defmodule Boxic.FEEL.Evaluator do
  @moduledoc false
  alias Boxic.FEEL.{Builtins, Duration, Error, ExternalFunctions, Function, Range, Semantics}
  alias Boxic.FEEL.DateTime, as: FeelDateTime
  alias Boxic.FEEL.Time, as: FeelTime

  def evaluate_unary_test(test_expression, value, context) do
    trimmed = String.trim(test_expression)

    cond do
      trimmed == "-" ->
        {:ok, true}

      String.starts_with?(trimmed, "not(") and String.ends_with?(trimmed, ")") ->
        inner = trimmed |> String.slice(4, String.length(trimmed) - 5)

        with {:ok, matches?} <- evaluate_unary_test(inner, value, context),
             do: {:ok, not matches?}

      comparator_unary_test?(trimmed) ->
        eval_comparator_unary_test(trimmed, value, context)

      range_unary_test?(trimmed) ->
        with {:ok, range_value} <- Boxic.FEEL.evaluate(trimmed, context),
             true <- match?(%Range{}, range_value) do
          {:ok, range_contains?(range_value, value)}
        else
          false -> {:error, error(:type_error, "range unary test expected a range")}
          {:error, %Error{} = e} -> {:error, e}
        end

      true ->
        with {:ok, expected} <- Boxic.FEEL.evaluate(trimmed, context) do
          if is_list(expected),
            do: {:ok, Enum.any?(expected, &Semantics.equal?(value, &1))},
            else: {:ok, Semantics.equal?(value, expected)}
        end
    end
  end

  def eval({:literal, value}, _context), do: {:ok, value}

  def eval({:identifier, name}, context) do
    case Map.fetch(context, name) do
      {:ok, value} ->
        {:ok, value}

      :error ->
        Builtins.resolve(name)
    end
  end

  def eval({:list, items}, context) do
    eval_list(items, context, [])
  end

  def eval({:context, entries}, context) do
    eval_context_entries(entries, context, %{})
  end

  def eval({:path, expr, key}, context) do
    with {:ok, value} <- eval(expr, context) do
      case value do
        list when is_list(list) ->
          {:ok, Enum.map(list, fn item -> if is_map(item), do: Map.get(item, key), else: nil end)}

        map when is_map(map) ->
          {:ok, property_value(map, key)}

        {:unary_test_value, operator, _operand} = unary_test
        when operator in [:lt, :lte, :gt, :gte, :eq] ->
          {:ok, property_value(unary_test, key)}

        _ ->
          {:ok, nil}
      end
    end
  end

  def eval({:filter, source_expr, predicate}, context) do
    with {:ok, source} <- eval(source_expr, context) do
      case source do
        list when is_list(list) ->
          eval_list_filter(list, predicate, context)

        scalar ->
          eval_scalar_filter(scalar, predicate, context)
      end
    end
  end

  def eval({:range, start_inclusive, end_inclusive, start_ast, end_ast}, context) do
    with {:ok, start_value} <- eval(start_ast, context),
         {:ok, end_value} <- eval(end_ast, context) do
      {:ok,
       %Range{
         start: start_value,
         end: end_value,
         start_inclusive: start_inclusive,
         end_inclusive: end_inclusive
       }}
    end
  end

  def eval({:if, condition_ast, then_ast, else_ast}, context) do
    with {:ok, condition} <- eval(condition_ast, context) do
      case condition do
        true -> eval(then_ast, context)
        false -> eval(else_ast, context)
        nil -> eval(else_ast, context)
        _ -> {:error, error(:type_error, "if condition must be boolean")}
      end
    end
  end

  def eval({:in, value_ast, tests_ast}, context) do
    with {:ok, value} <- eval(value_ast, context) do
      evaluate_in(value, tests_ast, context)
    end
  end

  def eval({:between, value_ast, lower_ast, upper_ast}, context) do
    with {:ok, value} <- eval(value_ast, context),
         {:ok, lower} <- eval(lower_ast, context),
         {:ok, upper} <- eval(upper_ast, context),
         {:ok, above} <- eval_binary(:gte, value, lower),
         {:ok, below} <- eval_binary(:lte, value, upper) do
      {:ok, feel_and(above, below)}
    end
  end

  def eval({:instance_of, value_ast, type}, context) do
    with {:ok, value} <- eval(value_ast, context) do
      {:ok, instance_of?(value, type, context)}
    end
  end

  def eval({:unary_test, operator, operand_ast}, context) do
    with {:ok, operand} <- eval(operand_ast, context) do
      {:ok, {:unary_test_value, operator, operand}}
    end
  end

  def eval({:sequence, first_ast, last_ast}, context) do
    with {:ok, first} <- eval(first_ast, context),
         {:ok, last} <- eval(last_ast, context) do
      {:ok, {:sequence, first, last}}
    end
  end

  def eval({:for, var, source_ast, body_ast}, context) do
    with {:ok, source} <- eval(source_ast, context) do
      case source do
        list when is_list(list) ->
          list
          |> Enum.reduce_while({:ok, []}, fn item, {:ok, acc} ->
            scoped_context = Map.put(context, var, item)

            case eval(body_ast, scoped_context) do
              {:ok, value} -> {:cont, {:ok, acc ++ [value]}}
              {:error, %Error{} = e} -> {:halt, {:error, e}}
            end
          end)

        _ ->
          {:error, error(:type_error, "for-expression source must be a list")}
      end
    end
  end

  def eval({:for, bindings, body_ast}, context) when is_list(bindings) do
    with {:ok, contexts} <- expand_for_contexts(bindings, [context]) do
      Enum.reduce_while(contexts, {:ok, []}, fn scoped_context, {:ok, acc} ->
        case eval(body_ast, Map.put(scoped_context, "partial", acc)) do
          {:ok, value} -> {:cont, {:ok, acc ++ [value]}}
          {:error, %Error{} = error} -> {:halt, {:error, error}}
        end
      end)
    end
  end

  def eval({:quantifier, kind, var, source_ast, predicate_ast}, context) do
    with {:ok, source} <- eval(source_ast, context) do
      case source do
        list when is_list(list) ->
          case kind do
            :some -> {:ok, Enum.any?(list, &quantifier_match?(&1, var, predicate_ast, context))}
            :every -> {:ok, Enum.all?(list, &quantifier_match?(&1, var, predicate_ast, context))}
          end

        _ ->
          {:error, error(:type_error, "quantifier source must be a list")}
      end
    end
  end

  def eval({:function, params, body}, context) do
    {:ok, %Function{params: params, body: body, closure: context}}
  end

  def eval({:call, {:identifier, name}, args_ast}, context) do
    with {:ok, callee} <- resolve_callable(name, context),
         {:ok, arg_values} <- eval_call_args(args_ast, context, []) do
      case callee do
        {:builtin, "range"} -> apply_range_function(arg_values, context)
        _ -> apply_function(callee, arg_values)
      end
    end
  end

  def eval({:call, callee_ast, args_ast}, context) do
    with {:ok, callee} <- eval(callee_ast, context),
         {:ok, arg_values} <- eval_call_args(args_ast, context, []) do
      case callee do
        {:builtin, "range"} -> apply_range_function(arg_values, context)
        _ -> apply_function(callee, arg_values)
      end
    end
  end

  def eval({:unary, :not, expr}, context) do
    with {:ok, value} <- eval(expr, context) do
      {:ok, feel_not(value)}
    end
  end

  def eval({:unary, :negate, expr}, context) do
    with {:ok, value} <- eval(expr, context) do
      case value do
        nil -> {:ok, nil}
        %Decimal{} = decimal -> {:ok, decimal_negate(decimal)}
        %Duration{} = duration -> {:ok, Duration.negate(duration)}
        _ -> {:error, error(:type_error, "negation requires a number")}
      end
    end
  end

  def eval({:binary, op, left, right}, context) do
    with {:ok, left_value} <- eval(left, context),
         {:ok, right_value} <- eval(right, context) do
      eval_binary(op, left_value, right_value)
    end
  end

  defp property_value(%Date{} = value, "year"), do: decimal_new(value.year)
  defp property_value(%Date{} = value, "month"), do: decimal_new(value.month)
  defp property_value(%Date{} = value, "day"), do: decimal_new(value.day)
  defp property_value(%Date{} = value, "weekday"), do: decimal_new(Date.day_of_week(value))

  defp property_value(%FeelDateTime{date: date}, key) when key in ~w(year month day weekday),
    do: property_value(date, key)

  defp property_value(%FeelDateTime{time: time}, key), do: property_value(time, key)
  defp property_value(%FeelTime{} = value, "hour"), do: decimal_new(value.hour)
  defp property_value(%FeelTime{} = value, "minute"), do: decimal_new(value.minute)
  defp property_value(%FeelTime{} = value, "second"), do: value.second

  defp property_value(%FeelTime{zone: {:offset, seconds}}, "time offset"),
    do: Duration.from_seconds(seconds)

  defp property_value(%FeelTime{}, "time offset"), do: nil
  defp property_value(%FeelTime{zone: {:iana, name}}, "timezone"), do: name
  defp property_value(%FeelTime{}, "timezone"), do: nil

  defp property_value(%Duration{kind: :year_month, months: months}, "years"),
    do: decimal_new(div(months, 12))

  defp property_value(%Duration{kind: :year_month, months: months}, "months"),
    do: decimal_new(rem(months, 12))

  defp property_value(%Duration{}, key) when key in ~w(years months), do: nil

  defp property_value(%Duration{kind: :day_time, seconds: seconds}, "days"),
    do: seconds_component(seconds, 86_400, :quotient)

  defp property_value(%Duration{kind: :day_time, seconds: seconds}, "hours"),
    do: seconds_component(seconds, 3_600, :remainder)

  defp property_value(%Duration{kind: :day_time, seconds: seconds}, "minutes"),
    do: seconds_component(seconds, 60, :remainder)

  defp property_value(%Duration{kind: :day_time, seconds: seconds}, "seconds"),
    do: Decimal.rem(decimal_value(seconds), Decimal.new(60))

  defp property_value(%Duration{}, key) when key in ~w(days hours minutes seconds), do: nil

  defp property_value(%Range{} = value, "start"), do: value.start
  defp property_value(%Range{} = value, "end"), do: value.end
  defp property_value(%Range{} = value, "start included"), do: value.start_inclusive
  defp property_value(%Range{} = value, "end included"), do: value.end_inclusive

  defp property_value({:unary_test_value, operator, operand}, property)
       when operator in [:lt, :lte, :gt, :gte, :eq] do
    range =
      case operator do
        :lt -> %Range{start: nil, end: operand, start_inclusive: false, end_inclusive: false}
        :lte -> %Range{start: nil, end: operand, start_inclusive: false, end_inclusive: true}
        :gt -> %Range{start: operand, end: nil, start_inclusive: false, end_inclusive: false}
        :gte -> %Range{start: operand, end: nil, start_inclusive: true, end_inclusive: false}
        :eq -> %Range{start: operand, end: operand, start_inclusive: true, end_inclusive: true}
      end

    property_value(range, property)
  end

  defp property_value(map, key), do: Map.get(map, key)

  defp seconds_component(seconds, divisor, :quotient) do
    seconds |> decimal_value() |> Decimal.div_int(divisor) |> Decimal.round(0, :down)
  end

  defp seconds_component(seconds, divisor, :remainder) do
    seconds
    |> decimal_value()
    |> Decimal.div_int(divisor)
    |> Decimal.round(0, :down)
    |> Decimal.rem(Decimal.new(if(divisor == 3_600, do: 24, else: 60)))
  end

  defp decimal_value(%Decimal{} = value), do: value
  defp decimal_value(value), do: decimal_new(value)

  defp resolve_callable(name, context) do
    case ExternalFunctions.resolve(context, name) do
      {:ok, callable} ->
        {:ok, callable}

      :error ->
        case Map.fetch(context, name) do
          {:ok, callable} -> {:ok, callable}
          :error -> {:error, error(:unknown_identifier, "unknown identifier #{inspect(name)}")}
        end
    end
  end

  defp eval_call_args([], _context, acc), do: {:ok, Enum.reverse(acc)}

  defp eval_call_args([{:named_arg, name, value_ast} | rest], context, acc) do
    with {:ok, value} <- eval(value_ast, context) do
      eval_call_args(rest, context, [{:named_arg, name, value} | acc])
    end
  end

  defp eval_call_args([arg_ast | rest], context, acc) do
    with {:ok, value} <- eval(arg_ast, context) do
      eval_call_args(rest, context, [value | acc])
    end
  end

  defp eval_list([], _context, acc), do: {:ok, acc}

  defp eval_list([item_ast | rest], context, acc) do
    with {:ok, value} <- eval(item_ast, context) do
      eval_list(rest, context, acc ++ [value])
    end
  end

  defp eval_context_entries([], _context, acc), do: {:ok, acc}

  defp eval_context_entries([{key, value_ast} | rest], context, acc) do
    scoped_context = Map.merge(context, acc)

    with {:ok, value} <- eval(value_ast, scoped_context) do
      eval_context_entries(rest, context, Map.put(acc, key, value))
    end
  end

  defp expand_for_contexts([], contexts), do: {:ok, contexts}

  defp expand_for_contexts([{variable, source_ast} | rest], contexts) do
    contexts
    |> Enum.reduce_while({:ok, []}, fn scoped_context, {:ok, acc} ->
      with {:ok, source} <- eval(source_ast, scoped_context),
           {:ok, values} <- iteration_values(source) do
        expanded = Enum.map(values, &Map.put(scoped_context, variable, &1))
        {:cont, {:ok, acc ++ expanded}}
      else
        {:error, %Error{} = error} -> {:halt, {:error, error}}
      end
    end)
    |> case do
      {:ok, expanded} -> expand_for_contexts(rest, expanded)
      {:error, %Error{} = error} -> {:error, error}
    end
  end

  defp iteration_values(values) when is_list(values), do: {:ok, values}

  defp iteration_values({:sequence, %Decimal{} = first, %Decimal{} = last}) do
    numeric_sequence(first, last, true)
  end

  defp iteration_values({:sequence, %Date{} = first, %Date{} = last}) do
    step = if Date.compare(first, last) in [:lt, :eq], do: 1, else: -1
    count = abs(Date.diff(last, first))
    {:ok, Enum.map(0..count, &Date.add(first, &1 * step))}
  end

  defp iteration_values(%Range{start: %Decimal{} = first, end: %Decimal{} = last}) do
    numeric_sequence(first, last, false)
  end

  defp iteration_values(_source),
    do: {:error, error(:type_error, "for-expression source must be a list or numeric range")}

  defp numeric_sequence(first, last, descending_allowed?) do
    with {:ok, first_integer} <- decimal_integer(first),
         {:ok, last_integer} <- decimal_integer(last),
         true <- descending_allowed? or first_integer <= last_integer do
      step = if first_integer <= last_integer, do: 1, else: -1

      values =
        first_integer
        |> Elixir.Range.new(last_integer, step)
        |> Enum.map(&decimal_new/1)

      {:ok, values}
    else
      false -> {:error, error(:evaluation_error, "range start must not exceed its end")}
      :error -> {:error, error(:type_error, "numeric iteration range requires integers")}
    end
  end

  defp eval_list_filter(list, predicate, context) do
    case eval(predicate, context) do
      {:ok, %Decimal{} = index} ->
        {:ok, list_index(list, index)}

      _ ->
        filtered =
          Enum.filter(list, fn item ->
            predicate_context = bind_item_context(context, item)

            case eval(predicate, predicate_context) do
              {:ok, true} -> true
              _ -> false
            end
          end)

        {:ok, filtered}
    end
  end

  defp eval_scalar_filter(scalar, predicate, context) do
    predicate_context = bind_item_context(context, scalar)

    case eval(predicate, predicate_context) do
      {:ok, true} -> {:ok, [scalar]}
      {:ok, false} -> {:ok, []}
      {:ok, nil} -> {:ok, []}
      {:ok, %Decimal{} = index} -> {:ok, scalar_index(scalar, index)}
      {:ok, _other} -> {:ok, nil}
      {:error, %Error{} = error} -> {:error, error}
    end
  end

  defp list_index(list, index) do
    with {:ok, position} <- decimal_integer(index),
         true <- position != 0 do
      if position > 0, do: Enum.at(list, position - 1), else: Enum.at(list, position)
    else
      _ -> nil
    end
  end

  defp scalar_index(scalar, index) do
    case decimal_integer(index) do
      {:ok, position} when position in [1, -1] -> scalar
      _ -> nil
    end
  end

  defp bind_item_context(context, item) do
    base = Map.put(context, "item", item)

    case item do
      map when is_map(map) and not is_struct(map) ->
        Enum.reduce(map, base, fn
          {k, v}, acc when is_binary(k) -> Map.put(acc, k, v)
          _entry, acc -> acc
        end)

      _ ->
        base
    end
  end

  defp quantifier_match?(item, var, predicate_ast, context) do
    scoped_context = Map.put(context, var, item)

    case eval(predicate_ast, scoped_context) do
      {:ok, true} -> true
      _ -> false
    end
  end

  defp apply_function(%Function{params: params, body: body, closure: closure}, args) do
    with {:ok, args} <- order_function_args(params, args),
         true <- length(params) == length(args) do
      if Enum.zip(params, args)
         |> Enum.all?(fn {{_name, type}, value} -> parameter_type?(value, type) end) do
        call_context =
          params
          |> Enum.zip(args)
          |> Enum.reduce(closure, fn {{name, _type}, value}, acc -> Map.put(acc, name, value) end)

        eval(body, call_context)
      else
        {:error, error(:type_error, "function argument does not conform to parameter type")}
      end
    else
      _ -> {:error, error(:arity_error, "function called with invalid arguments")}
    end
  end

  defp apply_function({:builtin, "sort"}, [values, comparator]) when is_list(values) do
    sort_with_comparator(values, comparator)
  end

  defp apply_function({:builtin, "list_replace"}, [list, matcher, new_item])
       when is_list(list) and is_struct(matcher, Function) do
    Enum.reduce_while(list, {:ok, []}, fn item, {:ok, result} ->
      case apply_function(matcher, [item, new_item]) do
        {:ok, true} ->
          {:cont, {:ok, result ++ [new_item]}}

        {:ok, false} ->
          {:cont, {:ok, result ++ [item]}}

        {:ok, _value} ->
          {:halt, {:error, error(:type_error, "list replace match must return boolean")}}

        {:error, %Error{} = error} ->
          {:halt, {:error, error}}
      end
    end)
  end

  defp apply_function({:builtin, "list_replace"} = builtin, args) do
    if Enum.all?(args, &match?({:named_arg, _, _}, &1)) do
      values = Map.new(args, fn {:named_arg, name, value} -> {name, value} end)

      cond do
        Map.keys(values) |> Enum.sort() == ["list", "match", "newItem"] |> Enum.sort() ->
          apply_function(builtin, [values["list"], values["match"], values["newItem"]])

        Map.keys(values) |> Enum.sort() == ["list", "newItem", "position"] |> Enum.sort() ->
          apply_function(builtin, [values["list"], values["position"], values["newItem"]])

        true ->
          {:error, error(:arity_error, "invalid named arguments for list replace")}
      end
    else
      Builtins.invoke("list_replace", args)
    end
  end

  defp apply_function({:builtin, name}, args) do
    Builtins.invoke(name, args)
  end

  defp apply_function({:external_function, function}, args) when is_function(function, 1) do
    case function.(args) do
      {:ok, value} -> {:ok, value}
      {:error, %Error{} = error} -> {:error, error}
      {:error, reason} -> {:error, error(:evaluation_error, inspect(reason))}
    end
  end

  defp apply_function(fun, args) when is_function(fun, length(args)) do
    {:ok, apply(fun, args)}
  end

  defp apply_function(_callee, _args),
    do: {:error, error(:type_error, "attempted to call a non-function value")}

  defp order_function_args(params, args) do
    names = Enum.map(params, &elem(&1, 0))

    Enum.reduce_while(args, {:ok, %{}, names}, fn
      {:named_arg, name, value}, {:ok, bound, remaining} ->
        if name in remaining do
          {:cont, {:ok, Map.put(bound, name, value), List.delete(remaining, name)}}
        else
          {:halt, :error}
        end

      value, {:ok, bound, [name | remaining]} ->
        {:cont, {:ok, Map.put(bound, name, value), remaining}}

      _value, {:ok, _bound, []} ->
        {:halt, :error}
    end)
    |> case do
      {:ok, bound, []} -> {:ok, Enum.map(names, &Map.fetch!(bound, &1))}
      _ -> :error
    end
  end

  defp apply_range_function([{:named_arg, "from", value}], context),
    do: apply_range_function([value], context)

  defp apply_range_function([source], context) when is_binary(source) do
    with {:ok, ast} <- Boxic.FEEL.parse(String.trim(source)),
         true <- valid_range_ast?(ast),
         {:ok, %Range{} = range} <- Boxic.FEEL.evaluate_ast(ast, context),
         {:ok, true} <- eval_binary(:lte, range.start, range.end) do
      {:ok, range}
    else
      _ -> {:error, error(:evaluation_error, "invalid range string")}
    end
  end

  defp apply_range_function(_args, _context),
    do: {:error, error(:type_error, "range expects one string argument")}

  defp valid_range_ast?({:range, _start_inclusive, _end_inclusive, start_ast, end_ast}),
    do: valid_range_endpoint_ast?(start_ast) and valid_range_endpoint_ast?(end_ast)

  defp valid_range_ast?(_ast), do: false

  defp valid_range_endpoint_ast?({:literal, value}), do: not is_nil(value)

  defp valid_range_endpoint_ast?({:call, {:identifier, name}, [{:literal, value}]})
       when name in ["date", "date_time", "time", "duration"],
       do: is_binary(value)

  defp valid_range_endpoint_ast?(_ast), do: false

  defp parameter_type?(_value, nil), do: true
  defp parameter_type?(%Decimal{}, "number"), do: true
  defp parameter_type?(value, "string"), do: is_binary(value)
  defp parameter_type?(value, "boolean"), do: is_boolean(value)
  defp parameter_type?(_value, _type), do: false

  defp sort_with_comparator(values, comparator) do
    values
    |> Enum.reduce_while({:ok, []}, fn value, {:ok, sorted} ->
      case insert_with_comparator(value, sorted, comparator, []) do
        {:ok, next} -> {:cont, {:ok, next}}
        {:error, %Error{} = error} -> {:halt, {:error, error}}
      end
    end)
  end

  defp insert_with_comparator(value, [], _comparator, prefix),
    do: {:ok, Enum.reverse(prefix, [value])}

  defp insert_with_comparator(value, [head | tail] = remaining, comparator, prefix) do
    case apply_function(comparator, [value, head]) do
      {:ok, true} -> {:ok, Enum.reverse(prefix, [value | remaining])}
      {:ok, false} -> insert_with_comparator(value, tail, comparator, [head | prefix])
      {:ok, _} -> {:error, error(:type_error, "sort comparator must return a boolean")}
      {:error, %Error{} = error} -> {:error, error}
    end
  end

  defp eval_binary(:plus, left, right), do: plus(left, right)
  defp eval_binary(:minus, left, right), do: minus(left, right)

  defp eval_binary(:mul, %Duration{} = duration, %Decimal{} = factor),
    do: {:ok, Duration.scale(duration, factor)}

  defp eval_binary(:mul, %Decimal{} = factor, %Duration{} = duration),
    do: {:ok, Duration.scale(duration, factor)}

  defp eval_binary(:mul, left, right), do: decimal_binary(left, right, &decimal_mult/2)
  defp eval_binary(:pow, left, right), do: decimal_power(left, right)

  defp eval_binary(:div, left, right) do
    case {left, right} do
      {nil, _} ->
        {:ok, nil}

      {_, nil} ->
        {:ok, nil}

      {%Decimal{} = l, %Decimal{} = r} ->
        if decimal_equal?(r, decimal_new("0")) do
          {:ok, nil}
        else
          {:ok, decimal_div(l, r)}
        end

      {%Duration{} = duration, %Decimal{} = divisor} ->
        if decimal_equal?(divisor, decimal_new("0")) do
          {:ok, nil}
        else
          {:ok, Duration.scale(duration, decimal_div(decimal_new("1"), divisor))}
        end

      {%Duration{} = left_duration, %Duration{} = right_duration} ->
        case Duration.ratio(left_duration, right_duration) do
          {:ok, ratio} -> {:ok, ratio}
          :error -> {:error, error(:type_error, "division requires compatible durations")}
        end

      _ ->
        {:error, error(:type_error, "division requires numbers")}
    end
  end

  defp eval_binary(op, left, right) when op in [:gt, :gte, :lt, :lte] do
    cond do
      is_nil(left) or is_nil(right) ->
        {:ok, nil}

      match?(%Decimal{}, left) and match?(%Decimal{}, right) ->
        {:ok, compare_from_op(op, decimal_compare(left, right))}

      is_struct(left, Date) and is_struct(right, Date) ->
        {:ok, compare_from_op(op, Date.compare(left, right))}

      is_struct(left, Time) and is_struct(right, Time) ->
        {:ok, compare_from_op(op, Time.compare(left, right))}

      is_struct(left, DateTime) and is_struct(right, DateTime) ->
        {:ok, compare_from_op(op, DateTime.compare(left, right))}

      match?(%FeelTime{}, left) and match?(%FeelTime{}, right) ->
        compare_temporal(op, FeelTime.compare(left, right))

      match?(%FeelDateTime{}, left) and match?(%FeelDateTime{}, right) ->
        compare_temporal(op, FeelDateTime.compare(left, right))

      match?(%Duration{}, left) and match?(%Duration{}, right) ->
        compare_temporal(op, Duration.compare(left, right))

      is_binary(left) and is_binary(right) ->
        {:ok, compare_from_op(op, compare_strings(left, right))}

      is_boolean(left) and is_boolean(right) ->
        {:ok, compare_from_op(op, compare_booleans(left, right))}

      true ->
        {:error, error(:type_error, "comparison requires compatible values")}
    end
  end

  defp eval_binary(:eq, left, right), do: {:ok, feel_equal(left, right)}

  defp eval_binary(:neq, left, right) do
    case feel_equal(left, right) do
      nil -> {:ok, nil}
      equal? -> {:ok, not equal?}
    end
  end

  defp eval_binary(:and, left, right), do: {:ok, feel_and(left, right)}
  defp eval_binary(:or, left, right), do: {:ok, feel_or(left, right)}

  defp instance_of?(value, "Any", _context), do: not is_nil(value)
  defp instance_of?(value, "number", _context), do: match?(%Decimal{}, value)
  defp instance_of?(value, "string", _context), do: is_binary(value)
  defp instance_of?(value, "boolean", _context), do: is_boolean(value)
  defp instance_of?(value, "date", _context), do: match?(%Date{}, value)

  defp instance_of?(value, "time", _context),
    do: match?(%FeelTime{}, value) or match?(%Time{}, value)

  defp instance_of?(value, "date_time", _context),
    do:
      match?(%FeelDateTime{}, value) or match?(%DateTime{}, value) or
        match?(%NaiveDateTime{}, value)

  defp instance_of?(%Duration{kind: :year_month}, "years and months duration", _context),
    do: true

  defp instance_of?(%Duration{kind: :year_month}, "years_and_months_duration", _context),
    do: true

  defp instance_of?(%Duration{kind: :day_time}, "days and time duration", _context), do: true

  defp instance_of?(value, "context<>", _context),
    do: is_map(value) and not is_struct(value)

  defp instance_of?(value, "list<" <> rest, context) when is_list(value) do
    subtype = String.trim_trailing(rest, ">")
    Enum.all?(value, &instance_of?(&1, subtype, context))
  end

  defp instance_of?(value, "context<" <> rest, context)
       when is_map(value) and not is_struct(value) do
    rest
    |> String.trim_trailing(">")
    |> split_type_fields()
    |> Enum.all?(fn {key, subtype} ->
      Map.has_key?(value, key) and
        (is_nil(Map.get(value, key)) or instance_of?(Map.get(value, key), subtype, context))
    end)
  end

  defp instance_of?(%Range{} = range, "range<" <> rest, context) do
    subtype = String.trim_trailing(rest, ">")
    instance_of?(range.start, subtype, context) and instance_of?(range.end, subtype, context)
  end

  defp instance_of?(value, "function<" <> _signature, _context),
    do: match?(%Function{}, value) or match?({:external_function, _}, value)

  defp instance_of?(value, type, context) do
    types = Map.get(context, "__feel_types__", %{})

    case Enum.find_value(types, fn {_id, definition} ->
           Map.get(definition, :name) == type && definition
         end) do
      nil -> false
      definition -> instance_of_definition?(value, definition, context)
    end
  end

  defp instance_of_definition?(value, definition, context) do
    collection? = Map.get(definition, :is_collection) in [true, "true"]

    cond do
      collection? and is_list(value) ->
        Enum.all?(value, &instance_of?(&1, Map.get(definition, :type_ref) || "Any", context))

      collection? ->
        false

      Map.get(definition, :components, []) != [] and is_map(value) and not is_struct(value) ->
        Enum.all?(Map.get(definition, :components), fn component ->
          key = Map.get(component, :name)

          Map.has_key?(value, key) and
            (is_nil(Map.get(value, key)) or
               instance_of?(Map.get(value, key), Map.get(component, :type_ref), context))
        end)

      String.contains?(Map.get(definition, :name, ""), "Function") ->
        match?(%Function{}, value) or match?({:external_function, _}, value)

      is_binary(Map.get(definition, :type_ref)) ->
        instance_of?(value, Map.get(definition, :type_ref), context)

      true ->
        false
    end
  end

  defp split_type_fields(value) do
    value
    |> String.split(~r/,(?![^<]*>)/, trim: true)
    |> Enum.map(fn field ->
      case String.split(field, ":", parts: 2) do
        [key, type] -> {String.trim(key), String.trim(type)}
        _ -> {"", "Any"}
      end
    end)
  end

  defp plus(left, right) do
    case {left, right} do
      {nil, _} ->
        {:ok, nil}

      {_, nil} ->
        {:ok, nil}

      {%Decimal{} = l, %Decimal{} = r} ->
        {:ok, decimal_add(l, r)}

      {left, right} when is_binary(left) and is_binary(right) ->
        {:ok, left <> right}

      {%Date{} = date, %Duration{} = duration} ->
        {:ok, Duration.add_to_date(date, duration)}

      {%Duration{} = duration, %Date{} = date} ->
        {:ok, Duration.add_to_date(date, duration)}

      {%DateTime{} = datetime, %Duration{} = duration} ->
        {:ok, Duration.add_to_datetime(datetime, duration)}

      {%Duration{} = duration, %DateTime{} = datetime} ->
        {:ok, Duration.add_to_datetime(datetime, duration)}

      {%FeelDateTime{} = datetime, %Duration{} = duration} ->
        temporal_arithmetic(FeelDateTime.add_duration(datetime, duration))

      {%Duration{} = duration, %FeelDateTime{} = datetime} ->
        temporal_arithmetic(FeelDateTime.add_duration(datetime, duration))

      {%Time{} = time, %Duration{} = duration} ->
        {:ok, Duration.add_to_time(time, duration)}

      {%Duration{} = duration, %Time{} = time} ->
        {:ok, Duration.add_to_time(time, duration)}

      {%FeelTime{} = time, %Duration{months: 0} = duration} ->
        {:ok, FeelTime.add_seconds(time, duration.seconds)}

      {%Duration{months: 0} = duration, %FeelTime{} = time} ->
        {:ok, FeelTime.add_seconds(time, duration.seconds)}

      {%Duration{kind: kind} = l, %Duration{kind: kind} = r} ->
        {:ok, Duration.add(l, r)}

      {%Duration{}, %Duration{}} ->
        {:error, error(:type_error, "duration kinds must match")}

      _ ->
        {:error, error(:type_error, "addition requires compatible values")}
    end
  end

  defp minus(left, right) do
    case {left, right} do
      {nil, _} ->
        {:ok, nil}

      {_, nil} ->
        {:ok, nil}

      {%Decimal{} = l, %Decimal{} = r} ->
        {:ok, decimal_sub(l, r)}

      {%Date{} = left_date, %Date{} = right_date} ->
        {:ok, Duration.from_days(Date.diff(left_date, right_date))}

      {%DateTime{} = left_datetime, %DateTime{} = right_datetime} ->
        {:ok, Duration.from_seconds(DateTime.diff(left_datetime, right_datetime, :second))}

      {%FeelDateTime{} = left_datetime, %FeelDateTime{} = right_datetime} ->
        temporal_arithmetic(FeelDateTime.difference(left_datetime, right_datetime))

      {%FeelDateTime{} = left_datetime, %Date{} = right_date} ->
        temporal_arithmetic(
          FeelDateTime.difference(
            left_datetime,
            date_at_midnight(right_date, left_datetime.time.zone)
          )
        )

      {%Date{} = left_date, %FeelDateTime{} = right_datetime} ->
        temporal_arithmetic(
          FeelDateTime.difference(
            date_at_midnight(left_date, right_datetime.time.zone),
            right_datetime
          )
        )

      {%FeelTime{} = left_time, %FeelTime{} = right_time} ->
        temporal_arithmetic(FeelTime.difference(left_time, right_time))

      {%Date{} = date, %Duration{} = duration} ->
        {:ok, Duration.add_to_date(date, Duration.negate(duration))}

      {%DateTime{} = datetime, %Duration{} = duration} ->
        {:ok, Duration.add_to_datetime(datetime, Duration.negate(duration))}

      {%FeelDateTime{} = datetime, %Duration{} = duration} ->
        temporal_arithmetic(FeelDateTime.add_duration(datetime, Duration.negate(duration)))

      {%Time{} = time, %Duration{} = duration} ->
        {:ok, Duration.add_to_time(time, Duration.negate(duration))}

      {%FeelTime{} = time, %Duration{months: 0} = duration} ->
        {:ok, FeelTime.add_seconds(time, Duration.negate(duration).seconds)}

      {%Duration{kind: kind} = l, %Duration{kind: kind} = r} ->
        {:ok, Duration.subtract(l, r)}

      {%Duration{}, %Duration{}} ->
        {:error, error(:type_error, "duration kinds must match")}

      _ ->
        {:error, error(:type_error, "subtraction requires compatible values")}
    end
  end

  defp temporal_arithmetic({:ok, value}), do: {:ok, value}

  defp temporal_arithmetic(:error),
    do: {:error, error(:evaluation_error, "temporal operation failed")}

  defp date_at_midnight(date, _zone) do
    {:ok, time} = FeelTime.new(0, 0, 0, {:offset, 0})
    FeelDateTime.new(date, time)
  end

  defp compare_from_op(op, cmp) do
    case op do
      :gt -> cmp == :gt
      :gte -> cmp in [:gt, :eq]
      :lt -> cmp == :lt
      :lte -> cmp in [:lt, :eq]
    end
  end

  defp compare_temporal(_op, :unordered), do: {:ok, nil}
  defp compare_temporal(op, comparison), do: {:ok, compare_from_op(op, comparison)}

  defp compare_strings(left, right) when left == right, do: :eq
  defp compare_strings(left, right) when left < right, do: :lt
  defp compare_strings(_left, _right), do: :gt

  defp compare_booleans(left, right) when left == right, do: :eq
  defp compare_booleans(false, true), do: :lt
  defp compare_booleans(true, false), do: :gt

  defp decimal_binary(left, right, operation) do
    case {left, right} do
      {nil, _} -> {:ok, nil}
      {_, nil} -> {:ok, nil}
      {%Decimal{} = l, %Decimal{} = r} -> {:ok, operation.(l, r)}
      _ -> {:error, error(:type_error, "arithmetic requires numbers")}
    end
  end

  defp decimal_power(nil, _right), do: {:ok, nil}
  defp decimal_power(_left, nil), do: {:ok, nil}

  defp decimal_power(%Decimal{} = base, %Decimal{} = exponent) do
    case decimal_integer(exponent) do
      {:ok, integer} when integer < 0 ->
        powered = decimal_integer_power(base, -integer)

        if decimal_equal?(powered, decimal_new("0")) do
          {:ok, nil}
        else
          {:ok, decimal_div(decimal_new("1"), powered)}
        end

      {:ok, integer} ->
        {:ok, decimal_integer_power(base, integer)}

      :error ->
        {:ok,
         base
         |> Decimal.to_float()
         |> :math.pow(Decimal.to_float(exponent))
         |> Decimal.from_float()}
    end
  end

  defp decimal_power(_left, _right),
    do: {:error, error(:type_error, "exponentiation requires numbers")}

  defp decimal_integer_power(_base, 0), do: decimal_new("1")

  defp decimal_integer_power(base, exponent) do
    decimal_integer_power(base, exponent, decimal_new("1"))
  end

  defp decimal_integer_power(_base, 0, acc), do: acc

  defp decimal_integer_power(base, exponent, acc) when rem(exponent, 2) == 1 do
    decimal_integer_power(decimal_mult(base, base), div(exponent, 2), decimal_mult(acc, base))
  end

  defp decimal_integer_power(base, exponent, acc) do
    decimal_integer_power(decimal_mult(base, base), div(exponent, 2), acc)
  end

  defp decimal_integer(value) do
    integer = Decimal.to_integer(value)
    if decimal_equal?(value, decimal_new(integer)), do: {:ok, integer}, else: :error
  rescue
    _ -> :error
  end

  defp feel_equal(nil, nil), do: true
  defp feel_equal(nil, _right), do: false
  defp feel_equal(_left, nil), do: false
  defp feel_equal(%Decimal{} = left, %Decimal{} = right), do: decimal_equal?(left, right)
  defp feel_equal(left, right) when is_integer(left) and is_integer(right), do: left == right

  defp feel_equal(%Decimal{} = left, right) when is_integer(right),
    do: decimal_equal?(left, decimal_new(right))

  defp feel_equal(left, %Decimal{} = right) when is_integer(left),
    do: decimal_equal?(decimal_new(left), right)

  defp feel_equal(left, right) when is_boolean(left) and is_boolean(right), do: left == right
  defp feel_equal(left, right) when is_binary(left) and is_binary(right), do: left == right
  defp feel_equal(%Date{} = left, %Date{} = right), do: Date.compare(left, right) == :eq
  defp feel_equal(%Time{} = left, %Time{} = right), do: Time.compare(left, right) == :eq

  defp feel_equal(%DateTime{} = left, %DateTime{} = right),
    do: DateTime.compare(left, right) == :eq

  defp feel_equal(%FeelTime{} = left, %FeelTime{} = right),
    do:
      left.zone == right.zone and left.hour == right.hour and left.minute == right.minute and
        Decimal.equal?(
          Decimal.round(left.second, 0, :down),
          Decimal.round(right.second, 0, :down)
        )

  defp feel_equal(%FeelDateTime{} = left, %FeelDateTime{} = right),
    do:
      if(left.time.zone == right.time.zone,
        do:
          Date.compare(left.date, right.date) == :eq and
            feel_equal(left.time, right.time) == true,
        else: FeelDateTime.compare(left, right) == :eq
      )

  defp feel_equal(%Duration{} = left, %Duration{} = right),
    do:
      if(left.kind == right.kind,
        do: left.months == right.months and feel_equal(left.seconds, right.seconds) == true,
        else: nil
      )

  defp feel_equal(%Range{} = left, %Range{} = right) do
    left.start_inclusive == right.start_inclusive and
      left.end_inclusive == right.end_inclusive and
      feel_equal(left.start, right.start) == true and
      feel_equal(left.end, right.end) == true
  end

  defp feel_equal(
         {:unary_test_value, left_operator, left_operand},
         {:unary_test_value, right_operator, right_operand}
       ) do
    left_operator == right_operator and feel_equal(left_operand, right_operand) == true
  end

  defp feel_equal({:unary_test_value, _operator, _operand}, %Range{}), do: false
  defp feel_equal(%Range{}, {:unary_test_value, _operator, _operand}), do: false

  defp feel_equal(left, right) when is_list(left) and is_list(right) do
    if length(left) == length(right) do
      left |> Enum.zip(right) |> Enum.map(fn {l, r} -> feel_equal(l, r) end) |> equality_all()
    else
      false
    end
  end

  defp feel_equal(left, right)
       when is_map(left) and is_map(right) and not is_struct(left) and not is_struct(right) do
    if Map.keys(left) |> Enum.sort() == Map.keys(right) |> Enum.sort() do
      left
      |> Enum.map(fn {key, value} -> feel_equal(value, Map.fetch!(right, key)) end)
      |> equality_all()
    else
      false
    end
  end

  defp feel_equal(_left, _right), do: nil

  defp equality_all(results) do
    cond do
      Enum.any?(results, &(&1 == false)) -> false
      Enum.any?(results, &is_nil/1) -> nil
      true -> true
    end
  end

  defp comparator_unary_test?(expression) do
    Regex.match?(~r/^(<=|>=|<|>|!=|=)\s*.+$/, expression)
  end

  defp range_unary_test?(expression) do
    String.starts_with?(expression, "[") or String.starts_with?(expression, "(")
  end

  defp eval_comparator_unary_test(expression, value, context) do
    %{"op" => op, "rhs" => rhs} =
      Regex.named_captures(~r/^(?<op><=|>=|<|>|!=|=)\s*(?<rhs>.+)$/, expression)

    with {:ok, rhs_value} <- Boxic.FEEL.evaluate(rhs, context) do
      case compare_for_unary_test(op, value, rhs_value) do
        {:ok, result} -> {:ok, result}
        {:error, %Error{} = e} -> {:error, e}
      end
    end
  end

  defp compare_for_unary_test(_op, nil, _rhs), do: {:ok, false}
  defp compare_for_unary_test(_op, _lhs, nil), do: {:ok, false}

  defp compare_for_unary_test(op, %Decimal{} = lhs, %Decimal{} = rhs) do
    cmp = decimal_compare(lhs, rhs)

    result =
      case op do
        ">" -> cmp == :gt
        ">=" -> cmp in [:gt, :eq]
        "<" -> cmp == :lt
        "<=" -> cmp in [:lt, :eq]
        "=" -> cmp == :eq
        "!=" -> cmp != :eq
      end

    {:ok, result}
  end

  defp compare_for_unary_test(op, %Date{} = lhs, %Date{} = rhs)
       when op in [">", ">=", "<", "<=", "=", "!="] do
    unary_compare_result(op, Date.compare(lhs, rhs))
  end

  defp compare_for_unary_test(op, %Time{} = lhs, %Time{} = rhs)
       when op in [">", ">=", "<", "<=", "=", "!="] do
    unary_compare_result(op, Time.compare(lhs, rhs))
  end

  defp compare_for_unary_test(op, %DateTime{} = lhs, %DateTime{} = rhs)
       when op in [">", ">=", "<", "<=", "=", "!="] do
    unary_compare_result(op, DateTime.compare(lhs, rhs))
  end

  defp compare_for_unary_test(op, %FeelTime{} = lhs, %FeelTime{} = rhs)
       when op in [">", ">=", "<", "<=", "=", "!="] do
    unary_compare_result(op, FeelTime.compare(lhs, rhs))
  end

  defp compare_for_unary_test(op, %FeelDateTime{} = lhs, %FeelDateTime{} = rhs)
       when op in [">", ">=", "<", "<=", "=", "!="] do
    unary_compare_result(op, FeelDateTime.compare(lhs, rhs))
  end

  defp compare_for_unary_test(op, %Duration{} = lhs, %Duration{} = rhs)
       when op in [">", ">=", "<", "<=", "=", "!="] do
    case Duration.compare(lhs, rhs) do
      :unordered -> {:ok, nil}
      comparison -> unary_compare_result(op, comparison)
    end
  end

  defp compare_for_unary_test(op, lhs, rhs)
       when is_binary(lhs) and is_binary(rhs) and op in [">", ">=", "<", "<=", "=", "!="] do
    unary_compare_result(op, compare_strings(lhs, rhs))
  end

  defp compare_for_unary_test(op, lhs, rhs) when op in ["=", "!="] do
    eq = Semantics.equal?(lhs, rhs)
    {:ok, if(op == "=", do: eq, else: not eq)}
  end

  defp compare_for_unary_test(_op, _lhs, _rhs),
    do: {:error, error(:type_error, "unary test comparison requires compatible values")}

  defp unary_compare_result(op, cmp) do
    result =
      case op do
        ">" -> cmp == :gt
        ">=" -> cmp in [:gt, :eq]
        "<" -> cmp == :lt
        "<=" -> cmp in [:lt, :eq]
        "=" -> cmp == :eq
        "!=" -> cmp != :eq
      end

    {:ok, result}
  end

  defp range_contains?(%Range{}, nil), do: nil
  defp range_contains?(%Range{start: nil}, _value), do: nil
  defp range_contains?(%Range{end: nil}, _value), do: nil

  defp range_contains?(%Range{} = range, value) do
    lower_ok = range_lower_ok?(range, value)
    upper_ok = range_upper_ok?(range, value)
    lower_ok and upper_ok
  end

  defp evaluate_in(value, {:unary_test, operator, operand_ast}, context) do
    with {:ok, operand} <- eval(operand_ast, context) do
      compare_for_unary_test(unary_operator(operator), value, operand)
    end
  end

  defp evaluate_in(value, {:unary_tests, tests}, context) do
    tests
    |> Enum.reduce_while({:ok, []}, fn test, {:ok, results} ->
      case evaluate_in(value, test, context) do
        {:ok, true} -> {:halt, {:ok, true}}
        {:ok, result} -> {:cont, {:ok, [result | results]}}
        {:error, %Error{} = error} -> {:halt, {:error, error}}
      end
    end)
    |> case do
      {:ok, true} -> {:ok, true}
      {:ok, results} -> {:ok, equality_any(results)}
      {:error, %Error{} = error} -> {:error, error}
    end
  end

  defp evaluate_in(value, tests_ast, context) do
    with {:ok, tests} <- eval(tests_ast, context) do
      {:ok, membership_result(value, tests)}
    end
  end

  defp membership_result(value, tests) when is_list(tests) do
    tests
    |> Enum.map(&membership_candidate(value, &1))
    |> equality_any()
  end

  defp membership_result(value, test), do: membership_candidate(value, test)

  defp membership_candidate(value, %Range{} = range), do: range_contains?(range, value)
  defp membership_candidate(value, test), do: feel_equal(value, test)

  defp equality_any(results) do
    cond do
      Enum.any?(results, &(&1 == true)) -> true
      Enum.any?(results, &(&1 == false)) -> false
      true -> nil
    end
  end

  defp unary_operator(:eq), do: "="
  defp unary_operator(:neq), do: "!="
  defp unary_operator(:lt), do: "<"
  defp unary_operator(:lte), do: "<="
  defp unary_operator(:gt), do: ">"
  defp unary_operator(:gte), do: ">="

  defp range_lower_ok?(%Range{start: start, start_inclusive: inclusive}, value) do
    case compare_for_bounds(value, start) do
      :gt -> true
      :eq -> inclusive
      _ -> false
    end
  end

  defp range_upper_ok?(%Range{end: finish, end_inclusive: inclusive}, value) do
    case compare_for_bounds(value, finish) do
      :lt -> true
      :eq -> inclusive
      _ -> false
    end
  end

  defp compare_for_bounds(%Decimal{} = left, %Decimal{} = right), do: decimal_compare(left, right)
  defp compare_for_bounds(%Date{} = left, %Date{} = right), do: Date.compare(left, right)
  defp compare_for_bounds(%Time{} = left, %Time{} = right), do: Time.compare(left, right)

  defp compare_for_bounds(%DateTime{} = left, %DateTime{} = right),
    do: DateTime.compare(left, right)

  defp compare_for_bounds(%FeelTime{} = left, %FeelTime{} = right),
    do: FeelTime.compare(left, right)

  defp compare_for_bounds(%FeelDateTime{} = left, %FeelDateTime{} = right),
    do: FeelDateTime.compare(left, right)

  defp compare_for_bounds(%Duration{} = left, %Duration{} = right),
    do: Duration.compare(left, right)

  defp compare_for_bounds(left, right) do
    cond do
      left == right -> :eq
      left < right -> :lt
      true -> :gt
    end
  rescue
    _ -> :not_comparable
  end

  defp feel_not(nil), do: nil
  defp feel_not(true), do: false
  defp feel_not(false), do: true
  defp feel_not(_), do: nil

  defp feel_and(false, _), do: false
  defp feel_and(_, false), do: false
  defp feel_and(nil, _), do: nil
  defp feel_and(_, nil), do: nil
  defp feel_and(true, true), do: true
  defp feel_and(_, _), do: nil

  defp feel_or(true, _), do: true
  defp feel_or(_, true), do: true
  defp feel_or(nil, _), do: nil
  defp feel_or(_, nil), do: nil
  defp feel_or(false, false), do: false
  defp feel_or(_, _), do: nil

  defp error(code, message), do: %Error{code: code, message: message}

  defp decimal_new(value), do: apply(Decimal, :new, [value])
  defp decimal_add(left, right), do: apply(Decimal, :add, [left, right])
  defp decimal_sub(left, right), do: apply(Decimal, :sub, [left, right])
  defp decimal_mult(left, right), do: apply(Decimal, :mult, [left, right])
  defp decimal_div(left, right), do: apply(Decimal, :div, [left, right])
  defp decimal_negate(value), do: apply(Decimal, :negate, [value])
  defp decimal_equal?(left, right), do: apply(Decimal, :equal?, [left, right])
  defp decimal_compare(left, right), do: apply(Decimal, :compare, [left, right])
end
