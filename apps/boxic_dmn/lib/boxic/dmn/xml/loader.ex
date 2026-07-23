defmodule Boxic.DMN.XML.Loader do
  @moduledoc false
  alias Boxic.DMN.Model
  alias Boxic.DMN.Model.Binding
  alias Boxic.DMN.Model.BusinessKnowledgeModel
  alias Boxic.DMN.Model.ContextEntry
  alias Boxic.DMN.Model.ContextExpression
  alias Boxic.DMN.Model.ConditionalExpression
  alias Boxic.DMN.Model.Decision
  alias Boxic.DMN.Model.DecisionRule
  alias Boxic.DMN.Model.DecisionService
  alias Boxic.DMN.Model.DecisionTable
  alias Boxic.DMN.Model.Definitions
  alias Boxic.DMN.Model.FunctionDefinition
  alias Boxic.DMN.Model.FilterExpression
  alias Boxic.DMN.Model.InformationRequirement
  alias Boxic.DMN.Model.Import
  alias Boxic.DMN.Model.InputData
  alias Boxic.DMN.Model.InputClause
  alias Boxic.DMN.Model.Invocation
  alias Boxic.DMN.Model.IteratorExpression
  alias Boxic.DMN.Model.ItemComponent
  alias Boxic.DMN.Model.ItemDefinition
  alias Boxic.DMN.Model.LiteralExpression
  alias Boxic.DMN.Model.ListExpression
  alias Boxic.DMN.Model.OutputClause
  alias Boxic.DMN.Model.Relation
  alias Boxic.DMN.Model.RelationColumn
  alias Boxic.DMN.Model.Variable
  alias Boxic.DMN.Compatibility
  alias Boxic.DMN.Diagnostic
  alias Boxic.DMN.Imports
  alias Boxic.DMN.Validator
  alias Boxic.DMN.XML.SchemaValidator

  @normalized_element_names ~w(
    definitions import itemDefinition itemComponent typeRef allowedValues
    inputData variable decision informationRequirement requiredInput
    requiredDecision knowledgeRequirement requiredKnowledge
    businessKnowledgeModel encapsulatedLogic formalParameter decisionService
    outputDecision inputDecision inputData literalExpression text decisionTable
    input inputExpression inputValues output outputValues defaultOutputEntry
    rule inputEntry outputEntry context contextEntry invocation binding parameter
    functionDefinition relation column row list conditional if then else filter
    in match for some every return satisfies description documentation extensionElements
    authorityRequirement annotationClause annotationEntry DMNDI DMNDiagram
    encapsulatedDecision
  )

  @retained_attributes %{
    "definitions" => ~w(id name namespace expressionLanguage typeLanguage),
    "import" => ~w(name namespace locationURI importType),
    "itemDefinition" => ~w(id name isCollection),
    "itemComponent" => ~w(id name isCollection),
    "inputData" => ~w(id name),
    "variable" => ~w(id name typeRef),
    "decision" => ~w(id name),
    "informationRequirement" => [],
    "requiredInput" => ~w(href),
    "requiredDecision" => ~w(href),
    "knowledgeRequirement" => [],
    "requiredKnowledge" => ~w(href),
    "businessKnowledgeModel" => ~w(id name),
    "encapsulatedLogic" => [],
    "formalParameter" => ~w(id name typeRef),
    "decisionService" => ~w(id name),
    "outputDecision" => ~w(href),
    "inputDecision" => ~w(href),
    "literalExpression" => ~w(id typeRef expressionLanguage),
    "decisionTable" => ~w(id hitPolicy aggregation outputLabel),
    "input" => ~w(id label),
    "inputExpression" => ~w(typeRef),
    "output" => ~w(id name label typeRef),
    "rule" => ~w(id),
    "context" => ~w(id),
    "contextEntry" => ~w(id),
    "invocation" => ~w(id typeRef),
    "parameter" => ~w(name),
    "functionDefinition" => ~w(id),
    "relation" => ~w(id),
    "column" => ~w(id name typeRef),
    "list" => ~w(id),
    "conditional" => ~w(id),
    "filter" => ~w(id),
    "for" => ~w(id iteratorVariable),
    "some" => ~w(id iteratorVariable),
    "every" => ~w(id iteratorVariable)
  }

  @doc """
  Loads a DMN document from either an XML string or a file path.

  New code should prefer `load_xml/1` or `load_file/1`, which avoid input
  ambiguity.
  """
  @spec load(String.t()) :: {:ok, Model.t()} | {:error, load_error()}
  def load(path_or_xml) when is_binary(path_or_xml) do
    if xml_input?(path_or_xml), do: load_xml(path_or_xml), else: load_file(path_or_xml)
  end

  @typedoc "An error returned while reading or decoding a DMN document."
  @type load_error ::
          {:file_error, Path.t(), File.posix()}
          | :invalid_xml
          | :trailing_xml_content
          | :invalid_definitions_document

  @doc "Loads a DMN document and the local files it explicitly imports."
  @spec load_file(Path.t()) :: {:ok, Model.t()} | {:error, load_error() | [Diagnostic.t()]}
  def load_file(path) when is_binary(path) do
    expanded_path = Path.expand(path)
    import_root = Path.dirname(expanded_path)

    with {:ok, model} <- load_source_file(expanded_path),
         {:ok, imported_models} <-
           resolve_file_imports(model, expanded_path, import_root, MapSet.new([expanded_path])),
         merged = Imports.merge(model, imported_models),
         :ok <- validate_model(merged) do
      {:ok, merged}
    end
  end

  @doc "Loads a strictly validated DMN 1.5 document from an XML string."
  @spec load_xml(String.t()) :: {:ok, Model.t()} | {:error, [Diagnostic.t()]}
  def load_xml(xml) when is_binary(xml), do: load_xml(xml, imports: %{})

  @doc """
  Loads DMN XML with an explicit import source.

  `:imports` may be a namespace-keyed map whose values are DMN XML binaries or
  already inspected models. `:resolver` may be a one-argument function that
  receives the normalized import declaration and returns either form.
  """
  @spec load_xml(String.t(), keyword()) :: {:ok, Model.t()} | {:error, [Diagnostic.t()]}
  def load_xml(xml, opts) when is_binary(xml) and is_list(opts) do
    with {:ok, model} <- load_source_xml(xml),
         {:ok, imported_models} <-
           resolve_explicit_imports(model, opts, MapSet.new([model.definitions.namespace])),
         merged = Imports.merge(model, imported_models),
         :ok <- validate_model(merged) do
      {:ok, merged}
    end
  end

  defp load_source_file(path) do
    with {:ok, xml} <- read_file(path), do: load_source_xml(xml)
  end

  defp load_source_xml(xml) do
    with {:ok, model} <- inspect_xml(xml),
         :ok <- validate_profile(model),
         :ok <- SchemaValidator.validate(xml) do
      {:ok, model}
    end
  end

  defp resolve_file_imports(model, importing_path, import_root, active_paths) do
    model.imports
    |> Map.values()
    |> Enum.reduce_while({:ok, []}, fn import, {:ok, models} ->
      with :ok <- validate_import_type(import, model),
           {:ok, imported_path} <- local_import_path(import, importing_path, import_root, model),
           :ok <- reject_import_cycle(imported_path, active_paths, model),
           {:ok, imported} <- load_source_file(imported_path),
           :ok <- validate_import_namespace(import, imported, model),
           {:ok, transitive} <-
             resolve_file_imports(
               imported,
               imported_path,
               import_root,
               MapSet.put(active_paths, imported_path)
             ) do
        {:cont, {:ok, models ++ [imported | transitive]}}
      else
        {:error, _diagnostics} = error -> {:halt, error}
      end
    end)
  end

  defp resolve_explicit_imports(model, opts, active_namespaces) do
    imports = Keyword.get(opts, :imports, %{})
    resolver = Keyword.get(opts, :resolver)

    model.imports
    |> Map.values()
    |> Enum.reduce_while({:ok, []}, fn import, {:ok, models} ->
      with :ok <- validate_import_type(import, model),
           :ok <- reject_namespace_cycle(import.namespace, active_namespaces, model),
           {:ok, source} <- explicit_import_source(import, imports, resolver, model),
           {:ok, imported} <- normalize_import_source(source, model, import),
           :ok <- validate_import_namespace(import, imported, model),
           {:ok, transitive} <-
             resolve_explicit_imports(
               imported,
               opts,
               MapSet.put(active_namespaces, import.namespace)
             ) do
        {:cont, {:ok, models ++ [imported | transitive]}}
      else
        {:error, _diagnostics} = error -> {:halt, error}
      end
    end)
  end

  defp explicit_import_source(import, imports, resolver, model) do
    case Map.fetch(imports, import.namespace) do
      {:ok, source} ->
        {:ok, source}

      :error when is_function(resolver, 1) ->
        case resolver.(import) do
          {:ok, source} ->
            {:ok, source}

          {:error, reason} ->
            import_error(
              :import_resolver_error,
              import,
              model,
              "The explicit import resolver rejected the declaration.",
              %{reason: reason}
            )

          other ->
            import_error(
              :invalid_import_resolver_result,
              import,
              model,
              "The explicit import resolver returned an invalid result.",
              %{result: other}
            )
        end

      :error ->
        import_error(
          :missing_import,
          import,
          model,
          "No explicit source was supplied for the declared import."
        )
    end
  end

  defp normalize_import_source(%Model{} = imported, _model, _import) do
    with :ok <- validate_profile(imported), do: {:ok, imported}
  end

  defp normalize_import_source(xml, _model, _import) when is_binary(xml),
    do: load_source_xml(xml)

  defp normalize_import_source(source, model, import) do
    import_error(
      :invalid_import_source,
      import,
      model,
      "An import source must be DMN XML or an inspected model.",
      %{source: source}
    )
  end

  defp reject_namespace_cycle(namespace, active_namespaces, model) do
    if MapSet.member?(active_namespaces, namespace) do
      {:error,
       [
         %Diagnostic{
           code: :import_cycle,
           category: :import,
           path: [:imports, namespace],
           message: "The declared import graph contains a namespace cycle.",
           specification: "DMN 1.5",
           source_profile: model.source_profile,
           details: %{namespace: namespace}
         }
       ]}
    else
      :ok
    end
  end

  defp validate_import_type(import, model) do
    expected = Compatibility.pinned_profile().model_namespace

    if import.import_type == expected do
      :ok
    else
      import_error(
        :unsupported_import_type,
        import,
        model,
        "Only DMN 1.5 model imports are executable.",
        %{actual: import.import_type, expected: expected}
      )
    end
  end

  defp local_import_path(import, importing_path, import_root, model) do
    location = import.location_uri

    cond do
      location in [nil, ""] ->
        import_error(
          :missing_import_location,
          import,
          model,
          "A local file import requires locationURI."
        )

      Path.type(location) == :absolute or Regex.match?(~r/^[A-Za-z][A-Za-z0-9+.-]*:/, location) ->
        import_error(
          :external_import_forbidden,
          import,
          model,
          "Network and absolute-path imports are disabled by default."
        )

      true ->
        candidate = importing_path |> Path.dirname() |> Path.join(location) |> Path.expand()
        relative = Path.relative_to(candidate, import_root)

        if relative == ".." or String.starts_with?(relative, "../") do
          import_error(
            :import_path_escape,
            import,
            model,
            "The import resolves outside the root model directory."
          )
        else
          {:ok, candidate}
        end
    end
  end

  defp reject_import_cycle(path, active_paths, model) do
    if MapSet.member?(active_paths, path) do
      {:error,
       [
         %Diagnostic{
           code: :import_cycle,
           category: :import,
           path: [:imports],
           message: "The declared import graph contains a cycle.",
           specification: "DMN 1.5",
           source_profile: model.source_profile,
           details: %{path: path}
         }
       ]}
    else
      :ok
    end
  end

  defp validate_import_namespace(import, imported, model) do
    if imported.definitions.namespace == import.namespace do
      :ok
    else
      import_error(
        :import_namespace_mismatch,
        import,
        model,
        "The imported definitions namespace does not match the declaration.",
        %{actual: imported.definitions.namespace, expected: import.namespace}
      )
    end
  end

  defp import_error(code, import, model, message, details \\ %{}) do
    {:error,
     [
       %Diagnostic{
         code: code,
         category: :import,
         path: [:imports, import.namespace],
         message: message,
         specification: "DMN 1.5",
         source_profile: model.source_profile,
         details: Map.put(details, :location_uri, import.location_uri)
       }
     ]}
  end

  @doc "Inspects a well-formed DMN document without granting executable status."
  @spec inspect_xml(String.t()) :: {:ok, Model.t()} | {:error, load_error() | [Diagnostic.t()]}
  def inspect_xml(xml) when is_binary(xml) do
    with :ok <- SchemaValidator.validate_safety(xml),
         :ok <- SchemaValidator.validate_inspection_names(xml),
         {:ok, document} <- parse_xml(xml),
         :ok <- SchemaValidator.validate_document(document),
         :ok <- definitions_document?(document) do
      {:ok, build_model(document)}
    end
  end

  defp validate_profile(%Model{source_profile: :dmn_1_5}), do: :ok

  defp validate_profile(%Model{source_profile: source_profile}) do
    {:error,
     [
       %Diagnostic{
         code: :dmn_version_mismatch,
         category: :executable_profile,
         path: [:source_profile],
         message: "The document is not in the executable DMN 1.5 profile.",
         specification: "DMN 1.5",
         source_profile: source_profile,
         details: %{required: :dmn_1_5}
       }
     ]}
  end

  defp validate_model(model) do
    case Validator.validate(model) do
      :ok ->
        :ok

      {:error, errors} ->
        errors =
          Enum.reject(errors, fn
            {:missing_id, _, _} -> true
            {:missing_expression, _} -> true
            _error -> false
          end)

        if errors == [] do
          :ok
        else
          {:error,
           errors
           |> Enum.with_index()
           |> Enum.map(fn {error, index} ->
             %Diagnostic{
               code: validation_code(error),
               category: :dmn_model,
               path: [:validation, index],
               message: "The normalized DMN model is not valid.",
               specification: "DMN 1.5",
               source_profile: model.source_profile,
               details: %{validation_error: error}
             }
           end)}
        end
    end
  end

  defp validation_code(error) when is_atom(error), do: error
  defp validation_code(error) when is_tuple(error), do: elem(error, 0)

  defp read_file(path) do
    case File.read(path) do
      {:ok, contents} -> {:ok, contents}
      {:error, reason} -> {:error, {:file_error, path, reason}}
    end
  end

  defp xml_input?(input), do: input |> String.trim_leading() |> String.starts_with?("<")

  defp parse_xml(xml) do
    try do
      {document, rest} =
        :xmerl_scan.string(:binary.bin_to_list(xml),
          namespace_conformant: true,
          allow_entities: false
        )

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
    source_profile =
      document
      |> namespace_uri()
      |> Compatibility.source_profile()

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

    import_nodes = nodes(document, "./*[local-name()='import']")

    duplicate_import_issues =
      import_nodes
      |> Enum.map(&attr(&1, "namespace"))
      |> Enum.frequencies()
      |> Enum.flat_map(fn
        {_namespace, 1} -> []
        {namespace, _count} -> [{:duplicate_import_namespace, namespace}]
      end)

    %Model{
      definitions: definitions,
      source_profile: source_profile,
      imports:
        import_nodes
        |> Map.new(fn import ->
          namespace = attr(import, "namespace")

          {namespace,
           %Import{
             name: attr(import, "name"),
             namespace: namespace,
             location_uri: attr(import, "locationURI"),
             import_type: attr(import, "importType")
           }}
        end),
      input_data: input_data,
      decisions: decisions,
      bkms: bkms,
      item_definitions: item_definitions,
      decision_services: decision_services,
      serialization_fidelity: serialization_fidelity(document),
      issues:
        input_issues ++
          decision_issues ++ bkm_issues ++ service_issues ++ duplicate_import_issues
    }
  end

  defp serialization_fidelity(document) do
    known_losses =
      [
        {"description", "description"},
        {"documentation", "documentation"},
        {"extensionElements", "extension elements"},
        {"authorityRequirement", "authority requirements"},
        {"annotationClause", "decision-table annotation clauses"},
        {"annotationEntry", "decision-table annotation entries"},
        {"DMNDI", "DMNDI layout"},
        {"DMNDiagram", "DMNDI layout"},
        {"encapsulatedDecision", "encapsulated decision references"}
      ]
      |> Enum.flat_map(fn {local_name, label} ->
        count = length(nodes(document, ".//*[local-name()='#{local_name}']"))
        if count == 0, do: [], else: [{:discarded_xml_content, label, count}]
      end)

    unknown_losses =
      document
      |> nodes(".//*")
      |> Enum.map(&local_name/1)
      |> Enum.reject(&(&1 in @normalized_element_names))
      |> Enum.frequencies()
      |> Enum.sort()
      |> Enum.map(fn {name, count} -> {:unsupported_xml_element, name, count} end)

    attribute_losses =
      document
      |> nodes("descendant-or-self::*")
      |> Enum.flat_map(&discarded_attributes/1)
      |> Enum.frequencies()
      |> Enum.sort()
      |> Enum.map(fn {{element, attribute}, count} ->
        {:discarded_xml_attribute, element, attribute, count}
      end)

    losses = Enum.uniq(known_losses ++ unknown_losses ++ attribute_losses)

    case losses do
      [] -> :complete
      losses -> {:lossy, losses}
    end
  end

  defp discarded_attributes(element) do
    element_name = local_name(element)
    retained = Map.get(@retained_attributes, element_name, [])

    element
    |> nodes("./@*")
    |> Enum.flat_map(fn attribute ->
      case attribute_identity(attribute) do
        {nil, name} ->
          if name in retained, do: [], else: [{element_name, name}]

        {namespace, name} ->
          [{element_name, "{#{namespace}}#{name}"}]
      end
    end)
  end

  defp attribute_identity(attribute) do
    case elem(attribute, 2) do
      {namespace, local_name} -> {to_string(namespace), to_string(local_name)}
      local_name -> {nil, to_string(local_name)}
    end
  end

  defp parse_item_definition(node) do
    function_item = node |> nodes("./*[local-name()='functionItem']") |> List.first()

    %ItemDefinition{
      id: attr(node, "id"),
      name: attr(node, "name"),
      type_ref:
        child_text_value(node, "typeRef") ||
          (function_item && "function:" <> (attr(function_item, "outputTypeRef") || "Any")),
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
      requirements: parse_requirements(node),
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
          expression_language: attr(expression, "expressionLanguage")
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

      "list" ->
        %ListExpression{
          id: attr(expression, "id"),
          items:
            Enum.map(
              nodes(expression, "./*[local-name()='literalExpression']"),
              &parse_expression_node/1
            )
        }

      "conditional" ->
        %ConditionalExpression{
          id: attr(expression, "id"),
          condition: parse_boxed_child(expression, "if"),
          then_branch: parse_boxed_child(expression, "then"),
          else_branch: parse_boxed_child(expression, "else")
        }

      "filter" ->
        %FilterExpression{
          id: attr(expression, "id"),
          source: parse_boxed_child(expression, "in"),
          match: parse_boxed_child(expression, "match")
        }

      kind when kind in ["for", "some", "every"] ->
        body_name = if kind == "for", do: "return", else: "satisfies"

        %IteratorExpression{
          id: attr(expression, "id"),
          kind: String.to_atom(kind),
          variable: attr(expression, "iteratorVariable"),
          source: parse_boxed_child(expression, "in"),
          body: parse_boxed_child(expression, body_name)
        }

      kind ->
        {:unsupported, kind}
    end
  end

  defp parse_boxed_child(expression, name) do
    expression
    |> nodes("./*[local-name()='#{name}']/*[1]")
    |> List.first()
    |> then(&(&1 && parse_expression_node(&1)))
  end

  defp parse_invocation(node) do
    function = node |> nodes("./*[local-name()='literalExpression']") |> List.first()

    %Invocation{
      id: attr(node, "id"),
      type_ref: attr(node, "typeRef"),
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
        is_nil(item.id) and is_binary(Map.get(item, :name)) ->
          item = Map.put(item, :id, item.name)

          {Map.put(items, item.name, item),
           [{:missing_id, struct_name(item), item.name} | issues]}

        is_nil(item.id) ->
          {items, [{:missing_id, struct_name(item), item.name} | issues]}

        Map.has_key?(items, item.id) ->
          {items, [{:duplicate_id, item.id} | issues]}

        true ->
          {Map.put(items, item.id, item), issues}
      end
    end)
  end

  defp reference(node) do
    case attr(node, "href") do
      "#" <> id -> id
      href -> href
    end
  end

  defp text_child(node), do: xpath_raw_string(node, "./*[local-name()='text']")

  defp child_text(node, child),
    do: xpath_raw_string(node, "./*[local-name()='#{child}']/*[local-name()='text']")

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

  defp xpath_raw_string(node, path) do
    query = ~c"string(" ++ String.to_charlist(path) ++ ~c")"

    case :xmerl_xpath.string(query, node) do
      {:xmlObj, :string, value} -> value |> to_string() |> empty_to_nil()
      value -> value |> to_string() |> empty_to_nil()
    end
  end

  defp local_name(node) do
    node |> xpath_string("local-name(.)")
  end

  defp namespace_uri(node) when is_tuple(node) do
    case elem(node, 2) do
      {namespace, _local_name} -> to_string(namespace)
      _unqualified_name -> nil
    end
  end

  defp struct_name(%module{}),
    do: module |> Module.split() |> List.last() |> Macro.underscore() |> String.to_atom()

  defp empty_to_nil(""), do: nil
  defp empty_to_nil(value), do: value
end
