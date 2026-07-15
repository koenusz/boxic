defmodule Arbiter.DMN do
  @moduledoc """
  Loads DMN XML into normalized model values and validates the model boundary.

  WP-08 deliberately separates XML normalization from execution. Namespace
  prefixes and `:xmerl` records are removed during loading; later work packages
  can therefore resolve and execute decisions against stable domain structs.
  """

  alias Arbiter.DMN.Model
  alias Arbiter.DMN.Model.Decision
  alias Arbiter.DMN.Model.Definitions
  alias Arbiter.DMN.Model.InformationRequirement
  alias Arbiter.DMN.Model.InputData
  alias Arbiter.DMN.Model.LiteralExpression
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

    %Model{
      definitions: definitions,
      input_data: input_data,
      decisions: decisions,
      issues: input_issues ++ decision_issues
    }
  end

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
  end

  defp parse_expression(node) do
    children =
      nodes(
        node,
        "./*[not(local-name()='description') and not(local-name()='question') and not(local-name()='allowedAnswers') and not(local-name()='variable') and not(local-name()='informationRequirement') and not(local-name()='knowledgeRequirement') and not(local-name()='authorityRequirement') and not(local-name()='extensionElements')]"
      )

    case children do
      [expression | _] ->
        case local_name(expression) do
          "literalExpression" ->
            %LiteralExpression{
              id: attr(expression, "id"),
              text: text_child(expression),
              type_ref: attr(expression, "typeRef"),
              expression_language: attr(expression, "expressionLanguage") || "feel"
            }

          kind ->
            {:unsupported, kind}
        end

      [] ->
        nil
    end
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
    required(definitions, [:id, :name, :namespace], :definitions)
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

  defp validate_variable(nil, _owner), do: []
  defp validate_variable(variable, owner), do: required(variable, [:name], {:variable, owner})

  defp validate_expression(nil, id), do: [{:missing_expression, id}]

  defp validate_expression(%LiteralExpression{text: nil}, id),
    do: [{:missing_expression_text, id}]

  defp validate_expression(%LiteralExpression{expression_language: language}, id)
       when language not in [nil, "feel", "https://www.omg.org/spec/DMN/20191111/FEEL/"] do
    [{:unsupported_expression_language, id, language}]
  end

  defp validate_expression(%LiteralExpression{}, _id), do: []
  defp validate_expression({:unsupported, kind}, id), do: [{:unsupported_expression, id, kind}]

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
             %LiteralExpression{text: text} when is_binary(text) <- decision.expression,
             {text, dependency_context} <- normalize_feel_names(text, dependency_context),
             {:ok, value} <- Arbiter.FEEL.evaluate(text, dependency_context) do
          {:ok, value, Map.put(memo, decision.id, value)}
        else
          nil -> {:error, {:missing_expression, decision.id}}
          {:unsupported, kind} -> {:error, {:unsupported_expression, kind}}
          error -> error
        end
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
    with {:ok, dependency} <- fetch_reference(model.decisions, :decision, id),
         {:ok, value, memo} <- evaluate_decision(model, dependency, context, memo, visiting) do
      {:ok, bind_value(context, dependency, value), memo}
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

  defp bind_value(context, node, value) do
    [node.name, node.variable && node.variable.name, node.id]
    |> Enum.reject(&is_nil/1)
    |> Enum.reduce(context, &Map.put(&2, &1, value))
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
    (Map.values(model.input_data) ++ Map.values(model.decisions))
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
