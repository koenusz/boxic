defmodule Boxic.DMN.Evaluator do
  @moduledoc false
  alias Boxic.DMN.Model
  alias Boxic.DMN.Model.BusinessKnowledgeModel
  alias Boxic.DMN.Model.ContextExpression
  alias Boxic.DMN.Model.ConditionalExpression
  alias Boxic.DMN.Model.DecisionService
  alias Boxic.DMN.Model.DecisionTable
  alias Boxic.DMN.Model.FunctionDefinition
  alias Boxic.DMN.Model.FilterExpression
  alias Boxic.DMN.Model.InformationRequirement
  alias Boxic.DMN.Model.Invocation
  alias Boxic.DMN.Model.IteratorExpression
  alias Boxic.DMN.Model.LiteralExpression
  alias Boxic.DMN.Model.ListExpression
  alias Boxic.DMN.Model.Relation
  alias Boxic.DMN.Model.Variable
  alias Boxic.DMN.{FEEL, Validator}
  alias Boxic.DMN.DecisionTable, as: DecisionTableEvaluator
  alias Boxic.FEEL.ExternalFunctions

  @type evaluation_error ::
          Boxic.FEEL.Error.t()
          | {atom(), term()}
          | {atom(), term(), term()}
          | {atom(), term(), term(), term()}

  @spec evaluate(Model.t(), String.t(), map()) :: {:ok, term()} | {:error, evaluation_error()}
  def evaluate(%Model{} = model, decision_name, context \\ %{})
      when is_binary(decision_name) and is_map(context) do
    with {:ok, context} <- coerce_input_context(model, context),
         {:ok, decision} <- find_decision(model, decision_name),
         {:ok, value, _memo} <- evaluate_decision(model, decision, context, %{}, %{}) do
      {:ok, value}
    end
  end

  @spec evaluate(Model.t(), String.t(), map(), keyword()) ::
          {:ok, term()} | {:error, evaluation_error()}
  def evaluate(%Model{} = model, decision_name, context, opts)
      when is_binary(decision_name) and is_map(context) and is_list(opts) do
    external_context =
      case Keyword.get(opts, :external_functions) do
        nil -> %{}
        registry -> ExternalFunctions.to_context(registry)
      end

    evaluate(model, decision_name, Map.merge(context, external_context))
  end

  @spec evaluate_service(Model.t(), String.t(), map() | list()) ::
          {:ok, term()} | {:error, evaluation_error()}
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

  defp evaluate_decision(model, decision, context, memo, visiting) do
    cond do
      Map.has_key?(memo, decision.id) ->
        {:ok, Map.fetch!(memo, decision.id), memo}

      Map.has_key?(visiting, decision.id) ->
        {:error, {:cyclic_decision_dependency, decision.id}}

      true ->
        visiting = Map.put(visiting, decision.id, true)

        with :ok <- Validator.validate_for_evaluation(model, decision),
             {:ok, dependency_context, memo} <-
               resolve_requirements(model, decision, context, memo, visiting),
             {:ok, value} <- evaluate_expression(decision.expression, dependency_context, model),
             {:ok, value} <-
               coerce_type(value, decision.variable && decision.variable.type_ref, model) do
          {:ok, value, Map.put(memo, decision.id, value)}
        else
          nil -> {:error, {:missing_expression, decision.id}}
          {:unsupported, kind} -> {:error, {:unsupported_expression, kind}}
          error -> error
        end
    end
  end

  defp evaluate_expression(%LiteralExpression{text: text, type_ref: type_ref}, context, model)
       when is_binary(text) do
    {text, context} = FEEL.normalize_names(text, context)
    context = Map.put(context, "__feel_types__", model.item_definitions)

    with {:ok, value} <- Boxic.FEEL.evaluate(text, context) do
      coerce_type(value, type_ref, model)
    end
  end

  defp evaluate_expression(%DecisionTable{} = table, context, _model),
    do: DecisionTableEvaluator.evaluate(table, context)

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

  defp evaluate_expression(%ListExpression{items: items}, context, model) do
    Enum.reduce_while(items, {:ok, []}, fn item, {:ok, values} ->
      case evaluate_expression(item, context, model) do
        {:ok, value} -> {:cont, {:ok, values ++ [value]}}
        {:error, _reason} = error -> {:halt, error}
      end
    end)
  end

  defp evaluate_expression(%ConditionalExpression{} = expression, context, model) do
    with {:ok, condition} <- evaluate_expression(expression.condition, context, model) do
      case condition do
        true -> evaluate_expression(expression.then_branch, context, model)
        false -> evaluate_expression(expression.else_branch, context, model)
        nil -> evaluate_expression(expression.else_branch, context, model)
        _ -> {:error, {:type_error, :boolean}}
      end
    end
  end

  defp evaluate_expression(%FilterExpression{} = expression, context, model) do
    with {:ok, source} <- evaluate_expression(expression.source, context, model),
         true <- is_list(source) do
      Enum.reduce_while(source, {:ok, []}, fn item, {:ok, result} ->
        case evaluate_expression(expression.match, bind_boxed_item(context, item), model) do
          {:ok, true} -> {:cont, {:ok, result ++ [item]}}
          {:ok, false} -> {:cont, {:ok, result}}
          {:ok, _value} -> {:halt, {:error, {:type_error, :boolean}}}
          {:error, _reason} = error -> {:halt, error}
        end
      end)
    else
      false -> {:error, {:type_error, :list}}
      {:error, _reason} = error -> error
    end
  end

  defp evaluate_expression(%IteratorExpression{kind: :for} = expression, context, model) do
    with {:ok, source} <- evaluate_expression(expression.source, context, model),
         true <- is_list(source) do
      Enum.reduce_while(source, {:ok, []}, fn item, {:ok, result} ->
        case evaluate_expression(
               expression.body,
               Map.put(context, expression.variable, item),
               model
             ) do
          {:ok, value} -> {:cont, {:ok, result ++ [value]}}
          {:error, _reason} = error -> {:halt, error}
        end
      end)
    else
      false -> {:error, {:type_error, :list}}
      {:error, _reason} = error -> error
    end
  end

  defp evaluate_expression(%IteratorExpression{} = expression, context, model) do
    with {:ok, source} <- evaluate_expression(expression.source, context, model),
         true <- is_list(source) do
      evaluate_boxed_quantifier(expression.kind, source, expression, context, model)
    else
      false -> {:error, {:type_error, :list}}
      {:error, _reason} = error -> error
    end
  end

  defp evaluate_expression(nil, _context, _model), do: {:error, :missing_expression}

  defp evaluate_expression({:unsupported, kind}, _context, _model),
    do: {:error, {:unsupported_expression, kind}}

  defp evaluate_boxed_quantifier(kind, source, expression, context, model) do
    initial = if kind == :every, do: true, else: false

    Enum.reduce_while(source, {:ok, initial}, fn item, {:ok, _result} ->
      case evaluate_expression(
             expression.body,
             Map.put(context, expression.variable, item),
             model
           ) do
        {:ok, value} when is_boolean(value) ->
          if (kind == :some and value) or (kind == :every and not value),
            do: {:halt, {:ok, value}},
            else: {:cont, {:ok, value}}

        {:ok, _value} ->
          {:halt, {:error, {:type_error, :boolean}}}

        {:error, _reason} = error ->
          {:halt, error}
      end
    end)
  end

  defp bind_boxed_item(context, item) when is_map(item) and not is_struct(item),
    do: Map.merge(context, Map.put(item, "item", item))

  defp bind_boxed_item(context, item), do: Map.put(context, "item", item)

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
          {:ok, bind_reference_value(context, dependency, value, id, model), memo}

        :error ->
          with {:ok, value, memo} <- evaluate_decision(model, dependency, context, memo, visiting) do
            {:ok, bind_reference_value(context, dependency, value, id, model), memo}
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
    case fetch_reference(Map.merge(model.bkms, model.decision_services), :knowledge, id) do
      {:ok, %BusinessKnowledgeModel{} = bkm} ->
        callable =
          {:external_function, fn args -> invoke_bkm_from_feel(model, bkm, context, args) end}

        {:ok, bind_reference_value(context, bkm, callable, id, model), memo}

      {:ok, %DecisionService{} = service} ->
        callable =
          {:external_function,
           fn args -> invoke_decision_service(model, service, context, args) end}

        {:ok, bind_reference_value(context, service, callable, id, model), memo}

      {:error, _reason} = error ->
        error
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
         {:ok, value} <- input_value(context, input),
         {:ok, value} <- coerce_type(value, input.variable && input.variable.type_ref, model) do
      {:ok, bind_reference_value(context, input, value, id, model), memo}
    end
  end

  defp resolve_requirement(_model, requirement, _context, _memo, _visiting),
    do: {:error, {:invalid_information_requirement, requirement}}

  defp fetch_reference(index, kind, id) do
    case Map.fetch(index, id) do
      {:ok, value} ->
        {:ok, value}

      :error ->
        fragment = id |> String.split("#") |> List.last()

        case Map.fetch(index, fragment) do
          {:ok, value} -> {:ok, value}
          :error -> {:error, {:unresolved_reference, kind, id}}
        end
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

  defp coerce_input_context(model, context) do
    Enum.reduce_while(model.input_data, {:ok, context}, fn {_id, input}, {:ok, result} ->
      keys =
        [input.name, input.variable && input.variable.name, input.id] |> Enum.reject(&is_nil/1)

      case Enum.find(keys, &Map.has_key?(result, &1)) do
        nil ->
          {:cont, {:ok, result}}

        key ->
          case coerce_type(
                 Map.fetch!(result, key),
                 input.variable && input.variable.type_ref,
                 model
               ) do
            {:ok, value} -> {:cont, {:ok, Enum.reduce(keys, result, &Map.put(&2, &1, value))}}
            {:error, _reason} = error -> {:halt, error}
          end
      end
    end)
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

  defp bind_reference_value(context, node, value, href, model) do
    context = bind_value(context, node, value)

    case String.split(href, "#", parts: 2) do
      [namespace, _id] ->
        case Map.get(model.imports, namespace) do
          alias_name when is_binary(alias_name) ->
            Map.update(context, alias_name, %{node.name => value}, &Map.put(&1, node.name, value))

          _ ->
            context
        end

      _ ->
        context
    end
  end

  defp evaluate_invocation(%Invocation{} = invocation, context, model) do
    with %LiteralExpression{text: function_name} when is_binary(function_name) <-
           invocation.function,
         {:ok, bkm} <- find_bkm(model, String.trim(function_name)),
         :ok <- validate_invocation_result_shape(invocation, bkm),
         {:ok, bindings} <- evaluate_bindings(invocation.bindings, context, model),
         :ok <- validate_bkm_arguments(bkm, bindings),
         values = Enum.map(bkm.parameters, &Map.fetch!(bindings, &1.name)),
         {:ok, values} <- coerce_parameter_values(values, bkm.parameters, model),
         bindings = Map.new(Enum.zip(Enum.map(bkm.parameters, & &1.name), values)),
         {:ok, bkm_context, _memo} <-
           resolve_requirements(model, bkm, context, %{}, MapSet.new()),
         {:ok, result} <-
           evaluate_expression(bkm.expression, Map.merge(bkm_context, bindings), model) do
      coerce_type(result, bkm.variable && bkm.variable.type_ref, model)
    else
      nil -> {:error, :missing_invocation_function}
      error -> error
    end
  end

  defp validate_invocation_result_shape(
         %Invocation{type_ref: type},
         %BusinessKnowledgeModel{expression: %LiteralExpression{text: text}}
       )
       when type in ["string", "number", "boolean"] and is_binary(text) do
    if String.starts_with?(String.trim(text), "["),
      do: {:error, {:invocation_type_error, type}},
      else: :ok
  end

  defp validate_invocation_result_shape(_invocation, _bkm), do: :ok

  defp invoke_bkm_from_feel(model, bkm, outer_context, args) do
    names = Enum.map(bkm.parameters, & &1.name)

    self_callable =
      {:external_function,
       fn recursive_args -> invoke_bkm_from_feel(model, bkm, outer_context, recursive_args) end}

    with {:ok, values} <- normalize_service_args(args, names),
         {:ok, values} <- coerce_parameter_values(values, bkm.parameters, model),
         {:ok, bkm_context, _memo} <-
           resolve_requirements(model, bkm, outer_context, %{}, MapSet.new()),
         {:ok, result} <-
           evaluate_expression(
             bkm.expression,
             bkm_context
             |> bind_value(bkm, self_callable)
             |> Map.merge(Map.new(Enum.zip(names, values))),
             model
           ) do
      coerce_type(result, bkm.variable && bkm.variable.type_ref, model)
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
      result =
        case outputs do
          [{_name, value}] -> value
          values -> Map.new(values)
        end

      coerce_type(result, service.variable && service.variable.type_ref, model)
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
         {:ok, values} <- coerce_input_values(values, inputs, model) do
      {:ok, Map.merge(outer_context, Map.new(Enum.zip(names, values)))}
    end
  end

  defp coerce_input_values(values, inputs, model) do
    types = Enum.map(inputs, fn input -> input.variable && input.variable.type_ref end)
    coerce_values(values, types, model)
  end

  defp coerce_parameter_values(values, parameters, model) do
    coerce_values(values, Enum.map(parameters, & &1.type_ref), model)
  end

  defp coerce_values(values, types, model) do
    Enum.zip(values, types)
    |> Enum.reduce_while({:ok, []}, fn {value, type}, {:ok, result} ->
      case coerce_type(value, type, model) do
        {:ok, coerced} -> {:cont, {:ok, result ++ [coerced]}}
        {:error, _reason} = error -> {:halt, error}
      end
    end)
  end

  defp coerce_type(value, nil, _model), do: {:ok, value}
  defp coerce_type(nil, _type, _model), do: {:ok, nil}

  defp coerce_type([value], type, model) when type in ["string", "number", "boolean"],
    do: coerce_type(value, type, model)

  defp coerce_type(value, "string", _model) when is_binary(value), do: {:ok, value}
  defp coerce_type(%Decimal{} = value, "number", _model), do: {:ok, value}

  defp coerce_type(value, "number", _model) when is_binary(value) do
    case Decimal.parse(value) do
      {number, ""} -> {:ok, number}
      _ -> {:error, {:type_error, "number"}}
    end
  end

  defp coerce_type(value, "boolean", _model) when is_boolean(value), do: {:ok, value}
  defp coerce_type("true", "boolean", _model), do: {:ok, true}
  defp coerce_type("false", "boolean", _model), do: {:ok, false}
  defp coerce_type(%Date{} = value, "date", _model), do: {:ok, value}
  defp coerce_type(value, "date", _model) when is_binary(value), do: Date.from_iso8601(value)
  defp coerce_type(%Boxic.FEEL.Time{} = value, "time", _model), do: {:ok, value}
  defp coerce_type(%Time{} = value, "time", _model), do: {:ok, value}

  defp coerce_type(value, "time", _model) when is_binary(value) do
    case Boxic.FEEL.Time.parse(value) do
      {:ok, time} -> {:ok, time}
      :error -> {:error, {:type_error, "time"}}
    end
  end

  defp coerce_type(%Boxic.FEEL.DateTime{} = value, "date and time", _model), do: {:ok, value}
  defp coerce_type(%Boxic.FEEL.DateTime{} = value, "dateTime", _model), do: {:ok, value}
  defp coerce_type(%DateTime{} = value, "date and time", _model), do: {:ok, value}
  defp coerce_type(%DateTime{} = value, "dateTime", _model), do: {:ok, value}
  defp coerce_type(%NaiveDateTime{} = value, "date and time", _model), do: {:ok, value}
  defp coerce_type(%NaiveDateTime{} = value, "dateTime", _model), do: {:ok, value}

  defp coerce_type(value, type, _model)
       when is_binary(value) and type in ["date and time", "dateTime"] do
    case Boxic.FEEL.DateTime.parse(value) do
      {:ok, datetime} -> {:ok, datetime}
      :error -> {:error, {:type_error, type}}
    end
  end

  defp coerce_type(%Boxic.FEEL.Duration{} = value, "duration", _model), do: {:ok, value}

  defp coerce_type(value, type, _model)
       when is_binary(value) and
              type in [
                "duration",
                "dayTimeDuration",
                "yearMonthDuration",
                "days and time duration",
                "years and months duration"
              ] do
    case Boxic.FEEL.Duration.parse_iso8601(value) do
      {:ok, duration} -> coerce_duration_kind(duration, type)
      {:error, _reason} -> {:error, {:type_error, type}}
    end
  end

  defp coerce_type(%Boxic.FEEL.Duration{kind: :day_time} = value, "dayTimeDuration", _model),
    do: {:ok, value}

  defp coerce_type(
         %Boxic.FEEL.Duration{kind: :year_month} = value,
         "yearMonthDuration",
         _model
       ),
       do: {:ok, value}

  defp coerce_type(
         %Boxic.FEEL.Duration{kind: :day_time} = value,
         "days and time duration",
         _model
       ),
       do: {:ok, value}

  defp coerce_type(
         %Boxic.FEEL.Duration{kind: :year_month} = value,
         "years and months duration",
         _model
       ),
       do: {:ok, value}

  defp coerce_type(value, "Any", _model), do: {:ok, value}

  defp coerce_type(value, type, model) do
    case find_item_definition(model, type) do
      nil -> {:error, {:type_error, type}}
      definition -> coerce_item_definition(value, definition, model)
    end
  end

  defp find_item_definition(model, type) do
    qualified =
      case String.split(type, ".", parts: 2) do
        [alias_name, local_name] ->
          Enum.find_value(model.imports, fn
            {namespace, ^alias_name} ->
              Map.get(model.item_definitions, namespace <> "#" <> local_name)

            _entry ->
              nil
          end)

        _ ->
          nil
      end

    qualified ||
      Enum.find_value(model.item_definitions, fn {_id, definition} ->
        definition.name == type && definition
      end)
  end

  defp coerce_duration_kind(duration, "duration"), do: {:ok, duration}

  defp coerce_duration_kind(%Boxic.FEEL.Duration{kind: :day_time} = duration, type)
       when type in ["dayTimeDuration", "days and time duration"],
       do: {:ok, duration}

  defp coerce_duration_kind(%Boxic.FEEL.Duration{kind: :year_month} = duration, type)
       when type in ["yearMonthDuration", "years and months duration"],
       do: {:ok, duration}

  defp coerce_duration_kind(_duration, type), do: {:error, {:type_error, type}}

  defp coerce_item_definition(value, %{is_collection: true} = definition, model) do
    values = if is_list(value), do: value, else: [value]

    values
    |> Enum.reduce_while({:ok, []}, fn item, {:ok, result} ->
      case coerce_type(item, definition.type_ref || "Any", model) do
        {:ok, coerced} -> {:cont, {:ok, result ++ [coerced]}}
        {:error, _reason} = error -> {:halt, error}
      end
    end)
  end

  defp coerce_item_definition(value, %{components: components} = definition, model)
       when components != [] do
    if is_map(value) and not is_struct(value) do
      Enum.reduce_while(components, {:ok, value}, fn component, {:ok, result} ->
        case Map.fetch(value, component.name) do
          {:ok, item} ->
            case coerce_item_component(item, component, model) do
              {:ok, coerced} -> {:cont, {:ok, Map.put(result, component.name, coerced)}}
              {:error, _reason} = error -> {:halt, error}
            end

          :error ->
            if definition.id,
              do: {:halt, {:ok, nil}},
              else: {:halt, {:error, {:missing_context_component, component.name}}}
        end
      end)
    else
      {:error, {:type_error, :context}}
    end
  end

  defp coerce_item_definition(value, definition, model),
    do: coerce_item_base(value, definition.type_ref, model)

  defp coerce_item_component(value, %{is_collection: true} = component, model) do
    values = if is_list(value), do: value, else: [value]

    Enum.reduce_while(values, {:ok, []}, fn item, {:ok, result} ->
      case coerce_type(item, component.type_ref || "Any", model) do
        {:ok, coerced} -> {:cont, {:ok, result ++ [coerced]}}
        {:error, _reason} = error -> {:halt, error}
      end
    end)
  end

  defp coerce_item_component(value, component, model),
    do: coerce_type(value, component.type_ref || "Any", model)

  defp coerce_item_base(%Boxic.FEEL.Function{} = value, "function:" <> _output_type, _model),
    do: {:ok, value}

  defp coerce_item_base({:external_function, _} = value, "function:" <> _output_type, _model),
    do: {:ok, value}

  defp coerce_item_base({:builtin, _} = value, "function:" <> _output_type, _model),
    do: {:ok, value}

  defp coerce_item_base(value, "function:" <> output_type, model),
    do: coerce_type(value, output_type, model)

  defp coerce_item_base(value, type, model), do: coerce_type(value, type, model)

  defp service_inputs(model, references) do
    Enum.reduce_while(references, {:ok, []}, fn id, {:ok, inputs} ->
      node = Map.get(model.input_data, id) || Map.get(model.decisions, id)

      if node,
        do: {:cont, {:ok, inputs ++ [node]}},
        else: {:halt, {:error, {:unresolved_service_input, id}}}
    end)
  end

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
          case evaluate_decision(model, decision, context, memo, %{}) do
            {:ok, value, memo} -> {:cont, {:ok, outputs ++ [{decision.name, value}], memo}}
            {:error, _reason} = error -> {:halt, error}
          end

        :error ->
          {:halt, {:error, {:unresolved_service_output, id}}}
      end
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
end
