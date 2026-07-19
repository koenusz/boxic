defmodule Boxic.DMN.Authoring.DecisionTable do
  @moduledoc """
  Immutable, ID-based editing operations for normalized decision tables.

  Operations that add, remove, or move clauses update every rule at the same
  position so table arity remains structurally valid.
  """

  alias Boxic.DMN.AuthoringError
  alias Boxic.DMN.Model
  alias Boxic.DMN.Model.{DecisionRule, DecisionTable, InputClause, OutputClause}

  @type result :: {:ok, Model.t()} | {:error, AuthoringError.t()}

  @doc "Replaces one input entry, locating the decision, rule, and input by stable ID."
  @spec put_input_entry(Model.t(), keyword()) :: result()
  def put_input_entry(%Model{} = model, opts) do
    with {:ok, decision_id} <- required_option(opts, :decision_id),
         {:ok, rule_id} <- required_option(opts, :rule_id),
         {:ok, input_id} <- required_option(opts, :input_id),
         {:ok, text} <- required_binary_option(opts, :text) do
      update_table(model, decision_id, fn table ->
        with {:ok, input_index} <- find_index(table.inputs, input_id, :input),
             {:ok, rule_index} <- find_index(table.rules, rule_id, :rule) do
          rule = Enum.at(table.rules, rule_index)

          updated = %{
            rule
            | input_entries: List.replace_at(rule.input_entries, input_index, text)
          }

          {:ok, %{table | rules: List.replace_at(table.rules, rule_index, updated)}}
        end
      end)
    end
  end

  @doc "Replaces one output entry, locating the decision, rule, and output by stable ID."
  @spec put_output_entry(Model.t(), keyword()) :: result()
  def put_output_entry(%Model{} = model, opts) do
    with {:ok, decision_id} <- required_option(opts, :decision_id),
         {:ok, rule_id} <- required_option(opts, :rule_id),
         {:ok, output_id} <- required_option(opts, :output_id),
         {:ok, text} <- required_binary_option(opts, :text) do
      update_table(model, decision_id, fn table ->
        with {:ok, output_index} <- find_index(table.outputs, output_id, :output),
             {:ok, rule_index} <- find_index(table.rules, rule_id, :rule) do
          rule = Enum.at(table.rules, rule_index)

          updated = %{
            rule
            | output_entries: List.replace_at(rule.output_entries, output_index, text)
          }

          {:ok, %{table | rules: List.replace_at(table.rules, rule_index, updated)}}
        end
      end)
    end
  end

  @doc "Adds a structurally complete rule at `:position` or at the end."
  @spec add_rule(Model.t(), String.t(), DecisionRule.t(), keyword()) :: result()
  def add_rule(%Model{} = model, decision_id, %DecisionRule{} = rule, opts \\ []) do
    update_table(model, decision_id, fn table ->
      with :ok <- unique_id(table.rules, rule.id, :rule),
           :ok <- rule_arity(table, rule),
           {:ok, position} <- insertion_position(opts, length(table.rules)) do
        {:ok, %{table | rules: List.insert_at(table.rules, position, rule)}}
      end
    end)
  end

  @doc "Replaces an existing rule with the same stable ID after checking its arity."
  @spec update_rule(Model.t(), String.t(), DecisionRule.t()) :: result()
  def update_rule(%Model{} = model, decision_id, %DecisionRule{} = rule) do
    update_table(model, decision_id, fn table ->
      with {:ok, index} <- find_index(table.rules, rule.id, :rule),
           :ok <- rule_arity(table, rule) do
        {:ok, %{table | rules: List.replace_at(table.rules, index, rule)}}
      end
    end)
  end

  @doc "Removes a rule by stable ID."
  @spec remove_rule(Model.t(), String.t(), String.t()) :: result()
  def remove_rule(%Model{} = model, decision_id, rule_id) do
    update_table(model, decision_id, fn table ->
      with {:ok, index} <- find_index(table.rules, rule_id, :rule) do
        {:ok, %{table | rules: List.delete_at(table.rules, index)}}
      end
    end)
  end

  @doc "Moves a rule to a zero-based position."
  @spec move_rule(Model.t(), String.t(), String.t(), non_neg_integer()) :: result()
  def move_rule(%Model{} = model, decision_id, rule_id, position) do
    update_table(model, decision_id, fn table ->
      move_by_id(table.rules, rule_id, position, :rule, fn rules -> %{table | rules: rules} end)
    end)
  end

  @doc """
  Adds an input clause and inserts `:entry_text` into every existing rule.

  The clause is appended unless a zero-based `:position` is supplied.
  """
  @spec add_input(Model.t(), String.t(), InputClause.t(), keyword()) :: result()
  def add_input(%Model{} = model, decision_id, %InputClause{} = input, opts \\ []) do
    with {:ok, entry_text} <- required_binary_option(opts, :entry_text) do
      update_table(model, decision_id, fn table ->
        with :ok <- unique_id(table.inputs, input.id, :input),
             {:ok, position} <- insertion_position(opts, length(table.inputs)) do
          rules =
            Enum.map(table.rules, fn rule ->
              %{rule | input_entries: List.insert_at(rule.input_entries, position, entry_text)}
            end)

          {:ok,
           %{
             table
             | inputs: List.insert_at(table.inputs, position, input),
               rules: rules
           }}
        end
      end)
    end
  end

  @doc "Replaces an input clause with the same stable ID."
  @spec update_input(Model.t(), String.t(), InputClause.t()) :: result()
  def update_input(%Model{} = model, decision_id, %InputClause{} = input) do
    update_table(model, decision_id, fn table ->
      with {:ok, index} <- find_index(table.inputs, input.id, :input) do
        {:ok, %{table | inputs: List.replace_at(table.inputs, index, input)}}
      end
    end)
  end

  @doc "Removes an input clause and its corresponding entry from every rule."
  @spec remove_input(Model.t(), String.t(), String.t()) :: result()
  def remove_input(%Model{} = model, decision_id, input_id) do
    update_table(model, decision_id, fn table ->
      with {:ok, index} <- find_index(table.inputs, input_id, :input) do
        rules =
          Enum.map(table.rules, fn rule ->
            %{rule | input_entries: List.delete_at(rule.input_entries, index)}
          end)

        {:ok, %{table | inputs: List.delete_at(table.inputs, index), rules: rules}}
      end
    end)
  end

  @doc "Moves an input clause and the corresponding entry in every rule."
  @spec move_input(Model.t(), String.t(), String.t(), non_neg_integer()) :: result()
  def move_input(%Model{} = model, decision_id, input_id, position) do
    update_table(model, decision_id, fn table ->
      with {:ok, from} <- find_index(table.inputs, input_id, :input),
           :ok <- valid_move_position(position, length(table.inputs), :input) do
        inputs = move_at(table.inputs, from, position)

        rules =
          Enum.map(table.rules, &%{&1 | input_entries: move_at(&1.input_entries, from, position)})

        {:ok, %{table | inputs: inputs, rules: rules}}
      end
    end)
  end

  @doc """
  Adds an output clause and inserts `:entry_text` into every existing rule.

  The clause is appended unless a zero-based `:position` is supplied.
  """
  @spec add_output(Model.t(), String.t(), OutputClause.t(), keyword()) :: result()
  def add_output(%Model{} = model, decision_id, %OutputClause{} = output, opts \\ []) do
    with {:ok, entry_text} <- required_binary_option(opts, :entry_text) do
      update_table(model, decision_id, fn table ->
        with :ok <- unique_id(table.outputs, output.id, :output),
             {:ok, position} <- insertion_position(opts, length(table.outputs)) do
          rules =
            Enum.map(table.rules, fn rule ->
              %{rule | output_entries: List.insert_at(rule.output_entries, position, entry_text)}
            end)

          {:ok,
           %{
             table
             | outputs: List.insert_at(table.outputs, position, output),
               rules: rules
           }}
        end
      end)
    end
  end

  @doc "Replaces an output clause with the same stable ID."
  @spec update_output(Model.t(), String.t(), OutputClause.t()) :: result()
  def update_output(%Model{} = model, decision_id, %OutputClause{} = output) do
    update_table(model, decision_id, fn table ->
      with {:ok, index} <- find_index(table.outputs, output.id, :output) do
        {:ok, %{table | outputs: List.replace_at(table.outputs, index, output)}}
      end
    end)
  end

  @doc "Removes an output clause and its corresponding entry from every rule."
  @spec remove_output(Model.t(), String.t(), String.t()) :: result()
  def remove_output(%Model{} = model, decision_id, output_id) do
    update_table(model, decision_id, fn table ->
      with {:ok, index} <- find_index(table.outputs, output_id, :output) do
        rules =
          Enum.map(table.rules, fn rule ->
            %{rule | output_entries: List.delete_at(rule.output_entries, index)}
          end)

        {:ok, %{table | outputs: List.delete_at(table.outputs, index), rules: rules}}
      end
    end)
  end

  @doc "Moves an output clause and the corresponding entry in every rule."
  @spec move_output(Model.t(), String.t(), String.t(), non_neg_integer()) :: result()
  def move_output(%Model{} = model, decision_id, output_id, position) do
    update_table(model, decision_id, fn table ->
      with {:ok, from} <- find_index(table.outputs, output_id, :output),
           :ok <- valid_move_position(position, length(table.outputs), :output) do
        outputs = move_at(table.outputs, from, position)

        rules =
          Enum.map(
            table.rules,
            &%{&1 | output_entries: move_at(&1.output_entries, from, position)}
          )

        {:ok, %{table | outputs: outputs, rules: rules}}
      end
    end)
  end

  @doc "Changes the hit policy and validates any COLLECT aggregation."
  @spec set_hit_policy(Model.t(), String.t(), String.t(), String.t() | nil) :: result()
  def set_hit_policy(%Model{} = model, decision_id, hit_policy, aggregation \\ nil) do
    update_table(model, decision_id, fn table ->
      with :ok <- valid_hit_policy(hit_policy, aggregation, length(table.outputs)) do
        {:ok, %{table | hit_policy: hit_policy, aggregation: aggregation}}
      end
    end)
  end

  defp update_table(model, decision_id, update) do
    case Map.fetch(model.decisions, decision_id) do
      :error ->
        {:error, error(:decision_not_found, [:decisions, decision_id], "Decision was not found.")}

      {:ok, %{expression: %DecisionTable{} = table} = decision} ->
        case update.(table) do
          {:ok, updated_table} ->
            updated_decision = %{decision | expression: updated_table}
            {:ok, %{model | decisions: Map.put(model.decisions, decision_id, updated_decision)}}

          {:error, %AuthoringError{}} = error ->
            error
        end

      {:ok, _decision} ->
        {:error,
         error(
           :not_a_decision_table,
           [:decisions, decision_id, :expression],
           "Decision does not contain a decision table."
         )}
    end
  end

  defp find_index(values, id, kind) do
    case Enum.find_index(values, &(&1.id == id)) do
      nil ->
        {:error, error(:"#{kind}_not_found", [:"#{kind}s", id], "#{label(kind)} was not found.")}

      index ->
        {:ok, index}
    end
  end

  defp unique_id(_values, nil, kind),
    do: {:error, error(:missing_identifier, [:"#{kind}s"], "#{label(kind)} ID is required.")}

  defp unique_id(values, id, kind) do
    if Enum.any?(values, &(&1.id == id)) do
      {:error,
       error(:duplicate_identifier, [:"#{kind}s", id], "#{label(kind)} ID already exists.")}
    else
      :ok
    end
  end

  defp rule_arity(table, rule) do
    cond do
      length(rule.input_entries) != length(table.inputs) ->
        {:error,
         error(
           :rule_entry_count_mismatch,
           [:rules, rule.id, :input_entries],
           "Rule input entry count does not match the table input count."
         )}

      length(rule.output_entries) != length(table.outputs) ->
        {:error,
         error(
           :rule_entry_count_mismatch,
           [:rules, rule.id, :output_entries],
           "Rule output entry count does not match the table output count."
         )}

      true ->
        :ok
    end
  end

  defp insertion_position(opts, length) do
    position = Keyword.get(opts, :position, length)

    if is_integer(position) and position >= 0 and position <= length do
      {:ok, position}
    else
      {:error, error(:invalid_position, [:position], "Insertion position is out of bounds.")}
    end
  end

  defp valid_move_position(position, length, kind) do
    if is_integer(position) and position >= 0 and position < length do
      :ok
    else
      {:error,
       error(:invalid_position, [:"#{kind}s", :position], "Move position is out of bounds.")}
    end
  end

  defp move_by_id(values, id, position, kind, build) do
    with {:ok, from} <- find_index(values, id, kind),
         :ok <- valid_move_position(position, length(values), kind) do
      {:ok, build.(move_at(values, from, position))}
    end
  end

  defp move_at(values, from, to) do
    value = Enum.at(values, from)
    values |> List.delete_at(from) |> List.insert_at(to, value)
  end

  defp valid_hit_policy(hit_policy, aggregation, output_count) do
    policies = ~w(UNIQUE FIRST ANY PRIORITY RULE_ORDER OUTPUT_ORDER COLLECT)
    aggregations = ~w(SUM MIN MAX COUNT)

    cond do
      hit_policy not in policies ->
        {:error, error(:invalid_hit_policy, [:hit_policy], "Hit policy is not supported.")}

      hit_policy != "COLLECT" and not is_nil(aggregation) ->
        {:error,
         error(
           :invalid_aggregation,
           [:aggregation],
           "Aggregation is permitted only for the COLLECT hit policy."
         )}

      hit_policy == "COLLECT" and aggregation not in [nil | aggregations] ->
        {:error,
         error(:invalid_aggregation, [:aggregation], "COLLECT aggregation is not supported.")}

      hit_policy == "COLLECT" and not is_nil(aggregation) and output_count != 1 ->
        {:error,
         error(
           :invalid_aggregation,
           [:aggregation],
           "A COLLECT aggregation requires exactly one output clause."
         )}

      true ->
        :ok
    end
  end

  defp required_option(opts, key) do
    case Keyword.fetch(opts, key) do
      {:ok, value} -> {:ok, value}
      :error -> {:error, error(:missing_option, [key], "Required authoring option is missing.")}
    end
  end

  defp required_binary_option(opts, key) do
    with {:ok, value} <- required_option(opts, key) do
      if is_binary(value) do
        {:ok, value}
      else
        {:error, error(:invalid_option, [key], "Authoring option must be a string.")}
      end
    end
  end

  defp label(kind),
    do: kind |> Atom.to_string() |> String.replace("_", " ") |> String.capitalize()

  defp error(code, path, message),
    do: %AuthoringError{code: code, path: path, message: message, details: nil}
end
