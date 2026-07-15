defmodule Arbiter.FEEL.Builtins do
  @moduledoc """
  FEEL built-in function registry and invocation.
  """

  alias Arbiter.FEEL.Duration

  @builtins ~w(
    string_length
    upper_case
    lower_case
    substring
    count
    sum
    min
    max
    append
    abs
    round
    floor
    ceiling
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
    case {name, args} do
      {"string_length", [value]} when is_binary(value) ->
        {:ok, Decimal.new(String.length(value))}

      {"upper_case", [value]} when is_binary(value) ->
        {:ok, String.upcase(value)}

      {"lower_case", [value]} when is_binary(value) ->
        {:ok, String.downcase(value)}

      {"substring", [value, %Decimal{} = start]} when is_binary(value) ->
        index = Decimal.to_integer(start) - 1
        {:ok, String.slice(value, max(index, 0), String.length(value))}

      {"substring", [value, %Decimal{} = start, %Decimal{} = len]} when is_binary(value) ->
        index = Decimal.to_integer(start) - 1
        {:ok, String.slice(value, max(index, 0), Decimal.to_integer(len))}

      {"count", [list]} when is_list(list) ->
        {:ok, Decimal.new(length(list))}

      {"sum", [list]} when is_list(list) ->
        sum_list(list)

      {"min", [list]} when is_list(list) ->
        min_list(list)

      {"max", [list]} when is_list(list) ->
        max_list(list)

      {"append", [list, value]} when is_list(list) ->
        {:ok, list ++ [value]}

      {"abs", [%Decimal{} = value]} ->
        {:ok, Decimal.abs(value)}

      {"round", [%Decimal{} = value]} ->
        {:ok, Decimal.round(value)}

      {"floor", [%Decimal{} = value]} ->
        {:ok, Decimal.round(value, 0, :floor)}

      {"ceiling", [%Decimal{} = value]} ->
        {:ok, Decimal.round(value, 0, :ceiling)}

      {"number", [value]} when is_binary(value) ->
        {:ok, Decimal.new(value)}

      {"number", [%Decimal{} = value]} ->
        {:ok, value}

      {"date", [value]} when is_binary(value) ->
        case Date.from_iso8601(value) do
          {:ok, date} -> {:ok, date}
          _ -> {:error, err(:evaluation_error, "invalid date literal")}
        end

      {"time", [value]} when is_binary(value) ->
        case Time.from_iso8601(value) do
          {:ok, time} -> {:ok, time}
          _ -> {:error, err(:evaluation_error, "invalid time literal")}
        end

      {"date_time", [value]} when is_binary(value) ->
        parse_date_time(value)

      {"duration", [value]} when is_binary(value) ->
        case Duration.parse_iso8601(value) do
          {:ok, duration} -> {:ok, duration}
          _ -> {:error, err(:evaluation_error, "invalid duration literal")}
        end

      _ ->
        {:error, err(:arity_error, "invalid built-in invocation: #{name}/#{length(args)}")}
    end
  rescue
    _ -> {:error, err(:evaluation_error, "built-in invocation failed")}
  end

  defp parse_date_time(value) do
    case DateTime.from_iso8601(value) do
      {:ok, datetime, _offset} ->
        {:ok, datetime}

      _ ->
        case NaiveDateTime.from_iso8601(value) do
          {:ok, naive} -> DateTime.from_naive(naive, "Etc/UTC")
          _ -> {:error, err(:evaluation_error, "invalid date_time literal")}
        end
    end
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
      true -> {:ok, Enum.min_by(values, &Decimal.to_float/1)}
      false -> {:error, err(:type_error, "min expects a list of numbers")}
    end
  end

  defp max_list([]), do: {:ok, nil}

  defp max_list(values) do
    case Enum.all?(values, &match?(%Decimal{}, &1)) do
      true -> {:ok, Enum.max_by(values, &Decimal.to_float/1)}
      false -> {:error, err(:type_error, "max expects a list of numbers")}
    end
  end

  defp err(code, message), do: %Arbiter.FEEL.Error{code: code, message: message}
end
