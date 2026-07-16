defmodule Arbiter.FEEL.Builtins do
  @moduledoc """
  FEEL built-in function registry and invocation.
  """

  alias Arbiter.FEEL.Duration
  alias Arbiter.FEEL.DateTime, as: FeelDateTime
  alias Arbiter.FEEL.Time, as: FeelTime

  @builtins ~w(
    string_length
    upper_case
    lower_case
    substring
    substring_before
    substring_after
    contains
    ends_with
    split
    replace
    matches
    string_join
    list_contains
    count
    all
    any
    sum
    min
    max
    append
    concatenate
    insert_before
    remove
    reverse
    sort
    index_of
    union
    distinct_values
    flatten
    sublist
    abs
    sqrt
    exp
    log
    even
    odd
    modulo
    product
    median
    mode
    stddev
    round
    floor
    ceiling
    decimal
    round_up
    round_down
    round_half_up
    round_half_down
    string
    number
    date
    time
    date_time
    duration
  )

  @spec resolve(String.t()) :: {:ok, {:builtin, String.t()}} | {:ok, nil}
  def resolve(name) when is_binary(name) do
    if name in @builtins do
      {:ok, {:builtin, name}}
    else
      {:ok, nil}
    end
  end

  @spec invoke(String.t(), [term()]) :: {:ok, term()} | {:error, Arbiter.FEEL.Error.t()}
  def invoke(name, args) do
    with {:ok, normalized_args} <- normalize_args(name, args) do
      invoke_normalized(name, normalized_args)
    end
  rescue
    _ -> {:error, err(:evaluation_error, "built-in invocation failed")}
  end

  defp invoke_normalized(name, args) do
    case {name, args} do
      {"string_length", [value]} when is_binary(value) ->
        {:ok, Decimal.new(String.length(value))}

      {"upper_case", [value]} when is_binary(value) ->
        {:ok, String.upcase(value)}

      {"lower_case", [value]} when is_binary(value) ->
        {:ok, String.downcase(value)}

      {"substring", [value, %Decimal{} = start]} when is_binary(value) ->
        {:ok, substring(value, start, nil)}

      {"substring", [value, %Decimal{} = start, %Decimal{} = len]} when is_binary(value) ->
        {:ok, substring(value, start, len)}

      {"substring_before", [value, match]} when is_binary(value) and is_binary(match) ->
        {:ok, substring_before(value, match)}

      {"substring_after", [value, match]} when is_binary(value) and is_binary(match) ->
        {:ok, substring_after(value, match)}

      {"contains", [value, match]} when is_binary(value) and is_binary(match) ->
        {:ok, String.contains?(value, match)}

      {"ends_with", [value, match]} when is_binary(value) and is_binary(match) ->
        {:ok, String.ends_with?(value, match)}

      {"split", [value, delimiter]} when is_binary(value) and is_binary(delimiter) ->
        regex_split(value, delimiter)

      {"replace", [input, pattern, replacement]}
      when is_binary(input) and is_binary(pattern) and is_binary(replacement) ->
        regex_replace(input, pattern, replacement, "")

      {"replace", [input, pattern, replacement, flags]}
      when is_binary(input) and is_binary(pattern) and is_binary(replacement) and is_binary(flags) ->
        regex_replace(input, pattern, replacement, flags)

      {"matches", [input, pattern]} when is_binary(input) and is_binary(pattern) ->
        regex_matches(input, pattern, "")

      {"matches", [input, pattern, flags]}
      when is_binary(input) and is_binary(pattern) and is_binary(flags) ->
        regex_matches(input, pattern, flags)

      {"matches", [input, pattern, nil]} when is_binary(input) and is_binary(pattern) ->
        regex_matches(input, pattern, "")

      {"string_join", [list]} when is_list(list) ->
        string_join(list, "")

      {"string_join", [list, delimiter]} when is_list(list) and is_binary(delimiter) ->
        string_join(list, delimiter)

      {"string_join", [list, nil]} when is_list(list) ->
        string_join(list, "")

      {"string_join", [value]} when is_binary(value) ->
        {:ok, value}

      {"string_join", [value, delimiter]} when is_binary(value) and is_binary(delimiter) ->
        {:ok, value}

      {"count", [list]} when is_list(list) ->
        {:ok, Decimal.new(length(list))}

      {"all", [list]} when is_list(list) ->
        boolean_aggregate(list, :all)

      {"all", values} when values != [] ->
        boolean_aggregate(values, :all)

      {"any", [list]} when is_list(list) ->
        boolean_aggregate(list, :any)

      {"any", values} when values != [] ->
        boolean_aggregate(values, :any)

      {"list_contains", [list, element]} when is_list(list) ->
        {:ok, Enum.any?(list, &feel_equal?(&1, element))}

      {"sum", [list]} when is_list(list) ->
        sum_list(list)

      {"min", [list]} when is_list(list) ->
        min_list(list)

      {"max", [list]} when is_list(list) ->
        max_list(list)

      {"append", [list | values]} when is_list(list) and values != [] ->
        {:ok, list ++ values}

      {"concatenate", lists} when lists != [] ->
        if Enum.all?(lists, &is_list/1),
          do: {:ok, Enum.concat(lists)},
          else: {:error, err(:evaluation_error, "concatenate expects lists")}

      {"insert_before", [list, %Decimal{} = position, value]} when is_list(list) ->
        insert_before(list, position, value)

      {"remove", [list, %Decimal{} = position]} when is_list(list) ->
        remove_at(list, position)

      {"reverse", [list]} when is_list(list) ->
        {:ok, Enum.reverse(list)}

      {"index_of", [list, match]} when is_list(list) ->
        indexes =
          list
          |> Enum.with_index(1)
          |> Enum.filter(fn {value, _index} -> feel_equal?(value, match) end)
          |> Enum.map(fn {_value, index} -> Decimal.new(index) end)

        {:ok, indexes}

      {"union", lists} when lists != [] ->
        if Enum.all?(lists, &is_list/1),
          do: {:ok, lists |> Enum.concat() |> distinct()},
          else: {:error, err(:evaluation_error, "union expects lists")}

      {"distinct_values", [list]} when is_list(list) ->
        {:ok, distinct(list)}

      {"flatten", [list]} when is_list(list) ->
        {:ok, flatten(list)}

      {"sublist", [list, %Decimal{} = start]} when is_list(list) ->
        sublist(list, start, nil)

      {"sublist", [list, %Decimal{} = start, %Decimal{} = length]} when is_list(list) ->
        sublist(list, start, length)

      {"abs", [%Decimal{} = value]} ->
        {:ok, Decimal.abs(value)}

      {"sqrt", [%Decimal{} = value]} ->
        decimal_sqrt(value)

      {"exp", [%Decimal{} = value]} ->
        decimal_float_function(value, &:math.exp/1, 8)

      {"log", [%Decimal{} = value]} ->
        if Decimal.compare(value, Decimal.new(0)) == :gt,
          do: decimal_float_function(value, &:math.log/1, 8),
          else: {:ok, nil}

      {"even", [%Decimal{} = value]} ->
        {:ok, Decimal.equal?(Decimal.rem(value, Decimal.new(2)), Decimal.new(0))}

      {"odd", [%Decimal{} = value]} ->
        {:ok, not Decimal.equal?(Decimal.rem(value, Decimal.new(2)), Decimal.new(0))}

      {name, [nil]} when name in ["sqrt", "exp", "log", "even", "odd", "product"] ->
        {:ok, nil}

      {"modulo", [nil, _]} ->
        {:ok, nil}

      {"modulo", [_, nil]} ->
        {:ok, nil}

      {"modulo", [%Decimal{} = dividend, %Decimal{} = divisor]} ->
        decimal_modulo(dividend, divisor)

      {"product", [list]} when is_list(list) ->
        product_list(list)

      {"product", values} when values != [] ->
        product_list(values)

      {"median", [list]} when is_list(list) ->
        median(list)

      {"median", values} when values != [] ->
        median(values)

      {"mode", [list]} when is_list(list) ->
        mode(list)

      {"mode", values} when values != [] ->
        mode(values)

      {"stddev", [list]} when is_list(list) ->
        stddev(list)

      {"stddev", values} when values != [] ->
        stddev(values)

      {"abs", [%Duration{} = value]} ->
        {:ok, Duration.abs(value)}

      {"round", [%Decimal{} = value]} ->
        {:ok, Decimal.round(value)}

      {"floor", [%Decimal{} = value]} ->
        {:ok, Decimal.round(value, 0, :floor)}

      {"floor", [%Decimal{} = value, %Decimal{} = scale]} ->
        round_at_scale(value, scale, :floor)

      {"ceiling", [%Decimal{} = value]} ->
        {:ok, Decimal.round(value, 0, :ceiling)}

      {"ceiling", [%Decimal{} = value, %Decimal{} = scale]} ->
        round_at_scale(value, scale, :ceiling)

      {"decimal", [%Decimal{} = value, %Decimal{} = scale]} ->
        round_at_scale(value, scale, :half_even, truncate_scale: true)

      {"round_up", [%Decimal{} = value, %Decimal{} = scale]} ->
        round_at_scale(value, scale, :up)

      {"round_down", [%Decimal{} = value, %Decimal{} = scale]} ->
        round_at_scale(value, scale, :down)

      {"round_half_up", [%Decimal{} = value, %Decimal{} = scale]} ->
        round_at_scale(value, scale, :half_up)

      {"round_half_down", [%Decimal{} = value, %Decimal{} = scale]} ->
        round_at_scale(value, scale, :half_down)

      {"string", [value]} when is_binary(value) ->
        {:ok, value}

      {"string", [%Decimal{} = value]} ->
        {:ok, Decimal.to_string(value, :normal)}

      {"string", [value]} when is_boolean(value) ->
        {:ok, Atom.to_string(value)}

      {"string", [nil]} ->
        {:ok, nil}

      {"string", [%Date{} = value]} ->
        {:ok, Date.to_iso8601(value)}

      {"string", [%FeelTime{} = value]} ->
        {:ok, FeelTime.to_string(value)}

      {"string", [%FeelDateTime{} = value]} ->
        {:ok, FeelDateTime.to_string(value)}

      {"string", [%Duration{} = value]} ->
        {:ok, Duration.to_string(value)}

      {"string", [value]} when is_list(value) ->
        {:ok, stringify_value(value)}

      {"string", [value]} when is_map(value) and not is_struct(value) ->
        {:ok, stringify_value(value)}

      {"number", [value]} when is_binary(value) ->
        {:ok, Decimal.new(value)}

      {"number", [%Decimal{} = value]} ->
        {:ok, value}

      {"number", [value, grouping_separator, decimal_separator]} when is_binary(value) ->
        parse_number(value, grouping_separator, decimal_separator)

      {"date", [value]} when is_binary(value) ->
        parse_date(value)

      {"date", [%DateTime{} = value]} ->
        {:ok, DateTime.to_date(value)}

      {"date", [%NaiveDateTime{} = value]} ->
        {:ok, NaiveDateTime.to_date(value)}

      {"date", [%Date{} = value]} ->
        {:ok, value}

      {"date", [%FeelDateTime{} = value]} ->
        {:ok, value.date}

      {"date", [%Decimal{} = year, %Decimal{} = month, %Decimal{} = day]} ->
        new_date(year, month, day)

      {"time", [value]} when is_binary(value) ->
        parse_time(value)

      {"time", [%FeelTime{} = value]} ->
        {:ok, value}

      {"time", [%FeelDateTime{} = value]} ->
        {:ok, value.time}

      {"time", [%Time{} = value]} ->
        {:ok, FeelTime.from_elixir(value)}

      {"time", [%DateTime{} = value]} ->
        {:ok, value |> DateTime.to_time() |> FeelTime.from_elixir()}

      {"time", [%NaiveDateTime{} = value]} ->
        {:ok, value |> NaiveDateTime.to_time() |> FeelTime.from_elixir()}

      {"time", [%Date{}]} ->
        FeelTime.new(0, 0, 0, {:offset, 0})

      {"time", [%Decimal{} = hour, %Decimal{} = minute, %Decimal{} = second, offset]} ->
        new_time(hour, minute, second, offset)

      {"date_time", [value]} when is_binary(value) ->
        parse_date_time(value)

      {"date_time", [%Date{} = date, %FeelTime{} = time]} ->
        {:ok, FeelDateTime.new(date, time)}

      {"date_time", [%FeelDateTime{} = datetime, %FeelTime{} = time]} ->
        {:ok, FeelDateTime.new(datetime.date, time)}

      {"date_time", [%DateTime{} = datetime, %Time{} = time]} ->
        DateTime.new(DateTime.to_date(datetime), time, datetime.time_zone)

      {"duration", [value]} when is_binary(value) ->
        case Duration.parse_iso8601(value) do
          {:ok, duration} -> {:ok, duration}
          _ -> {:error, err(:evaluation_error, "invalid duration literal")}
        end

      _ ->
        {:error, err(:arity_error, "invalid built-in invocation: #{name}/#{length(args)}")}
    end
  end

  defp decimal_sqrt(%Decimal{} = value) do
    case Decimal.compare(value, Decimal.new(0)) do
      :lt -> {:ok, nil}
      _ -> {:ok, value |> Decimal.to_float() |> :math.sqrt() |> Decimal.from_float()}
    end
  end

  defp decimal_float_function(value, function) do
    {:ok, value |> Decimal.to_float() |> function.() |> Decimal.from_float()}
  end

  defp decimal_float_function(value, function, scale) do
    with {:ok, result} <- decimal_float_function(value, function) do
      {:ok, Decimal.round(result, scale, :half_even)}
    end
  end

  defp decimal_modulo(dividend, divisor) do
    if Decimal.equal?(divisor, Decimal.new(0)) do
      {:ok, nil}
    else
      quotient = dividend |> Decimal.div(divisor) |> Decimal.round(0, :floor)
      {:ok, Decimal.sub(dividend, Decimal.mult(divisor, quotient))}
    end
  end

  @parameters %{
    "string_length" => ["string"],
    "upper_case" => ["string"],
    "lower_case" => ["string"],
    "substring" => ["string", "start_position", "length"],
    "substring_before" => ["string", "match"],
    "substring_after" => ["string", "match"],
    "contains" => ["string", "match"],
    "ends_with" => ["string", "match"],
    "split" => ["string", "delimiter"],
    "replace" => ["input", "pattern", "replacement", "flags"],
    "matches" => ["input", "pattern", "flags"],
    "string_join" => ["list", "delimiter"],
    "list_contains" => ["list", "element"],
    "all" => ["list"],
    "any" => ["list"],
    "append" => ["list", "item"],
    "insert_before" => ["list", "position", "new_item"],
    "remove" => ["list", "position"],
    "reverse" => ["list"],
    "index_of" => ["list", "match"],
    "distinct_values" => ["list"],
    "flatten" => ["list"],
    "sublist" => ["list", "start_position", "length"],
    "floor" => ["n", "scale"],
    "ceiling" => ["n", "scale"],
    "decimal" => ["n", "scale"],
    "sqrt" => ["number"],
    "exp" => ["number"],
    "log" => ["number"],
    "even" => ["number"],
    "odd" => ["number"],
    "modulo" => ["dividend", "divisor"],
    "product" => ["list"],
    "median" => ["list"],
    "mode" => ["list"],
    "stddev" => ["list"],
    "round_up" => ["n", "scale"],
    "round_down" => ["n", "scale"],
    "round_half_up" => ["n", "scale"],
    "round_half_down" => ["n", "scale"],
    "abs" => ["n"],
    "string" => ["from"],
    "number" => ["from", "grouping_separator", "decimal_separator"],
    "duration" => ["from"],
    "date" => [["from"], ["year", "month", "day"]],
    "time" => [["from"], ["hour", "minute", "second", "offset"]],
    "date_time" => [["from"], ["date", "time"]]
  }

  defp normalize_args(name, args) do
    if Enum.any?(args, &match?({:named_arg, _, _}, &1)) do
      normalize_named_args(name, args)
    else
      {:ok, args}
    end
  end

  defp normalize_named_args(name, args) do
    signatures = Map.get(@parameters, name, [])

    signatures =
      if signatures != [] and is_binary(hd(signatures)), do: [signatures], else: signatures

    if Enum.all?(args, &match?({:named_arg, _, _}, &1)) do
      entries = Enum.map(args, fn {:named_arg, key, value} -> {key, value} end)
      names = Enum.map(entries, &elem(&1, 0))

      parameters = Enum.find(signatures, fn signature -> names -- signature == [] end)

      if parameters && length(names) == length(Enum.uniq(names)) do
        values_by_name = Map.new(entries)
        values = Enum.map(parameters, &Map.get(values_by_name, &1, :missing))

        case Enum.find_index(values, &(&1 == :missing)) do
          nil -> {:ok, values}
          index -> {:ok, Enum.take(values, index)}
        end
      else
        {:error, err(:arity_error, "invalid named arguments for #{name}")}
      end
    else
      {:error, err(:arity_error, "cannot mix positional and named arguments")}
    end
  end

  defp parse_date_time(value) do
    case FeelDateTime.parse(value) do
      {:ok, datetime} ->
        {:ok, datetime}

      :error ->
        with {:ok, date} <- parse_date_only(value),
             {:ok, time} <- FeelTime.new(0, 0, 0) do
          {:ok, FeelDateTime.new(date, time)}
        else
          _ -> {:error, err(:evaluation_error, "invalid date_time literal")}
        end
    end
  end

  defp parse_date(value) do
    case parse_date_only(value) do
      {:ok, date} ->
        {:ok, date}

      {:error, _error} ->
        with {:ok, %FeelDateTime{} = datetime} <- parse_date_time(value),
             do: {:ok, datetime.date}
    end
  end

  defp parse_date_only(value) do
    case Regex.run(~r/^(-?(?:\d{4}|[1-9]\d{4,8}))-(\d{2})-(\d{2})$/, value,
           capture: :all_but_first
         ) do
      [year, month, day] ->
        case Date.new(String.to_integer(year), String.to_integer(month), String.to_integer(day)) do
          {:ok, date} -> {:ok, date}
          _ -> {:error, err(:evaluation_error, "invalid date literal")}
        end

      _ ->
        {:error, err(:evaluation_error, "invalid date literal")}
    end
  end

  defp parse_time(value) do
    case FeelTime.parse(value) do
      {:ok, time} ->
        {:ok, time}

      :error ->
        with {:ok, %FeelDateTime{} = datetime} <- parse_date_time(value), do: {:ok, datetime.time}
    end
  end

  defp new_date(year, month, day) do
    with {:ok, year} <- decimal_integer(year),
         {:ok, month} <- decimal_integer(month),
         {:ok, day} <- decimal_integer(day),
         true <- year in -999_999_999..999_999_999,
         {:ok, date} <- Date.new(year, month, day) do
      {:ok, date}
    else
      _ -> {:error, err(:evaluation_error, "invalid date components")}
    end
  end

  defp new_time(hour, minute, second, offset) do
    with {:ok, hour} <- decimal_integer(hour),
         {:ok, minute} <- decimal_integer(minute),
         {:ok, zone} <- time_zone(offset),
         {:ok, time} <- FeelTime.new(hour, minute, second, zone) do
      {:ok, time}
    else
      _ -> {:error, err(:evaluation_error, "invalid time components")}
    end
  end

  defp time_zone(nil), do: {:ok, :floating}

  defp time_zone(%Duration{months: 0, seconds: seconds}) do
    case seconds do
      %Decimal{} ->
        case decimal_integer(seconds) do
          {:ok, value} -> {:ok, {:offset, value}}
          :error -> :error
        end

      value when is_integer(value) ->
        {:ok, {:offset, value}}
    end
  end

  defp time_zone(_value), do: :error

  defp substring_before(value, match) do
    case match do
      "" -> ""
      _ -> substring_before_match(value, match)
    end
  end

  defp substring_before_match(value, match) do
    case :binary.match(value, match) do
      {index, _length} -> binary_part(value, 0, index)
      :nomatch -> ""
    end
  end

  defp substring_after(value, match) do
    case match do
      "" -> value
      _ -> substring_after_match(value, match)
    end
  end

  defp substring_after_match(value, match) do
    case :binary.match(value, match) do
      {index, length} ->
        start = index + length
        binary_part(value, start, byte_size(value) - start)

      :nomatch ->
        ""
    end
  end

  defp substring(value, start, length) do
    start_position = decimal_truncate(start)

    index =
      if start_position > 0, do: start_position - 1, else: String.length(value) + start_position

    count = if length, do: max(decimal_truncate(length), 0), else: String.length(value)
    String.slice(value, max(index, 0), count) || ""
  end

  defp round_at_scale(value, scale, mode, opts \\ []) do
    scale = if opts[:truncate_scale], do: Decimal.round(scale, 0, :down), else: scale

    case decimal_integer(scale) do
      {:ok, integer} when integer in -6111..6176 ->
        if integer >= max(value.exp * -1, 0),
          do: {:ok, value},
          else: {:ok, Decimal.round(value, integer, mode)}

      {:ok, _integer} ->
        {:ok, nil}

      :error ->
        {:error, err(:type_error, "rounding scale must be an integer")}
    end
  end

  defp product_list([]), do: {:ok, nil}

  defp product_list(values) do
    if Enum.all?(values, &match?(%Decimal{}, &1)),
      do: {:ok, Enum.reduce(values, Decimal.new(1), &Decimal.mult/2)},
      else: {:ok, nil}
  end

  defp boolean_aggregate(values, operation) do
    if Enum.all?(values, &(&1 in [true, false, nil])) do
      result =
        case operation do
          :all ->
            cond do
              false in values -> false
              nil in values -> nil
              true -> true
            end

          :any ->
            cond do
              true in values -> true
              nil in values -> nil
              true -> false
            end
        end

      {:ok, result}
    else
      {:error, err(:type_error, "#{operation} expects boolean values")}
    end
  end

  defp median([]), do: {:ok, nil}

  defp median(values) do
    with :ok <- validate_numeric_values(values) do
      sorted = Enum.sort(values, &(Decimal.compare(&1, &2) != :gt))
      middle = div(length(sorted), 2)

      if rem(length(sorted), 2) == 1 do
        {:ok, Enum.at(sorted, middle)}
      else
        {:ok,
         sorted
         |> Enum.slice(middle - 1, 2)
         |> Enum.reduce(&Decimal.add/2)
         |> Decimal.div(Decimal.new(2))}
      end
    end
  end

  defp mode([]), do: {:ok, []}

  defp mode(values) do
    with :ok <- validate_numeric_values(values) do
      frequencies = Enum.frequencies_by(values, &Decimal.normalize/1)
      highest_frequency = frequencies |> Map.values() |> Enum.max()

      modes =
        frequencies
        |> Enum.filter(fn {_value, frequency} -> frequency == highest_frequency end)
        |> Enum.map(&elem(&1, 0))
        |> Enum.sort(&(Decimal.compare(&1, &2) != :gt))

      {:ok, modes}
    end
  end

  defp stddev(values) when length(values) < 2,
    do: {:error, err(:evaluation_error, "stddev expects at least two numbers")}

  defp stddev(values) do
    with :ok <- validate_numeric_values(values) do
      count = Decimal.new(length(values))
      mean = values |> Enum.reduce(Decimal.new(0), &Decimal.add/2) |> Decimal.div(count)

      variance =
        values
        |> Enum.reduce(Decimal.new(0), fn value, total ->
          difference = Decimal.sub(value, mean)
          Decimal.add(total, Decimal.mult(difference, difference))
        end)
        |> Decimal.div(Decimal.new(length(values) - 1))

      {:ok,
       variance
       |> Decimal.to_float()
       |> :math.sqrt()
       |> Decimal.from_float()
       |> Decimal.round(13, :half_even)}
    end
  end

  defp validate_numeric_values(values) do
    if Enum.all?(values, &match?(%Decimal{}, &1)),
      do: :ok,
      else: {:error, err(:type_error, "aggregate expects numeric values")}
  end

  defp parse_number(value, grouping_separator, decimal_separator) do
    with :ok <- validate_separator(grouping_separator),
         :ok <- validate_separator(decimal_separator),
         true <- grouping_separator != decimal_separator or is_nil(grouping_separator),
         without_grouping = remove_separator(value, grouping_separator),
         true <- valid_decimal_marker?(without_grouping, decimal_separator) do
      normalized = replace_decimal_separator(without_grouping, decimal_separator)

      case Decimal.parse(normalized) do
        {number, ""} -> {:ok, number}
        _ -> {:error, err(:evaluation_error, "invalid number literal")}
      end
    else
      false -> {:error, err(:evaluation_error, "number separators must be distinct")}
      :error -> {:error, err(:type_error, "number separators must be single characters")}
    end
  end

  defp validate_separator(nil), do: :ok

  defp validate_separator(value) when is_binary(value),
    do: if(String.length(value) == 1, do: :ok, else: :error)

  defp validate_separator(_value), do: :error

  defp remove_separator(value, nil), do: value
  defp remove_separator(value, separator), do: String.replace(value, separator, "")

  defp replace_decimal_separator(value, nil), do: value
  defp replace_decimal_separator(value, "."), do: value
  defp replace_decimal_separator(value, separator), do: String.replace(value, separator, ".")

  defp valid_decimal_marker?(_value, nil), do: true
  defp valid_decimal_marker?(_value, "."), do: true
  defp valid_decimal_marker?(value, _separator), do: not String.contains?(value, ".")

  defp decimal_truncate(value) do
    value
    |> Decimal.round(0, :down)
    |> Decimal.to_integer()
  end

  defp decimal_integer(value) do
    integer = Decimal.to_integer(value)
    if Decimal.equal?(value, Decimal.new(integer)), do: {:ok, integer}, else: :error
  rescue
    _ -> :error
  end

  defp sum_list(values) do
    case Enum.all?(values, &match?(%Decimal{}, &1)) do
      true -> {:ok, Enum.reduce(values, Decimal.new("0"), &Decimal.add/2)}
      false -> {:error, err(:type_error, "sum expects a list of numbers")}
    end
  end

  defp min_list([]), do: {:ok, nil}

  defp min_list(values) do
    case Enum.all?(values, &match?(%Decimal{}, &1)) do
      true -> {:ok, Enum.reduce(values, fn value, current -> decimal_min(value, current) end)}
      false -> {:error, err(:type_error, "min expects a list of numbers")}
    end
  end

  defp max_list([]), do: {:ok, nil}

  defp max_list(values) do
    case Enum.all?(values, &match?(%Decimal{}, &1)) do
      true -> {:ok, Enum.reduce(values, fn value, current -> decimal_max(value, current) end)}
      false -> {:error, err(:type_error, "max expects a list of numbers")}
    end
  end

  defp decimal_min(value, current) do
    if Decimal.compare(value, current) == :lt, do: value, else: current
  end

  defp decimal_max(value, current) do
    if Decimal.compare(value, current) == :gt, do: value, else: current
  end

  defp insert_before(list, position, value) do
    with {:ok, position} <- decimal_integer(position),
         true <- position != 0 and abs(position) <= length(list) + 1 do
      index = if position > 0, do: position - 1, else: length(list) + position + 1
      {:ok, List.insert_at(list, index, value)}
    else
      _ -> {:error, err(:evaluation_error, "insert position is outside the list")}
    end
  end

  defp remove_at(list, position) do
    with {:ok, position} <- decimal_integer(position),
         true <- position != 0 and abs(position) <= length(list) do
      index = if position > 0, do: position - 1, else: length(list) + position
      {:ok, List.delete_at(list, index)}
    else
      _ -> {:error, err(:evaluation_error, "remove position is outside the list")}
    end
  end

  defp sublist(list, start, requested_length) do
    with {:ok, start} <- decimal_integer(start),
         true <- start != 0,
         {:ok, count} <- sublist_length(requested_length),
         index = if(start > 0, do: start - 1, else: length(list) + start),
         true <- index >= 0 and index < length(list),
         true <- is_nil(count) or index + count <= length(list) do
      {:ok, Enum.slice(list, index, count || length(list))}
    else
      _ -> {:error, err(:evaluation_error, "invalid sublist bounds")}
    end
  end

  defp sublist_length(nil), do: {:ok, nil}

  defp sublist_length(value) do
    with {:ok, length} <- decimal_integer(value),
         true <- length >= 0,
         do: {:ok, length},
         else: (_ -> :error)
  end

  defp distinct(values) do
    Enum.reduce(values, [], fn value, result ->
      if Enum.any?(result, &feel_equal?(&1, value)), do: result, else: result ++ [value]
    end)
  end

  defp flatten(values) do
    Enum.flat_map(values, fn
      value when is_list(value) -> flatten(value)
      value -> [value]
    end)
  end

  defp feel_equal?(%Decimal{} = left, %Decimal{} = right), do: Decimal.equal?(left, right)

  defp feel_equal?(%FeelTime{} = left, %FeelTime{} = right),
    do: FeelTime.compare(left, right) == :eq

  defp feel_equal?(%FeelDateTime{} = left, %FeelDateTime{} = right),
    do: FeelDateTime.compare(left, right) == :eq

  defp feel_equal?(left, right) when is_list(left) and is_list(right) do
    length(left) == length(right) and
      Enum.zip(left, right) |> Enum.all?(fn {a, b} -> feel_equal?(a, b) end)
  end

  defp feel_equal?(left, right) when is_map(left) and is_map(right) do
    Map.keys(left) |> MapSet.new() == Map.keys(right) |> MapSet.new() and
      Enum.all?(left, fn {key, value} -> feel_equal?(value, Map.fetch!(right, key)) end)
  end

  defp feel_equal?(left, right), do: left == right

  defp string_join(values, delimiter) do
    values = Enum.reject(values, &is_nil/1)

    if Enum.all?(values, &is_binary/1),
      do: {:ok, Enum.join(values, delimiter)},
      else: {:error, err(:type_error, "string join expects strings")}
  end

  defp stringify_value(value) when is_binary(value), do: "\"#{escape_string(value)}\""
  defp stringify_value(%Decimal{} = value), do: Decimal.to_string(value, :normal)
  defp stringify_value(value) when is_boolean(value), do: Atom.to_string(value)
  defp stringify_value(nil), do: "null"

  defp stringify_value(value) when is_list(value),
    do: "[" <> Enum.map_join(value, ", ", &stringify_value/1) <> "]"

  defp stringify_value(value) when is_map(value) and not is_struct(value) do
    entries =
      value
      |> Enum.sort_by(&elem(&1, 0))
      |> Enum.map_join(", ", fn {key, item} ->
        "#{stringify_context_key(key)}: #{stringify_value(item)}"
      end)

    "{" <> entries <> "}"
  end

  defp stringify_context_key(key) do
    if Regex.match?(~r/^[\p{L}_][\p{L}\p{N}_ ]*$/u, key),
      do: key,
      else: "\"#{escape_string(key)}\""
  end

  defp escape_string(value),
    do: value |> String.replace("\\", "\\\\") |> String.replace("\"", "\\\"")

  defp regex_split(input, pattern) do
    with {:ok, regex} <- compile_regex(pattern, "") do
      {:ok, Regex.split(regex, input, trim: false)}
    end
  end

  defp regex_matches(input, pattern, flags) do
    with {:ok, pattern} <- normalize_match_pattern(pattern, flags),
         {:ok, regex} <- compile_regex(pattern, flags) do
      {:ok, Regex.match?(regex, input)}
    end
  end

  defp normalize_match_pattern(pattern, flags) do
    if Regex.match?(~r/\[[^]]*\\\d[^]]*\]/, pattern) do
      {:error, err(:evaluation_error, "invalid regular expression back-reference")}
    else
      pattern =
        pattern
        |> maybe_normalize_extended_pattern(flags)
        |> String.replace("\\p{IsBasicLatin}", "[\\x{0000}-\\x{007F}]")
        |> String.replace("[A-Z-[OI]]", "[A-HJ-NP-Z]")
        |> replace_xml_schema_dot()

      {:ok, pattern}
    end
  end

  defp maybe_normalize_extended_pattern(pattern, flags) do
    if String.contains?(flags, "x") do
      pattern
      |> String.replace("[ ]", "__FEEL_LITERAL_SPACE__")
      |> String.replace(~r/\\\s+/, "\\")
      |> String.replace(~r/\s+/, "")
      |> String.replace("__FEEL_LITERAL_SPACE__", "[ ]")
    else
      pattern
    end
  end

  defp replace_xml_schema_dot(pattern) do
    Regex.replace(~r/(?<!\\)\./, pattern, "[^\\r\\n]")
  end

  defp regex_replace(input, pattern, replacement, flags) do
    with {:ok, regex} <- compile_regex(pattern, flags) do
      replacement = Regex.replace(~r/\$(\d+)/, replacement, "\\\\g{\\1}")
      {:ok, Regex.replace(regex, input, replacement)}
    end
  end

  defp compile_regex(pattern, flags) do
    if Regex.match?(~r/^[simxq]*$/, flags) do
      pattern = if String.contains?(flags, "q"), do: Regex.escape(pattern), else: pattern
      options = String.replace(flags, "q", "") <> "u"

      case Regex.compile(pattern, options) do
        {:ok, regex} -> {:ok, regex}
        {:error, _reason} -> {:error, err(:evaluation_error, "invalid regular expression")}
      end
    else
      {:error, err(:evaluation_error, "invalid regular expression flags")}
    end
  end

  defp err(code, message), do: %Arbiter.FEEL.Error{code: code, message: message}
end
