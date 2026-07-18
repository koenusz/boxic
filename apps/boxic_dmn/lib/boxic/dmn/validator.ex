defmodule Boxic.DMN.Validator do
  @moduledoc false
  alias Boxic.DMN.Model
  alias Boxic.DMN.Model.ContextExpression
  alias Boxic.DMN.Model.ConditionalExpression
  alias Boxic.DMN.Model.DecisionTable
  alias Boxic.DMN.Model.Definitions
  alias Boxic.DMN.Model.FunctionDefinition
  alias Boxic.DMN.Model.FilterExpression
  alias Boxic.DMN.Model.Invocation
  alias Boxic.DMN.Model.IteratorExpression
  alias Boxic.DMN.Model.LiteralExpression
  alias Boxic.DMN.Model.ListExpression
  alias Boxic.DMN.Model.Relation

  @type validation_error ::
          {atom(), term()} | {atom(), term(), term()} | {atom(), term(), term(), term()}

  @spec validate(Model.t()) :: :ok | {:error, [validation_error()]}
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

  defp validate_expression(%ListExpression{items: items}, id) do
    Enum.flat_map(items, &validate_expression(&1, id))
  end

  defp validate_expression(%ConditionalExpression{} = expression, id) do
    validate_expression(expression.condition, id) ++
      validate_expression(expression.then_branch, id) ++
      validate_expression(expression.else_branch, id)
  end

  defp validate_expression(%FilterExpression{} = expression, id) do
    validate_expression(expression.source, id) ++ validate_expression(expression.match, id)
  end

  defp validate_expression(%IteratorExpression{} = expression, id) do
    required(expression, [:variable], {:iterator, id}) ++
      validate_expression(expression.source, id) ++ validate_expression(expression.body, id)
  end

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

  def validate_for_evaluation(model, decision) do
    errors =
      Enum.reject(model.issues, &match?({:missing_id, _, _}, &1)) ++
        validate_definitions(model.definitions) ++
        required(decision, [:name], {:decision, decision.id}) ++
        validate_expression(decision.expression, decision.id)

    case Enum.uniq(errors) do
      [] -> :ok
      errors -> {:error, errors}
    end
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

        if is_binary(requirement.href) and reference_exists?(target, requirement.href),
          do: [],
          else: [{:unresolved_reference, decision_id, requirement.kind, requirement.href}]
      end)
    end)
  end

  defp reference_exists?(target, href) do
    Map.has_key?(target, href) or Map.has_key?(target, href |> String.split("#") |> List.last())
  end

  defp required(value, fields, owner) do
    Enum.flat_map(fields, fn field ->
      if Map.get(value, field) in [nil, ""], do: [{:missing_attribute, owner, field}], else: []
    end)
  end
end
