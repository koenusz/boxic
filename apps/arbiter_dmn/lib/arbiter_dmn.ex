defmodule Arbiter.DMN do
  @moduledoc """
  Loads DMN XML into normalized model values and validates the model boundary.

  WP-08 deliberately separates XML normalization from execution. Namespace
  prefixes and `:xmerl` records are removed during loading; later work packages
  can therefore resolve and execute decisions against stable domain structs.
  """

  alias Arbiter.DMN.Model
  alias Arbiter.DMN.Model.Binding
  alias Arbiter.DMN.Model.BusinessKnowledgeModel
  alias Arbiter.DMN.Model.ContextEntry
  alias Arbiter.DMN.Model.ContextExpression
  alias Arbiter.DMN.Model.Decision
  alias Arbiter.DMN.Model.DecisionRule
  alias Arbiter.DMN.Model.DecisionService
  alias Arbiter.DMN.Model.DecisionTable
  alias Arbiter.DMN.Model.Definitions
  alias Arbiter.DMN.Model.FunctionDefinition
  alias Arbiter.DMN.Model.InformationRequirement
  alias Arbiter.DMN.Model.InputData
  alias Arbiter.DMN.Model.InputClause
  alias Arbiter.DMN.Model.Invocation
  alias Arbiter.DMN.Model.ItemComponent
  alias Arbiter.DMN.Model.ItemDefinition
  alias Arbiter.DMN.Model.LiteralExpression
  alias Arbiter.DMN.Model.OutputClause
  alias Arbiter.DMN.Model.Relation
  alias Arbiter.DMN.Model.RelationColumn
  alias Arbiter.DMN.Model.Variable

  @spec load(String.t()) :: {:ok, Model.t()} | {:error, term()}
  def load(path_or_xml) when is_binary(path_or_xml) do
    with {:ok, xml} <- read_xml(path_or_xml),
         {:ok, document} <- parse_xml(xml),
         :ok <- definitions_document?(document) do
      {:ok, build_model(document)}
    end
  end

  @spec validate(Model.t()) :: :ok | {:error, [term()]}
  def validate(%Model{} = model) do
    errors =
      model.issues ++
        validate_definitions(model.definitions) ++
        validate_input_data(model.input_data) ++
        validate_decisions(model.decisions) ++
        validate_bkms(model.bkms) ++
        validate_item_definitions(model.item_definitions) ++
        validate_decision_services(model) ++
        validate_unique_names(model) ++
        validate_references(model)

    case Enum.uniq(errors) do
      [] -> :ok
      errors -> {:error, errors}
    end
  end

  @spec evaluate(Model.t(), String.t(), map()) :: {:ok, term()} | {:error, term()}
  def evaluate(%Model{} = model, decision_name, context \\ %{})
      when is_binary(decision_name) and is_map(context) do
    with {:ok, decision} <- find_decision(model, decision_name),
         {:ok, value, _memo} <- evaluate_decision(model, decision, context, %{}, MapSet.new()) do
      {:ok, value}
    end
  end

  @spec evaluate_service(Model.t(), String.t(), map() | list()) ::
          {:ok, term()} | {:error, term()}
  def evaluate_service(%Model{} = model, service_name, arguments)
      when is_binary(service_name) and (is_map(arguments) or is_list(arguments)) do
    with {:ok, service} <- find_service(model, service_name) do
      args =
        if is_map(arguments),
          do: Enum.map(arguments, fn {name, value} -> {:named_arg, name, value} end),
          else: arguments

      invoke_decision_service(model, service, %{}, args)
    end
  end

  defp read_xml(path_or_xml) do
    if File.exists?(path_or_xml), do: File.read(path_or_xml), else: {:ok, path_or_xml}
  end

  defp parse_xml(xml) do
    try do
      {document, rest} =
        :xmerl_scan.string(:binary.bin_to_list(xml), namespace_conformant: true)

      if rest |> to_string() |> String.trim() == "",
        do: {:ok, document},
        else: {:error, :trailing_xml_content}
    rescue
      _ -> {:error, :invalid_xml}
    catch
      :exit, _ -> {:error, :invalid_xml}
    end
  end

  defp definitions_document?(document) do
    case nodes(document, "/*[local-name()='definitions']") do
      [_] -> :ok
      _ -> {:error, :invalid_definitions_document}
    end
  end

  defp build_model(document) do
    definitions = %Definitions{
      id: attr(document, "id"),
      name: attr(document, "name"),
      namespace: attr(document, "namespace"),
      expression_language: attr(document, "expressionLanguage"),
      type_language: attr(document, "typeLanguage")
    }

    {input_data, input_issues} =
      document |> nodes("./*[local-name()='inputData']") |> index_nodes(&parse_input_data/1)

    {decisions, decision_issues} =
      document |> nodes("./*[local-name()='decision']") |> index_nodes(&parse_decision/1)

    {bkms, bkm_issues} =
      document
      |> nodes("./*[local-name()='businessKnowledgeModel']")
      |> index_nodes(&parse_bkm/1)

    {decision_services, service_issues} =
      document
      |> nodes("./*[local-name()='decisionService']")
      |> index_nodes(&parse_decision_service/1)

    item_definitions =
      document
      |> nodes("./*[local-name()='itemDefinition']")
      |> Map.new(fn node ->
        item = parse_item_definition(node)
        {item.name, item}
      end)

    %Model{
      definitions: definitions,
      input_data: input_data,
      decisions: decisions,
      bkms: bkms,
      item_definitions: item_definitions,
      decision_services: decision_services,
      issues: input_issues ++ decision_issues ++ bkm_issues ++ service_issues
    }
  end

  defp parse_item_definition(node) do
    %ItemDefinition{
      id: attr(node, "id"),
      name: attr(node, "name"),
      type_ref: child_text_value(node, "typeRef"),
      allowed_values: child_text(node, "allowedValues"),
      is_collection: attr(node, "isCollection") == "true",
      components:
        Enum.map(nodes(node, "./*[local-name()='itemComponent']"), &parse_item_component/1)
    }
  end

  defp parse_item_component(node) do
    %ItemComponent{
      id: attr(node, "id"),
      name: attr(node, "name"),
      type_ref: child_text_value(node, "typeRef"),
      allowed_values: child_text(node, "allowedValues"),
      is_collection: attr(node, "isCollection") == "true",
      components:
        Enum.map(nodes(node, "./*[local-name()='itemComponent']"), &parse_item_component/1)
    }
  end

  defp parse_decision_service(node) do
    %DecisionService{
      id: attr(node, "id"),
      name: attr(node, "name"),
      variable: parse_variable(node),
      output_decisions: service_references(node, "outputDecision"),
      input_decisions: service_references(node, "inputDecision"),
      input_data: service_references(node, "inputData")
    }
  end

  defp service_references(node, child) do
    node
    |> nodes("./*[local-name()='#{child}']")
    |> Enum.map(&reference/1)
  end

  defp parse_bkm(node) do
    logic = node |> nodes("./*[local-name()='encapsulatedLogic']") |> List.first()

    expression =
      logic &&
        logic
        |> nodes("./*[not(local-name()='formalParameter') and not(local-name()='description')]")
        |> List.first()

    %BusinessKnowledgeModel{
      id: attr(node, "id"),
      name: attr(node, "name"),
      variable: parse_variable(node),
      parameters:
        if(logic,
          do: Enum.map(nodes(logic, "./*[local-name()='formalParameter']"), &parse_parameter/1),
          else: []
        ),
      expression: expression && parse_expression_node(expression)
    }
  end

  defp parse_parameter(node),
    do: %Variable{id: attr(node, "id"), name: attr(node, "name"), type_ref: attr(node, "typeRef")}

  defp parse_input_data(node) do
    %InputData{id: attr(node, "id"), name: attr(node, "name"), variable: parse_variable(node)}
  end

  defp parse_decision(node) do
    %Decision{
      id: attr(node, "id"),
      name: attr(node, "name"),
      variable: parse_variable(node),
      requirements: parse_requirements(node),
      expression: parse_expression(node)
    }
  end

  defp parse_variable(node) do
    case nodes(node, "./*[local-name()='variable']") do
      [variable | _] ->
        %Variable{
          id: attr(variable, "id"),
          name: attr(variable, "name"),
          type_ref: attr(variable, "typeRef")
        }

      [] ->
        nil
    end
  end

  defp parse_requirements(node) do
    information =
      node
      |> nodes("./*[local-name()='informationRequirement']")
      |> Enum.flat_map(fn requirement ->
        input =
          requirement
          |> nodes("./*[local-name()='requiredInput']")
          |> Enum.map(&%InformationRequirement{kind: :input_data, href: reference(&1)})

        decisions =
          requirement
          |> nodes("./*[local-name()='requiredDecision']")
          |> Enum.map(&%InformationRequirement{kind: :decision, href: reference(&1)})

        case input ++ decisions do
          [] -> [%InformationRequirement{}]
          references -> references
        end
      end)

    knowledge =
      node
      |> nodes("./*[local-name()='knowledgeRequirement']/*[local-name()='requiredKnowledge']")
      |> Enum.map(&%InformationRequirement{kind: :knowledge, href: reference(&1)})

    information ++ knowledge
  end

  defp parse_expression(node) do
    children =
      nodes(
        node,
        "./*[not(local-name()='description') and not(local-name()='question') and not(local-name()='allowedAnswers') and not(local-name()='variable') and not(local-name()='informationRequirement') and not(local-name()='knowledgeRequirement') and not(local-name()='authorityRequirement') and not(local-name()='extensionElements')]"
      )

    case children do
      [expression | _] ->
        parse_expression_node(expression)

      [] ->
        nil
    end
  end

  defp parse_expression_node(expression) do
    case local_name(expression) do
      "literalExpression" ->
        %LiteralExpression{
          id: attr(expression, "id"),
          text: text_child(expression),
          type_ref: attr(expression, "typeRef"),
          expression_language: attr(expression, "expressionLanguage") || "feel"
        }

      "decisionTable" ->
        parse_decision_table(expression)

      "context" ->
        %ContextExpression{
          id: attr(expression, "id"),
          entries:
            Enum.map(
              nodes(expression, "./*[local-name()='contextEntry']"),
              &parse_context_entry/1
            )
        }

      "invocation" ->
        parse_invocation(expression)

      "functionDefinition" ->
        body =
          expression
          |> nodes("./*[not(local-name()='formalParameter') and not(local-name()='description')]")
          |> List.first()

        %FunctionDefinition{
          id: attr(expression, "id"),
          parameters:
            Enum.map(nodes(expression, "./*[local-name()='formalParameter']"), &parse_parameter/1),
          body: body && parse_expression_node(body)
        }

      "relation" ->
        %Relation{
          id: attr(expression, "id"),
          columns:
            Enum.map(nodes(expression, "./*[local-name()='column']"), fn column ->
              %RelationColumn{
                id: attr(column, "id"),
                name: attr(column, "name"),
                type_ref: attr(column, "typeRef")
              }
            end),
          rows:
            Enum.map(nodes(expression, "./*[local-name()='row']"), fn row ->
              Enum.map(
                nodes(row, "./*[local-name()='literalExpression']"),
                &parse_expression_node/1
              )
            end)
        }

      kind ->
        {:unsupported, kind}
    end
  end

  defp parse_invocation(node) do
    function = node |> nodes("./*[local-name()='literalExpression']") |> List.first()

    %Invocation{
      id: attr(node, "id"),
      function: function && parse_expression_node(function),
      bindings: Enum.map(nodes(node, "./*[local-name()='binding']"), &parse_binding/1)
    }
  end

  defp parse_binding(node) do
    parameter = node |> nodes("./*[local-name()='parameter']") |> List.first()
    expression = node |> nodes("./*[local-name()='literalExpression']") |> List.first()

    %Binding{
      parameter: parameter && attr(parameter, "name"),
      expression: expression && parse_expression_node(expression)
    }
  end

  defp parse_context_entry(node) do
    expression =
      node
      |> nodes("./*[not(local-name()='variable') and not(local-name()='description')]")
      |> List.first()

    %ContextEntry{
      id: attr(node, "id"),
      variable: parse_variable(node),
      expression: expression && parse_expression_node(expression)
    }
  end

  defp parse_decision_table(node) do
    %DecisionTable{
      id: attr(node, "id"),
      hit_policy: node |> attr("hitPolicy") |> normalize_hit_policy(),
      aggregation: attr(node, "aggregation"),
      output_label: attr(node, "outputLabel"),
      inputs: Enum.map(nodes(node, "./*[local-name()='input']"), &parse_input_clause/1),
      outputs: Enum.map(nodes(node, "./*[local-name()='output']"), &parse_output_clause/1),
      rules: Enum.map(nodes(node, "./*[local-name()='rule']"), &parse_decision_rule/1)
    }
  end

  defp normalize_hit_policy(nil), do: "UNIQUE"
  defp normalize_hit_policy(value), do: String.replace(value, " ", "_")

  defp parse_input_clause(node) do
    expression = node |> nodes("./*[local-name()='inputExpression']") |> List.first()

    %InputClause{
      id: attr(node, "id"),
      label: attr(node, "label"),
      expression: expression && text_child(expression),
      type_ref: expression && attr(expression, "typeRef"),
      allowed_values: child_text(node, "inputValues")
    }
  end

  defp parse_output_clause(node) do
    %OutputClause{
      id: attr(node, "id"),
      name: attr(node, "name"),
      label: attr(node, "label"),
      type_ref: attr(node, "typeRef"),
      allowed_values: child_text(node, "outputValues"),
      default_output: child_text(node, "defaultOutputEntry")
    }
  end

  defp parse_decision_rule(node) do
    %DecisionRule{
      id: attr(node, "id"),
      input_entries: Enum.map(nodes(node, "./*[local-name()='inputEntry']"), &text_child/1),
      output_entries: Enum.map(nodes(node, "./*[local-name()='outputEntry']"), &text_child/1)
    }
  end

  defp index_nodes(nodes, parser) do
    Enum.reduce(nodes, {%{}, []}, fn node, {items, issues} ->
      item = parser.(node)

      cond do
        is_nil(item.id) -> {items, [{:missing_id, struct_name(item), item.name} | issues]}
        Map.has_key?(items, item.id) -> {items, [{:duplicate_id, item.id} | issues]}
        true -> {Map.put(items, item.id, item), issues}
      end
    end)
  end

  defp validate_definitions(%Definitions{} = definitions) do
    required(definitions, [:name, :namespace], :definitions)
  end

  defp validate_input_data(input_data) do
    Enum.flat_map(input_data, fn {id, input} ->
      required(input, [:name], {:input_data, id}) ++
        case input.variable do
          nil -> [{:missing_variable, {:input_data, id}}]
          variable -> validate_variable(variable, {:input_data, id})
        end
    end)
  end

  defp validate_decisions(decisions) when map_size(decisions) == 0, do: [:no_decisions]

  defp validate_decisions(decisions) do
    Enum.flat_map(decisions, fn {id, decision} ->
      required(decision, [:name], {:decision, id}) ++
        validate_variable(decision.variable, {:decision, id}) ++
        validate_expression(decision.expression, id)
    end)
  end

  defp validate_bkms(bkms) do
    Enum.flat_map(bkms, fn {id, bkm} ->
      required(bkm, [:name], {:bkm, id}) ++ validate_expression(bkm.expression, id)
    end)
  end

  defp validate_item_definitions(items) do
    Enum.flat_map(items, fn {name, item} ->
      required(item, [:name], {:item_definition, name}) ++
        validate_item_components(item.components, name)
    end)
  end

  defp validate_item_components(components, owner) do
    Enum.flat_map(components, fn component ->
      required(component, [:name], {:item_component, owner}) ++
        validate_item_components(component.components, "#{owner}.#{component.name}")
    end)
  end

  defp validate_decision_services(model) do
    Enum.flat_map(model.decision_services, fn {id, service} ->
      errors = required(service, [:name], {:decision_service, id})

      output_errors =
        Enum.flat_map(service.output_decisions, fn reference ->
          if Map.has_key?(model.decisions, reference),
            do: [],
            else: [{:unresolved_service_output, id, reference}]
        end)

      input_errors =
        Enum.flat_map(service.input_decisions, fn reference ->
          if Map.has_key?(model.decisions, reference),
            do: [],
            else: [{:unresolved_service_input, id, reference}]
        end) ++
          Enum.flat_map(service.input_data, fn reference ->
            if Map.has_key?(model.input_data, reference),
              do: [],
              else: [{:unresolved_service_input, id, reference}]
          end)

      errors ++ output_errors ++ input_errors
    end)
  end

  defp validate_variable(nil, _owner), do: []
  defp validate_variable(variable, owner), do: required(variable, [:name], {:variable, owner})

  defp validate_expression(nil, id), do: [{:missing_expression, id}]

  defp validate_expression(%LiteralExpression{text: nil}, id),
    do: [{:missing_expression_text, id}]

  defp validate_expression(%LiteralExpression{expression_language: language}, id)
       when language not in [
              nil,
              "feel",
              "https://www.omg.org/spec/DMN/20191111/FEEL/",
              "https://www.omg.org/spec/DMN/20230324/FEEL/"
            ] do
    [{:unsupported_expression_language, id, language}]
  end

  defp validate_expression(%LiteralExpression{}, _id), do: []
  defp validate_expression(%DecisionTable{} = table, id), do: validate_decision_table(table, id)
  defp validate_expression(%ContextExpression{} = context, id), do: validate_context(context, id)

  defp validate_expression(%Invocation{} = invocation, id),
    do: validate_invocation(invocation, id)

  defp validate_expression(%FunctionDefinition{} = function, id),
    do: validate_expression(function.body, "#{id}:function_body")

  defp validate_expression(%Relation{} = relation, id), do: validate_relation(relation, id)

  defp validate_expression({:unsupported, kind}, id), do: [{:unsupported_expression, id, kind}]

  defp validate_relation(%Relation{columns: columns, rows: rows}, id) do
    column_errors =
      Enum.flat_map(columns, &required(&1, [:name], {:relation_column, id}))

    row_errors =
      rows
      |> Enum.with_index()
      |> Enum.flat_map(fn {row, index} ->
        count_errors =
          if length(row) == length(columns),
            do: [],
            else: [{:invalid_relation_row_arity, id, index}]

        count_errors ++
          Enum.flat_map(row, &validate_expression(&1, "#{id}:relation:#{index}"))
      end)

    require_nonempty([], columns, {:relation, id, :columns}) ++
      require_nonempty([], rows, {:relation, id, :rows}) ++ column_errors ++ row_errors
  end

  defp validate_context(%ContextExpression{entries: []}, id),
    do: [{:missing_context_entries, id}]

  defp validate_context(%ContextExpression{entries: entries}, id) do
    last_index = length(entries) - 1

    entries
    |> Enum.with_index()
    |> Enum.flat_map(fn {entry, index} ->
      name_errors =
        if is_nil(entry.variable) and index != last_index,
          do: [{:unnamed_context_entry, id, index}],
          else: []

      name_errors ++ validate_expression(entry.expression, "#{id}:context:#{index}")
    end)
  end

  defp validate_invocation(invocation, id) do
    function_errors = validate_expression(invocation.function, "#{id}:function")

    binding_errors =
      Enum.flat_map(invocation.bindings, fn binding ->
        required(binding, [:parameter], {:invocation_binding, id}) ++
          validate_expression(binding.expression, "#{id}:binding:#{binding.parameter}")
      end)

    function_errors ++ binding_errors
  end

  defp validate_decision_table(table, decision_id) do
    errors =
      []
      |> require_nonempty(table.inputs, {:decision_table, decision_id, :inputs})
      |> require_nonempty(table.outputs, {:decision_table, decision_id, :outputs})
      |> require_nonempty(table.rules, {:decision_table, decision_id, :rules})

    rule_errors =
      Enum.flat_map(table.rules, fn rule ->
        []
        |> maybe_count_error(
          length(rule.input_entries),
          length(table.inputs),
          rule.id,
          :input_entries
        )
        |> maybe_count_error(
          length(rule.output_entries),
          length(table.outputs),
          rule.id,
          :output_entries
        )
      end)

    clause_errors =
      Enum.flat_map(table.inputs, fn input ->
        if is_binary(input.expression),
          do: [],
          else: [{:missing_input_expression, decision_id, input.id}]
      end)

    policy_errors = validate_hit_policy(table, decision_id)

    errors ++ rule_errors ++ clause_errors ++ policy_errors
  end

  defp require_nonempty(errors, [], owner), do: [{:missing_table_component, owner} | errors]
  defp require_nonempty(errors, _values, _owner), do: errors
  defp maybe_count_error(errors, count, count, _rule_id, _kind), do: errors

  defp maybe_count_error(errors, actual, expected, rule_id, kind),
    do: [{:entry_count_mismatch, rule_id, kind, expected, actual} | errors]

  defp validate_hit_policy(
         %DecisionTable{hit_policy: policy, aggregation: aggregation} = table,
         id
       ) do
    policies = ~w(UNIQUE FIRST ANY PRIORITY RULE_ORDER OUTPUT_ORDER COLLECT)
    aggregations = ~w(SUM MIN MAX COUNT)

    cond do
      policy not in policies ->
        [{:unsupported_hit_policy, id, policy}]

      policy == "COLLECT" and aggregation not in [nil | aggregations] ->
        [{:unsupported_collect_aggregation, id, aggregation}]

      policy == "COLLECT" and aggregation != nil and length(table.outputs) != 1 ->
        [{:collect_aggregation_requires_single_output, id, aggregation}]

      policy != "COLLECT" and aggregation != nil ->
        [{:aggregation_requires_collect, id, policy, aggregation}]

      true ->
        []
    end
  end

  defp validate_for_evaluation(model, decision) do
    errors =
      model.issues ++
        validate_definitions(model.definitions) ++
        required(decision, [:name], {:decision, decision.id}) ++
        validate_expression(decision.expression, decision.id)

    case Enum.uniq(errors) do
      [] -> :ok
      errors -> {:error, errors}
    end
  end

  defp evaluate_decision(model, decision, context, memo, visiting) do
    cond do
      Map.has_key?(memo, decision.id) ->
        {:ok, Map.fetch!(memo, decision.id), memo}

      MapSet.member?(visiting, decision.id) ->
        {:error, {:cyclic_decision_dependency, decision.id}}

      true ->
        visiting = MapSet.put(visiting, decision.id)

        with :ok <- validate_for_evaluation(model, decision),
             {:ok, dependency_context, memo} <-
               resolve_requirements(model, decision, context, memo, visiting),
             {:ok, value} <- evaluate_expression(decision.expression, dependency_context, model) do
          {:ok, value, Map.put(memo, decision.id, value)}
        else
          nil -> {:error, {:missing_expression, decision.id}}
          {:unsupported, kind} -> {:error, {:unsupported_expression, kind}}
          error -> error
        end
    end
  end

  defp evaluate_expression(%LiteralExpression{text: text}, context, _model)
       when is_binary(text) do
    {text, context} = normalize_feel_names(text, context)
    Arbiter.FEEL.evaluate(text, context)
  end

  defp evaluate_expression(%DecisionTable{} = table, context, _model),
    do: evaluate_table(table, context)

  defp evaluate_expression(%ContextExpression{} = expression, context, model),
    do: evaluate_context(expression, context, model)

  defp evaluate_expression(%Invocation{} = invocation, context, model),
    do: evaluate_invocation(invocation, context, model)

  defp evaluate_expression(%FunctionDefinition{} = function, context, model) do
    callable =
      {:external_function,
       fn args ->
         names = Enum.map(function.parameters, & &1.name)

         with {:ok, values} <- normalize_service_args(args, names) do
           evaluate_expression(
             function.body,
             Map.merge(context, Map.new(Enum.zip(names, values))),
             model
           )
         end
       end}

    {:ok, callable}
  end

  defp evaluate_expression(%Relation{} = relation, context, model) do
    names = Enum.map(relation.columns, & &1.name)

    relation.rows
    |> Enum.reduce_while({:ok, []}, fn row, {:ok, results} ->
      case Enum.reduce_while(row, {:ok, []}, fn expression, {:ok, values} ->
             case evaluate_expression(expression, context, model) do
               {:ok, value} -> {:cont, {:ok, values ++ [value]}}
               {:error, _reason} = error -> {:halt, error}
             end
           end) do
        {:ok, values} -> {:cont, {:ok, results ++ [Map.new(Enum.zip(names, values))]}}
        {:error, _reason} = error -> {:halt, error}
      end
    end)
  end

  defp evaluate_expression(nil, _context, _model), do: {:error, :missing_expression}

  defp evaluate_expression({:unsupported, kind}, _context, _model),
    do: {:error, {:unsupported_expression, kind}}

  defp evaluate_context(%ContextExpression{entries: entries}, outer_context, model) do
    entries
    |> Enum.with_index()
    |> Enum.reduce_while({:ok, %{}, outer_context}, fn {entry, index}, {:ok, result, scope} ->
      case evaluate_expression(entry.expression, scope, model) do
        {:ok, value} ->
          case entry.variable do
            %Variable{name: name} when is_binary(name) ->
              {:cont, {:ok, Map.put(result, name, value), Map.put(scope, name, value)}}

            nil when index == length(entries) - 1 ->
              {:halt, {:result, value}}

            _ ->
              {:halt, {:error, {:invalid_context_entry, index}}}
          end

        {:error, _reason} = error ->
          {:halt, error}
      end
    end)
    |> case do
      {:ok, result, _scope} -> {:ok, result}
      {:result, value} -> {:ok, value}
      error -> error
    end
  end

  defp resolve_requirements(model, decision, context, memo, visiting) do
    Enum.reduce_while(decision.requirements, {:ok, context, memo}, fn requirement,
                                                                      {:ok, acc, memo} ->
      case resolve_requirement(model, requirement, acc, memo, visiting) do
        {:ok, next_context, next_memo} -> {:cont, {:ok, next_context, next_memo}}
        {:error, _reason} = error -> {:halt, error}
      end
    end)
  end

  defp resolve_requirement(
         model,
         %InformationRequirement{kind: :decision, href: id},
         context,
         memo,
         visiting
       ) do
    with {:ok, dependency} <- fetch_reference(model.decisions, :decision, id) do
      case existing_node_value(context, dependency) do
        {:ok, value} ->
          {:ok, bind_value(context, dependency, value), memo}

        :error ->
          with {:ok, value, memo} <- evaluate_decision(model, dependency, context, memo, visiting) do
            {:ok, bind_value(context, dependency, value), memo}
          end
      end
    end
  end

  defp resolve_requirement(
         model,
         %InformationRequirement{kind: :knowledge, href: id},
         context,
         memo,
         _visiting
       ) do
    cond do
      Map.has_key?(model.bkms, id) ->
        bkm = Map.fetch!(model.bkms, id)

        callable =
          {:external_function, fn args -> invoke_bkm_from_feel(model, bkm, context, args) end}

        {:ok, bind_value(context, bkm, callable), memo}

      Map.has_key?(model.decision_services, id) ->
        service = Map.fetch!(model.decision_services, id)

        callable =
          {:external_function,
           fn args -> invoke_decision_service(model, service, context, args) end}

        {:ok, bind_value(context, service, callable), memo}

      true ->
        {:error, {:unresolved_reference, :knowledge, id}}
    end
  end

  defp resolve_requirement(
         model,
         %InformationRequirement{kind: :input_data, href: id},
         context,
         memo,
         _visiting
       ) do
    with {:ok, input} <- fetch_reference(model.input_data, :input_data, id),
         {:ok, value} <- input_value(context, input) do
      {:ok, bind_value(context, input, value), memo}
    end
  end

  defp resolve_requirement(_model, requirement, _context, _memo, _visiting),
    do: {:error, {:invalid_information_requirement, requirement}}

  defp fetch_reference(index, kind, id) do
    case Map.fetch(index, id) do
      {:ok, value} -> {:ok, value}
      :error -> {:error, {:unresolved_reference, kind, id}}
    end
  end

  defp input_value(context, input) do
    [input.name, input.variable && input.variable.name, input.id]
    |> Enum.reject(&is_nil/1)
    |> Enum.find_value(fn name ->
      case Map.fetch(context, name) do
        {:ok, value} -> {:found, value}
        :error -> nil
      end
    end)
    |> case do
      {:found, value} -> {:ok, value}
      nil -> {:error, {:missing_input, input.name || input.id}}
    end
  end

  defp existing_node_value(context, node) do
    [node.name, node.variable && node.variable.name, node.id]
    |> Enum.reject(&is_nil/1)
    |> Enum.find_value(fn key ->
      if Map.has_key?(context, key), do: {:found, Map.get(context, key)}
    end)
    |> case do
      {:found, value} -> {:ok, value}
      nil -> :error
    end
  end

  defp bind_value(context, node, value) do
    [node.name, node.variable && node.variable.name, node.id]
    |> Enum.reject(&is_nil/1)
    |> Enum.reduce(context, &Map.put(&2, &1, value))
  end

  defp evaluate_invocation(%Invocation{} = invocation, context, model) do
    with %LiteralExpression{text: function_name} when is_binary(function_name) <-
           invocation.function,
         {:ok, bkm} <- find_bkm(model, String.trim(function_name)),
         {:ok, bindings} <- evaluate_bindings(invocation.bindings, context, model),
         :ok <- validate_bkm_arguments(bkm, bindings) do
      evaluate_expression(bkm.expression, Map.merge(context, bindings), model)
    else
      nil -> {:error, :missing_invocation_function}
      error -> error
    end
  end

  defp invoke_bkm_from_feel(model, bkm, outer_context, args) do
    names = Enum.map(bkm.parameters, & &1.name)

    with {:ok, values} <- normalize_service_args(args, names) do
      evaluate_expression(
        bkm.expression,
        Map.merge(outer_context, Map.new(Enum.zip(names, values))),
        model
      )
    end
  end

  defp evaluate_bindings(bindings, context, model) do
    Enum.reduce_while(bindings, {:ok, %{}}, fn binding, {:ok, result} ->
      case evaluate_expression(binding.expression, context, model) do
        {:ok, value} -> {:cont, {:ok, Map.put(result, binding.parameter, value)}}
        {:error, _reason} = error -> {:halt, error}
      end
    end)
  end

  defp validate_bkm_arguments(bkm, bindings) do
    expected = Enum.map(bkm.parameters, & &1.name) |> MapSet.new()
    actual = Map.keys(bindings) |> MapSet.new()

    if expected == actual,
      do: :ok,
      else:
        {:error,
         {:bkm_argument_mismatch, bkm.name, MapSet.to_list(expected), MapSet.to_list(actual)}}
  end

  defp find_bkm(model, name_or_id) do
    case Map.fetch(model.bkms, name_or_id) do
      {:ok, bkm} ->
        {:ok, bkm}

      :error ->
        case Enum.find_value(model.bkms, fn {_id, bkm} -> bkm.name == name_or_id && bkm end) do
          nil -> {:error, {:bkm_not_found, name_or_id}}
          bkm -> {:ok, bkm}
        end
    end
  end

  defp invoke_decision_service(model, service, outer_context, args) do
    with {:ok, service_context} <- service_arguments(model, service, args, outer_context),
         {:ok, outputs, _memo} <-
           evaluate_service_outputs(model, service.output_decisions, service_context, %{}) do
      case outputs do
        [{_name, value}] -> {:ok, value}
        values -> {:ok, Map.new(values)}
      end
    end
  end

  defp find_service(model, name_or_id) do
    case Map.fetch(model.decision_services, name_or_id) do
      {:ok, service} ->
        {:ok, service}

      :error ->
        case Enum.find_value(model.decision_services, fn {_id, service} ->
               service.name == name_or_id && service
             end) do
          nil -> {:error, {:decision_service_not_found, name_or_id}}
          service -> {:ok, service}
        end
    end
  end

  defp service_arguments(model, service, args, outer_context) do
    references = service.input_data ++ service.input_decisions

    with {:ok, inputs} <- service_inputs(model, references),
         names = Enum.map(inputs, & &1.name),
         {:ok, values} <- normalize_service_args(args, names),
         :ok <- validate_service_types(inputs, values) do
      {:ok, Map.merge(outer_context, Map.new(Enum.zip(names, values)))}
    end
  end

  defp service_inputs(model, references) do
    Enum.reduce_while(references, {:ok, []}, fn id, {:ok, inputs} ->
      node = Map.get(model.input_data, id) || Map.get(model.decisions, id)

      if node,
        do: {:cont, {:ok, inputs ++ [node]}},
        else: {:halt, {:error, {:unresolved_service_input, id}}}
    end)
  end

  defp validate_service_types(inputs, values) do
    Enum.zip(inputs, values)
    |> Enum.reduce_while(:ok, fn {input, value}, :ok ->
      type_ref = input.variable && input.variable.type_ref

      if service_type?(type_ref, value),
        do: {:cont, :ok},
        else: {:halt, {:error, {:decision_service_type_error, input.name, type_ref}}}
    end)
  end

  defp service_type?(nil, _value), do: true
  defp service_type?(_type, nil), do: true
  defp service_type?("string", value), do: is_binary(value)
  defp service_type?("number", value), do: match?(%Decimal{}, value)
  defp service_type?("boolean", value), do: is_boolean(value)
  defp service_type?(_type, _value), do: true

  defp normalize_service_args(args, names) do
    if Enum.all?(args, &match?({:named_arg, _, _}, &1)) do
      values = Map.new(args, fn {:named_arg, name, value} -> {name, value} end)

      if Map.keys(values) |> MapSet.new() == MapSet.new(names),
        do: {:ok, Enum.map(names, &Map.fetch!(values, &1))},
        else: {:error, {:decision_service_argument_mismatch, names, Map.keys(values)}}
    else
      if length(args) == length(names),
        do: {:ok, args},
        else: {:error, {:decision_service_arity, length(names), length(args)}}
    end
  end

  defp evaluate_service_outputs(model, ids, context, memo) do
    Enum.reduce_while(ids, {:ok, [], memo}, fn id, {:ok, outputs, memo} ->
      case Map.fetch(model.decisions, id) do
        {:ok, decision} ->
          case evaluate_decision(model, decision, context, memo, MapSet.new()) do
            {:ok, value, memo} -> {:cont, {:ok, outputs ++ [{decision.name, value}], memo}}
            {:error, _reason} = error -> {:halt, error}
          end

        :error ->
          {:halt, {:error, {:unresolved_service_output, id}}}
      end
    end)
  end

  defp evaluate_table(%DecisionTable{} = table, context) do
    with {:ok, input_values} <- evaluate_table_inputs(table.inputs, context),
         {:ok, matches} <- matching_rules(table.rules, input_values, context),
         {:ok, results} <- evaluate_matched_outputs(matches, table.outputs, context) do
      reduce_hit_policy(table, matches, results, context)
    end
  end

  defp evaluate_matched_outputs(rules, outputs, context) do
    Enum.reduce_while(rules, {:ok, []}, fn rule, {:ok, values} ->
      case evaluate_rule_outputs(rule, outputs, context) do
        {:ok, value} -> {:cont, {:ok, values ++ [value]}}
        {:error, _reason} = error -> {:halt, error}
      end
    end)
  end

  defp reduce_hit_policy(table, _rules, [], context)
       when table.hit_policy in ~w(UNIQUE FIRST ANY PRIORITY),
       do: evaluate_default_outputs(table.outputs, context)

  defp reduce_hit_policy(%DecisionTable{hit_policy: "UNIQUE"}, rules, results, _context) do
    case results do
      [result] -> {:ok, result}
      _ -> {:error, {:unique_hit_policy_violation, Enum.map(rules, & &1.id)}}
    end
  end

  defp reduce_hit_policy(%DecisionTable{hit_policy: "FIRST"}, _rules, [result | _], _context),
    do: {:ok, result}

  defp reduce_hit_policy(%DecisionTable{hit_policy: "ANY"}, rules, [result | rest], _context) do
    if Enum.all?(rest, &(&1 == result)),
      do: {:ok, result},
      else: {:error, {:any_hit_policy_violation, Enum.map(rules, & &1.id)}}
  end

  defp reduce_hit_policy(%DecisionTable{hit_policy: "RULE_ORDER"}, _rules, results, _context),
    do: {:ok, results}

  defp reduce_hit_policy(
         %DecisionTable{hit_policy: "COLLECT", aggregation: nil},
         _rules,
         results,
         _context
       ),
       do: {:ok, results}

  defp reduce_hit_policy(
         %DecisionTable{hit_policy: "COLLECT", aggregation: aggregation},
         _rules,
         results,
         _context
       ),
       do: aggregate_collect(aggregation, results)

  defp reduce_hit_policy(%DecisionTable{hit_policy: policy} = table, _rules, results, context)
       when policy in ~w(PRIORITY OUTPUT_ORDER) do
    with {:ok, ordered} <- order_by_priority(table, results, context) do
      if policy == "PRIORITY", do: {:ok, List.first(ordered)}, else: {:ok, ordered}
    end
  end

  defp aggregate_collect("COUNT", results), do: {:ok, Decimal.new(length(results))}
  defp aggregate_collect(_aggregation, []), do: {:ok, nil}

  defp aggregate_collect("SUM", results) do
    if Enum.all?(results, &match?(%Decimal{}, &1)),
      do: {:ok, Enum.reduce(results, Decimal.new(0), &Decimal.add/2)},
      else: {:error, :collect_aggregation_requires_numbers}
  end

  defp aggregate_collect(aggregation, results) when aggregation in ~w(MIN MAX) do
    if Enum.all?(results, &match?(%Decimal{}, &1)) do
      chooser =
        case aggregation do
          "MIN" ->
            fn value, current ->
              if Decimal.compare(value, current) == :lt, do: value, else: current
            end

          "MAX" ->
            fn value, current ->
              if Decimal.compare(value, current) == :gt, do: value, else: current
            end
        end

      {:ok, Enum.reduce(results, chooser)}
    else
      {:error, :collect_aggregation_requires_numbers}
    end
  end

  defp order_by_priority(%DecisionTable{outputs: [priority_output | _]}, results, context) do
    with values when is_binary(values) <- priority_output.allowed_values,
         {:ok, priorities} <- evaluate_priority_values(values, context),
         ranked <- Enum.map(results, &rank_result(&1, priority_output, priorities)),
         true <- Enum.all?(ranked, &match?({rank, _} when is_integer(rank), &1)) do
      {:ok, ranked |> Enum.sort_by(&elem(&1, 0)) |> Enum.map(&elem(&1, 1))}
    else
      nil -> {:error, :missing_output_priorities}
      false -> {:error, :output_not_in_priority_values}
      {:error, _reason} = error -> error
    end
  end

  defp evaluate_priority_values(values, context) do
    {expression, bindings} = normalize_feel_names("[#{values}]", context)

    case Arbiter.FEEL.evaluate(expression, bindings) do
      {:ok, priorities} when is_list(priorities) -> {:ok, priorities}
      {:ok, _value} -> {:error, :invalid_output_priorities}
      error -> error
    end
  end

  defp rank_result(result, output, priorities) do
    value =
      if is_map(result),
        do: Map.get(result, output.name || output.label),
        else: result

    {Enum.find_index(priorities, &(&1 == value)), result}
  end

  defp evaluate_table_inputs(inputs, context) do
    Enum.reduce_while(inputs, {:ok, []}, fn input, {:ok, values} ->
      {expression, bindings} = normalize_feel_names(input.expression, context)

      case Arbiter.FEEL.evaluate(expression, bindings) do
        {:ok, value} -> {:cont, {:ok, values ++ [value]}}
        {:error, _reason} = error -> {:halt, error}
      end
    end)
  end

  defp matching_rules(rules, input_values, context) do
    Enum.reduce_while(rules, {:ok, []}, fn rule, {:ok, matches} ->
      case rule_matches?(rule, input_values, context) do
        {:ok, true} -> {:cont, {:ok, matches ++ [rule]}}
        {:ok, false} -> {:cont, {:ok, matches}}
        {:error, _reason} = error -> {:halt, error}
      end
    end)
  end

  defp rule_matches?(rule, input_values, context) do
    Enum.zip(rule.input_entries, input_values)
    |> Enum.reduce_while({:ok, true}, fn {test, value}, {:ok, true} ->
      case evaluate_unary_tests(test, value, context) do
        {:ok, true} -> {:cont, {:ok, true}}
        {:ok, false} -> {:halt, {:ok, false}}
        {:error, _reason} = error -> {:halt, error}
      end
    end)
  end

  defp evaluate_unary_tests(text, value, context) do
    text
    |> split_unary_tests()
    |> Enum.reduce_while({:ok, false}, fn test, {:ok, false} ->
      case Arbiter.FEEL.evaluate_unary_test(test, value, context) do
        {:ok, true} -> {:halt, {:ok, true}}
        {:ok, false} -> {:cont, {:ok, false}}
        {:error, _reason} = error -> {:halt, error}
      end
    end)
  end

  defp split_unary_tests(text) do
    Regex.split(~r/,(?=(?:[^"]*"[^"]*")*[^"]*$)/, text, trim: true)
    |> Enum.map(&String.trim/1)
  end

  defp evaluate_rule_outputs(rule, outputs, context) do
    with {:ok, values} <- evaluate_output_entries(rule.output_entries, context) do
      shape_output(outputs, values)
    end
  end

  defp evaluate_default_outputs(outputs, context) do
    defaults = Enum.map(outputs, & &1.default_output)

    if Enum.all?(defaults, &is_binary/1) do
      with {:ok, values} <- evaluate_output_entries(defaults, context),
           do: shape_output(outputs, values)
    else
      {:ok, nil}
    end
  end

  defp evaluate_output_entries(entries, context) do
    Enum.reduce_while(entries, {:ok, []}, fn expression, {:ok, values} ->
      {expression, bindings} = normalize_feel_names(expression, context)

      case Arbiter.FEEL.evaluate(expression, bindings) do
        {:ok, value} -> {:cont, {:ok, values ++ [value]}}
        {:error, _reason} = error -> {:halt, error}
      end
    end)
  end

  defp shape_output([_output], [value]), do: {:ok, value}

  defp shape_output(outputs, values) do
    names = Enum.map(outputs, &(&1.name || &1.label))

    if Enum.all?(names, &is_binary/1),
      do: {:ok, names |> Enum.zip(values) |> Map.new()},
      else: {:error, :unnamed_multiple_outputs}
  end

  # FEEL names may contain spaces and reserved words. The dependency graph gives
  # us the exact declared names, so compile those names to unambiguous evaluator
  # bindings before parsing the literal expression.
  defp normalize_feel_names(expression, context) do
    context
    |> Map.keys()
    |> Enum.filter(&(is_binary(&1) and String.contains?(&1, " ")))
    |> Enum.sort_by(&String.length/1, :desc)
    |> Enum.with_index()
    |> Enum.reduce({expression, context}, fn {name, index}, {source, bindings} ->
      alias_name = "__dmn_name_#{index}"

      pattern =
        Regex.compile!("(?<![\\p{L}\\p{N}_])#{Regex.escape(name)}(?![\\p{L}\\p{N}_])", "u")

      if Regex.match?(pattern, source) do
        {Regex.replace(pattern, source, alias_name),
         Map.put(bindings, alias_name, Map.fetch!(bindings, name))}
      else
        {source, bindings}
      end
    end)
  end

  defp validate_unique_names(model) do
    (Map.values(model.input_data) ++ Map.values(model.decisions) ++ Map.values(model.bkms))
    |> Enum.reject(&is_nil(&1.name))
    |> Enum.group_by(& &1.name)
    |> Enum.flat_map(fn
      {_name, [_]} -> []
      {name, values} -> [{:duplicate_name, name, Enum.map(values, & &1.id)}]
    end)
  end

  defp validate_references(model) do
    Enum.flat_map(model.decisions, fn {decision_id, decision} ->
      Enum.flat_map(decision.requirements, fn requirement ->
        target =
          case requirement.kind do
            :input_data -> model.input_data
            :decision -> model.decisions
            :knowledge -> Map.merge(model.bkms, model.decision_services)
            nil -> %{}
          end

        if is_binary(requirement.href) and Map.has_key?(target, requirement.href),
          do: [],
          else: [{:unresolved_reference, decision_id, requirement.kind, requirement.href}]
      end)
    end)
  end

  defp required(value, fields, owner) do
    Enum.flat_map(fields, fn field ->
      if Map.get(value, field) in [nil, ""], do: [{:missing_attribute, owner, field}], else: []
    end)
  end

  defp find_decision(model, name_or_id) do
    case Map.fetch(model.decisions, name_or_id) do
      {:ok, decision} ->
        {:ok, decision}

      :error ->
        case Enum.find_value(model.decisions, fn {_id, decision} ->
               decision.name == name_or_id && decision
             end) do
          nil -> {:error, {:decision_not_found, name_or_id}}
          decision -> {:ok, decision}
        end
    end
  end

  defp reference(node) do
    case attr(node, "href") do
      "#" <> id -> id
      href -> href
    end
  end

  defp text_child(node), do: xpath_string(node, "./*[local-name()='text']")

  defp child_text(node, child),
    do: xpath_string(node, "./*[local-name()='#{child}']/*[local-name()='text']")

  defp child_text_value(node, child),
    do: xpath_string(node, "./*[local-name()='#{child}']/text()")

  defp attr(node, name), do: xpath_string(node, "./@*[local-name()='#{name}']")
  defp nodes(node, path), do: :xmerl_xpath.string(String.to_charlist(path), node)

  defp xpath_string(node, path) do
    query = ~c"string(" ++ String.to_charlist(path) ++ ~c")"

    case :xmerl_xpath.string(query, node) do
      {:xmlObj, :string, value} -> value |> to_string() |> String.trim() |> empty_to_nil()
      value -> value |> to_string() |> String.trim() |> empty_to_nil()
    end
  end

  defp local_name(node) do
    node |> xpath_string("local-name(.)")
  end

  defp struct_name(%module{}),
    do: module |> Module.split() |> List.last() |> Macro.underscore() |> String.to_atom()

  defp empty_to_nil(""), do: nil
  defp empty_to_nil(value), do: value
end
