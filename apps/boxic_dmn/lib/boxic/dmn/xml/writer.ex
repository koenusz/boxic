defmodule Boxic.DMN.XML.Writer do
  @moduledoc false

  alias Boxic.DMN.Compatibility
  alias Boxic.DMN.Model

  alias Boxic.DMN.Model.{
    Binding,
    BusinessKnowledgeModel,
    ConditionalExpression,
    ContextEntry,
    ContextExpression,
    Decision,
    DecisionRule,
    DecisionService,
    DecisionTable,
    FilterExpression,
    FunctionDefinition,
    InformationRequirement,
    InputClause,
    InputData,
    Invocation,
    Import,
    ItemComponent,
    ItemDefinition,
    IteratorExpression,
    ListExpression,
    LiteralExpression,
    OutputClause,
    Relation,
    RelationColumn,
    Variable
  }

  alias Boxic.DMN.SerializationError
  alias Boxic.DMN.XML.{Element, Emitter, SerializationValidator}

  @spec encode(Model.t(), keyword()) ::
          {:ok, String.t()} | {:error, [SerializationError.t()]}
  def encode(model, opts \\ []) do
    with :ok <- SerializationValidator.validate(model, opts) do
      try do
        opts = Keyword.merge(default_options(), opts)
        xml = model |> definitions_element() |> Emitter.emit(opts) |> IO.iodata_to_binary()
        {:ok, xml}
      rescue
        error ->
          {:error,
           [
             %SerializationError{
               code: :xml_encoding_failed,
               path: [],
               message: "The normalized model could not be encoded as XML.",
               details: %{exception: error.__struct__}
             }
           ]}
      end
    end
  end

  @spec validate_serializable(Model.t(), keyword()) ::
          :ok | {:error, [SerializationError.t()]}
  def validate_serializable(model, opts \\ []),
    do: SerializationValidator.validate(model, opts)

  defp default_options, do: [format: :pretty, xml_declaration: true]

  defp definitions_element(%Model{} = model) do
    profile = Compatibility.pinned_profile()
    definitions = model.definitions

    element(
      "definitions",
      attrs([
        {"xmlns", profile.model_namespace},
        {"id", definitions.id},
        {"name", definitions.name},
        {"namespace", definitions.namespace},
        {"expressionLanguage", definitions.expression_language},
        {"typeLanguage", definitions.type_language}
      ]),
      imports(model.imports) ++
        sorted_values(model.item_definitions, &item_definition/1) ++
        sorted_values(model.input_data, &input_data/1) ++
        sorted_values(model.bkms, &business_knowledge_model/1) ++
        sorted_values(model.decisions, &decision/1) ++
        sorted_values(model.decision_services, &decision_service/1)
    )
  end

  defp imports(imports) do
    imports
    |> Enum.sort_by(fn {namespace, import} -> {namespace || "", import.name || ""} end)
    |> Enum.map(fn {_namespace, %Import{} = import} ->
      element(
        "import",
        attrs([
          {"name", import.name},
          {"namespace", import.namespace},
          {"locationURI", import.location_uri},
          {"importType", import.import_type}
        ])
      )
    end)
  end

  defp item_definition(%ItemDefinition{} = item) do
    element(
      "itemDefinition",
      attrs([
        {"id", item.id},
        {"name", item.name},
        {"isCollection", boolean_attribute(item.is_collection)}
      ]),
      optional_text_value("typeRef", item.type_ref) ++
        optional_text_container("allowedValues", item.allowed_values) ++
        Enum.map(item.components, &item_component/1)
    )
  end

  defp item_component(%ItemComponent{} = item) do
    element(
      "itemComponent",
      attrs([
        {"id", item.id},
        {"name", item.name},
        {"isCollection", boolean_attribute(item.is_collection)}
      ]),
      optional_text_value("typeRef", item.type_ref) ++
        optional_text_container("allowedValues", item.allowed_values) ++
        Enum.map(item.components, &item_component/1)
    )
  end

  defp input_data(%InputData{} = input) do
    element(
      "inputData",
      attrs([{"id", input.id}, {"name", input.name}]),
      optional(input.variable, &variable/1)
    )
  end

  defp decision(%Decision{} = decision) do
    element(
      "decision",
      attrs([{"id", decision.id}, {"name", decision.name}]),
      optional(decision.variable, &variable/1) ++
        Enum.map(decision.requirements, &requirement/1) ++
        optional(decision.expression, &expression/1)
    )
  end

  defp business_knowledge_model(%BusinessKnowledgeModel{} = bkm) do
    logic_children =
      Enum.map(bkm.parameters, &formal_parameter/1) ++ optional(bkm.expression, &expression/1)

    element(
      "businessKnowledgeModel",
      attrs([{"id", bkm.id}, {"name", bkm.name}]),
      optional(bkm.variable, &variable/1) ++
        Enum.map(bkm.requirements, &requirement/1) ++
        [element("encapsulatedLogic", [], logic_children)]
    )
  end

  defp decision_service(%DecisionService{} = service) do
    children =
      optional(service.variable, &variable/1) ++
        Enum.map(service.output_decisions, &reference_element("outputDecision", &1)) ++
        Enum.map(service.input_decisions, &reference_element("inputDecision", &1)) ++
        Enum.map(service.input_data, &reference_element("inputData", &1))

    element("decisionService", attrs([{"id", service.id}, {"name", service.name}]), children)
  end

  defp variable(%Variable{} = variable) do
    element(
      "variable",
      attrs([{"id", variable.id}, {"name", variable.name}, {"typeRef", variable.type_ref}])
    )
  end

  defp formal_parameter(%Variable{} = parameter) do
    element(
      "formalParameter",
      attrs([{"id", parameter.id}, {"name", parameter.name}, {"typeRef", parameter.type_ref}])
    )
  end

  defp requirement(%InformationRequirement{kind: :input_data, href: href}) do
    element("informationRequirement", [], [reference_element("requiredInput", href)])
  end

  defp requirement(%InformationRequirement{kind: :decision, href: href}) do
    element("informationRequirement", [], [reference_element("requiredDecision", href)])
  end

  defp requirement(%InformationRequirement{kind: :knowledge, href: href}) do
    element("knowledgeRequirement", [], [reference_element("requiredKnowledge", href)])
  end

  defp requirement(%InformationRequirement{}) do
    element("informationRequirement")
  end

  defp reference_element(name, href),
    do: element(name, attrs([{"href", reference_href(href)}]))

  defp reference_href(nil), do: nil

  defp reference_href(href) when is_binary(href) do
    if String.contains?(href, "#"), do: href, else: "#" <> href
  end

  defp expression(%LiteralExpression{} = expression) do
    element(
      "literalExpression",
      attrs([
        {"id", expression.id},
        {"typeRef", expression.type_ref},
        {"expressionLanguage", expression_language(expression.expression_language)}
      ]),
      optional_text_element(expression.text)
    )
  end

  defp expression(%DecisionTable{} = table), do: decision_table(table)

  defp expression(%ContextExpression{} = context) do
    element("context", attrs([{"id", context.id}]), Enum.map(context.entries, &context_entry/1))
  end

  defp expression(%Invocation{} = invocation) do
    element(
      "invocation",
      attrs([{"id", invocation.id}, {"typeRef", invocation.type_ref}]),
      optional(invocation.function, &expression/1) ++
        Enum.map(invocation.bindings, &binding_element/1)
    )
  end

  defp expression(%FunctionDefinition{} = function) do
    element(
      "functionDefinition",
      attrs([{"id", function.id}]),
      Enum.map(function.parameters, &formal_parameter/1) ++ optional(function.body, &expression/1)
    )
  end

  defp expression(%Relation{} = relation) do
    element(
      "relation",
      attrs([{"id", relation.id}]),
      Enum.map(relation.columns, &relation_column/1) ++
        Enum.map(relation.rows, fn row -> element("row", [], Enum.map(row, &expression/1)) end)
    )
  end

  defp expression(%ListExpression{} = list) do
    element("list", attrs([{"id", list.id}]), Enum.map(list.items, &expression/1))
  end

  defp expression(%ConditionalExpression{} = conditional) do
    element(
      "conditional",
      attrs([{"id", conditional.id}]),
      boxed_children([
        {"if", conditional.condition},
        {"then", conditional.then_branch},
        {"else", conditional.else_branch}
      ])
    )
  end

  defp expression(%FilterExpression{} = filter) do
    element(
      "filter",
      attrs([{"id", filter.id}]),
      boxed_children([{"in", filter.source}, {"match", filter.match}])
    )
  end

  defp expression(%IteratorExpression{} = iterator) do
    {name, body_name} =
      case iterator.kind do
        :for -> {"for", "return"}
        :some -> {"some", "satisfies"}
        :every -> {"every", "satisfies"}
      end

    element(
      name,
      attrs([{"id", iterator.id}, {"iteratorVariable", iterator_variable(iterator.variable)}]),
      boxed_children([{"in", iterator.source}, {body_name, iterator.body}])
    )
  end

  defp iterator_variable(%Variable{name: name}), do: name
  defp iterator_variable(name) when is_binary(name), do: name
  defp iterator_variable(nil), do: nil

  defp boxed_children(pairs) do
    Enum.map(pairs, fn {name, value} -> element(name, [], optional(value, &expression/1)) end)
  end

  defp context_entry(%ContextEntry{} = entry) do
    element(
      "contextEntry",
      attrs([{"id", entry.id}]),
      optional(entry.variable, &variable/1) ++ optional(entry.expression, &expression/1)
    )
  end

  defp binding_element(%Binding{} = binding) do
    element(
      "binding",
      [],
      [element("parameter", attrs([{"name", binding.parameter}]))] ++
        optional(binding.expression, &expression/1)
    )
  end

  defp relation_column(%RelationColumn{} = column) do
    element(
      "column",
      attrs([{"id", column.id}, {"name", column.name}, {"typeRef", column.type_ref}])
    )
  end

  defp decision_table(%DecisionTable{} = table) do
    element(
      "decisionTable",
      attrs([
        {"id", table.id},
        {"hitPolicy", emitted_hit_policy(table.hit_policy)},
        {"aggregation", table.aggregation},
        {"outputLabel", table.output_label}
      ]),
      Enum.map(table.inputs, &input_clause/1) ++
        Enum.map(table.outputs, &output_clause/1) ++ Enum.map(table.rules, &decision_rule/1)
    )
  end

  defp input_clause(%InputClause{} = input) do
    input_expression =
      element(
        "inputExpression",
        attrs([{"typeRef", input.type_ref}]),
        optional_text_element(input.expression)
      )

    element(
      "input",
      attrs([{"id", input.id}, {"label", input.label}]),
      [input_expression] ++ optional_text_container("inputValues", input.allowed_values)
    )
  end

  defp output_clause(%OutputClause{} = output) do
    element(
      "output",
      attrs([
        {"id", output.id},
        {"name", output.name},
        {"label", output.label},
        {"typeRef", output.type_ref}
      ]),
      optional_text_container("outputValues", output.allowed_values) ++
        optional_text_container("defaultOutputEntry", output.default_output)
    )
  end

  defp decision_rule(%DecisionRule{} = rule) do
    element(
      "rule",
      attrs([{"id", rule.id}]),
      Enum.map(rule.input_entries, &text_container("inputEntry", &1)) ++
        Enum.map(rule.output_entries, &text_container("outputEntry", &1))
    )
  end

  defp expression_language(nil), do: nil
  defp expression_language("feel"), do: nil
  defp expression_language(value), do: value

  defp emitted_hit_policy(nil), do: nil
  defp emitted_hit_policy("UNIQUE"), do: nil
  defp emitted_hit_policy(value), do: String.replace(value, "_", " ")

  defp boolean_attribute(true), do: "true"
  defp boolean_attribute(false), do: nil
  defp boolean_attribute(nil), do: nil

  defp optional(nil, _fun), do: []
  defp optional(value, fun), do: [fun.(value)]

  defp optional_text_element(nil), do: []
  defp optional_text_element(value), do: [element("text", [], [{:text, value}])]

  defp optional_text_value(_name, nil), do: []
  defp optional_text_value(name, value), do: [element(name, [], [{:text, value}])]

  defp optional_text_container(_name, nil), do: []
  defp optional_text_container(name, value), do: [text_container(name, value)]

  defp text_container(name, value),
    do: element(name, [], [element("text", [], [{:text, value}])])

  defp attrs(values), do: Enum.reject(values, fn {_name, value} -> is_nil(value) end)

  defp sorted_values(map, mapper) do
    map
    |> Enum.sort_by(fn {key, value} -> {value.id || "", key || ""} end)
    |> Enum.map(fn {_key, value} -> mapper.(value) end)
  end

  defp element(name, attrs \\ [], children \\ []),
    do: %Element{name: name, attrs: attrs, children: children}
end
