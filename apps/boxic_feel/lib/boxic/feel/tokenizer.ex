defmodule Boxic.FEEL.Tokenizer do
  @moduledoc false
  alias Boxic.FEEL.{Duration, Error}
  alias Boxic.FEEL.DateTime, as: FeelDateTime
  alias Boxic.FEEL.Time, as: FeelTime

  def tokenize(expression), do: tokenize(expression, [])

  defp tokenize(<<>>, acc), do: {:ok, Enum.reverse(acc)}

  defp tokenize(<<"/*", rest::binary>>, acc) do
    case :binary.split(rest, "*/") do
      [_comment, remaining] -> tokenize(remaining, acc)
      _ -> {:error, error(:invalid_syntax, "unterminated block comment")}
    end
  end

  defp tokenize(<<"//", rest::binary>>, acc) do
    case :binary.split(rest, "\n") do
      [_comment, remaining] -> tokenize(remaining, acc)
      [_comment] -> tokenize("", acc)
    end
  end

  defp tokenize(<<char::utf8, rest::binary>>, acc) when char in [?\n, ?\s, ?\t, ?\r] do
    tokenize(rest, acc)
  end

  defp tokenize(<<"\"", rest::binary>>, acc) do
    case take_string(rest, "") do
      {:ok, value, remaining} -> tokenize(remaining, [{:string, value} | acc])
      :error -> {:error, error(:invalid_syntax, "unterminated string literal")}
    end
  end

  defp tokenize(<<"@\"", rest::binary>>, acc) do
    case take_string(rest, "") do
      {:ok, value, remaining} ->
        case parse_at_literal(value) do
          {:ok, temporal} -> tokenize(remaining, [{:literal, temporal} | acc])
          :error -> {:error, error(:invalid_syntax, "invalid at-literal")}
        end

      :error ->
        {:error, error(:invalid_syntax, "unterminated at-literal")}
    end
  end

  defp tokenize(<<"substring before", rest::binary>>, acc),
    do: tokenize(rest, [{:identifier, "substring_before"} | acc])

  defp tokenize(<<"substring after", rest::binary>>, acc),
    do: tokenize(rest, [{:identifier, "substring_after"} | acc])

  defp tokenize(<<"string length", rest::binary>>, acc),
    do: tokenize(rest, [{:identifier, "string_length"} | acc])

  defp tokenize(<<"string join", rest::binary>>, acc),
    do: tokenize(rest, [{:identifier, "string_join"} | acc])

  defp tokenize(<<"get value", rest::binary>>, acc),
    do: tokenize(rest, [{:identifier, "get_value"} | acc])

  defp tokenize(<<"get entries", rest::binary>>, acc),
    do: tokenize(rest, [{:identifier, "get_entries"} | acc])

  defp tokenize(<<"context put", rest::binary>>, acc),
    do: tokenize(rest, [{:identifier, "context_put"} | acc])

  defp tokenize(<<"context merge", rest::binary>>, acc),
    do: tokenize(rest, [{:identifier, "context_merge"} | acc])

  defp tokenize(<<"day of year", rest::binary>>, acc),
    do: tokenize(rest, [{:identifier, "day_of_year"} | acc])

  defp tokenize(<<"day of week", rest::binary>>, acc),
    do: tokenize(rest, [{:identifier, "day_of_week"} | acc])

  defp tokenize(<<"month of year", rest::binary>>, acc),
    do: tokenize(rest, [{:identifier, "month_of_year"} | acc])

  defp tokenize(<<"week of year", rest::binary>>, acc),
    do: tokenize(rest, [{:identifier, "week_of_year"} | acc])

  defp tokenize(<<"years and months duration", rest::binary>>, acc),
    do: tokenize(rest, [{:identifier, "years_and_months_duration"} | acc])

  defp tokenize(<<"overlaps before", rest::binary>>, acc),
    do: tokenize(rest, [{:identifier, "overlaps_before"} | acc])

  defp tokenize(<<"overlaps after", rest::binary>>, acc),
    do: tokenize(rest, [{:identifier, "overlaps_after"} | acc])

  defp tokenize(<<"finished by", rest::binary>>, acc),
    do: tokenize(rest, [{:identifier, "finished_by"} | acc])

  defp tokenize(<<"started by", rest::binary>>, acc),
    do: tokenize(rest, [{:identifier, "started_by"} | acc])

  defp tokenize(<<"met by", rest::binary>>, acc),
    do: tokenize(rest, [{:identifier, "met_by"} | acc])

  defp tokenize(<<"ends with", rest::binary>>, acc),
    do: tokenize(rest, [{:identifier, "ends_with"} | acc])

  defp tokenize(<<"starts with", rest::binary>>, acc),
    do: tokenize(rest, [{:identifier, "starts_with"} | acc])

  defp tokenize(<<"upper case", rest::binary>>, acc),
    do: tokenize(rest, [{:identifier, "upper_case"} | acc])

  defp tokenize(<<"lower case", rest::binary>>, acc),
    do: tokenize(rest, [{:identifier, "lower_case"} | acc])

  defp tokenize(<<"round half up", rest::binary>>, acc),
    do: tokenize(rest, [{:identifier, "round_half_up"} | acc])

  defp tokenize(<<"round half down", rest::binary>>, acc),
    do: tokenize(rest, [{:identifier, "round_half_down"} | acc])

  defp tokenize(<<"round up", rest::binary>>, acc),
    do: tokenize(rest, [{:identifier, "round_up"} | acc])

  defp tokenize(<<"round down", rest::binary>>, acc),
    do: tokenize(rest, [{:identifier, "round_down"} | acc])

  defp tokenize(<<"list contains", rest::binary>>, acc),
    do: tokenize(rest, [{:identifier, "list_contains"} | acc])

  defp tokenize(<<"list replace", rest::binary>>, acc),
    do: tokenize(rest, [{:identifier, "list_replace"} | acc])

  defp tokenize(<<"insert before", rest::binary>>, acc),
    do: tokenize(rest, [{:identifier, "insert_before"} | acc])

  defp tokenize(<<"index of", rest::binary>>, acc),
    do: tokenize(rest, [{:identifier, "index_of"} | acc])

  defp tokenize(<<"distinct values", rest::binary>>, acc),
    do: tokenize(rest, [{:identifier, "distinct_values"} | acc])

  defp tokenize(<<"new item", rest::binary>>, acc),
    do: tokenize(rest, [{:identifier, "new_item"} | acc])

  defp tokenize(<<"start position", rest::binary>>, acc),
    do: tokenize(rest, [{:identifier, "start_position"} | acc])

  defp tokenize(<<"grouping separator", rest::binary>>, acc),
    do: tokenize(rest, [{:identifier, "grouping_separator"} | acc])

  defp tokenize(<<"decimal separator", rest::binary>>, acc),
    do: tokenize(rest, [{:identifier, "decimal_separator"} | acc])

  defp tokenize(<<"time offset", rest::binary>>, acc),
    do: tokenize(rest, [{:identifier, "time offset"} | acc])

  defp tokenize(<<"start included", rest::binary>>, acc),
    do: tokenize(rest, [{:identifier, "start included"} | acc])

  defp tokenize(<<"end included", rest::binary>>, acc),
    do: tokenize(rest, [{:identifier, "end included"} | acc])

  defp tokenize(<<"date and time", rest::binary>>, acc),
    do: tokenize(rest, [{:identifier, "date_time"} | acc])

  defp tokenize(<<"..", rest::binary>>, acc), do: tokenize(rest, [:range_dots | acc])

  defp tokenize(<<".", digit::utf8, _rest::binary>> = input, acc)
       when digit >= ?0 and digit <= ?9 do
    {number, remaining} = take_number(input)
    tokenize(remaining, [{:number, decimal_new(number)} | acc])
  end

  defp tokenize(<<".", rest::binary>>, acc), do: tokenize(rest, [:dot | acc])
  defp tokenize(<<"(", rest::binary>>, acc), do: tokenize(rest, [:lparen | acc])
  defp tokenize(<<")", rest::binary>>, acc), do: tokenize(rest, [:rparen | acc])
  defp tokenize(<<"[", rest::binary>>, acc), do: tokenize(rest, [:lbracket | acc])
  defp tokenize(<<"]", rest::binary>>, acc), do: tokenize(rest, [:rbracket | acc])
  defp tokenize(<<"{", rest::binary>>, acc), do: tokenize(rest, [:lbrace | acc])
  defp tokenize(<<"}", rest::binary>>, acc), do: tokenize(rest, [:rbrace | acc])
  defp tokenize(<<",", rest::binary>>, acc), do: tokenize(rest, [:comma | acc])
  defp tokenize(<<":", rest::binary>>, acc), do: tokenize(rest, [:colon | acc])
  defp tokenize(<<"+", rest::binary>>, acc), do: tokenize(rest, [:plus | acc])
  defp tokenize(<<"-", rest::binary>>, acc), do: tokenize(rest, [:minus | acc])
  defp tokenize(<<"**", rest::binary>>, acc), do: tokenize(rest, [:pow | acc])
  defp tokenize(<<"*", rest::binary>>, acc), do: tokenize(rest, [:mul | acc])
  defp tokenize(<<"/", rest::binary>>, acc), do: tokenize(rest, [:div | acc])
  defp tokenize(<<">=", rest::binary>>, acc), do: tokenize(rest, [:gte | acc])
  defp tokenize(<<"<=", rest::binary>>, acc), do: tokenize(rest, [:lte | acc])
  defp tokenize(<<"!=", rest::binary>>, acc), do: tokenize(rest, [:neq | acc])
  defp tokenize(<<">", rest::binary>>, acc), do: tokenize(rest, [:gt | acc])
  defp tokenize(<<"<", rest::binary>>, acc), do: tokenize(rest, [:lt | acc])
  defp tokenize(<<"=", rest::binary>>, acc), do: tokenize(rest, [:eq | acc])

  defp tokenize(<<char::utf8, _rest::binary>> = input, acc)
       when char in [?0, ?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9] do
    {number, remaining} = take_number(input)
    tokenize(remaining, [{:number, decimal_new(number)} | acc])
  end

  defp tokenize(<<char::utf8, _rest::binary>> = input, acc)
       when (char >= ?a and char <= ?z) or (char >= ?A and char <= ?Z) or char == ?_ do
    {word, remaining} = take_while(input, &identifier_char?/1)
    {word, remaining} = consume_spaced_identifier(word, remaining)

    token =
      case word do
        "true" -> {:boolean, true}
        "false" -> {:boolean, false}
        "null" -> {:null, nil}
        "and" -> :and
        "or" -> :or
        "not" -> :not
        "for" -> :for
        "in" -> :in
        "between" -> :between
        "instance" -> :instance
        "of" -> :of
        "return" -> :return
        "some" -> :some
        "every" -> :every
        "satisfies" -> :satisfies
        "function" -> :function
        "if" -> :if
        "then" -> :then
        "else" -> :else
        _ -> {:identifier, word}
      end

    tokenize(remaining, [token | acc])
  end

  defp tokenize(<<char::utf8, _rest::binary>> = input, acc) when char > 127 do
    {word, remaining} = take_while(input, &identifier_char?/1)
    tokenize(remaining, [{:identifier, word} | acc])
  end

  defp tokenize(_input, _acc), do: {:error, error(:invalid_syntax, "invalid token")}

  defp consume_spaced_identifier("date", remaining) do
    case Regex.run(~r/^\s+and\s+time/, remaining, return: :index) do
      [{0, length}] ->
        {"date_time", binary_part(remaining, length, byte_size(remaining) - length)}

      _ ->
        {"date", remaining}
    end
  end

  defp consume_spaced_identifier(word, remaining), do: {word, remaining}

  defp parse_at_literal(value) do
    cond do
      String.starts_with?(value, "P") or String.starts_with?(value, "-P") ->
        Duration.parse_iso8601(value)

      Regex.match?(~r/^-?\d{4,9}-\d{2}-\d{2}T/, value) ->
        FeelDateTime.parse(value)

      String.contains?(value, ":") ->
        FeelTime.parse(value)

      true ->
        parse_at_date(value)
    end
  end

  defp parse_at_date(value) do
    case Regex.run(~r/^(-?(?:\d{4}|[1-9]\d{4,8}))-(\d{2})-(\d{2})$/, value,
           capture: :all_but_first
         ) do
      [year, month, day] ->
        Date.new(String.to_integer(year), String.to_integer(month), String.to_integer(day))

      _ ->
        :error
    end
  end

  defp identifier_char?(char) do
    (char >= ?a and char <= ?z) or
      (char >= ?A and char <= ?Z) or
      (char >= ?0 and char <= ?9) or
      char == ?_ or char > 127
  end

  defp take_string(<<"\"", rest::binary>>, acc), do: {:ok, acc, rest}

  defp take_string(<<"\\\"", rest::binary>>, acc), do: take_string(rest, acc <> "\"")
  defp take_string(<<"\\\\", rest::binary>>, acc), do: take_string(rest, acc <> "\\")
  defp take_string(<<"\\n", rest::binary>>, acc), do: take_string(rest, acc <> "\n")
  defp take_string(<<"\\r", rest::binary>>, acc), do: take_string(rest, acc <> "\r")
  defp take_string(<<"\\t", rest::binary>>, acc), do: take_string(rest, acc <> "\t")

  defp take_string(<<"\\u", hex::binary-size(4), rest::binary>>, acc) do
    with {codepoint, ""} <- Integer.parse(hex, 16) do
      case {codepoint, rest} do
        {high, <<"\\u", low_hex::binary-size(4), remaining::binary>>}
        when high in 0xD800..0xDBFF ->
          with {low, ""} when low in 0xDC00..0xDFFF <- Integer.parse(low_hex, 16) do
            combined = 0x10000 + (high - 0xD800) * 0x400 + low - 0xDC00
            take_string(remaining, acc <> <<combined::utf8>>)
          else
            _ -> :error
          end

        {value, _} when value in 0xD800..0xDFFF ->
          :error

        {value, _} ->
          take_string(rest, acc <> <<value::utf8>>)
      end
    else
      _ -> :error
    end
  end

  defp take_string(<<"\\U", hex::binary-size(6), rest::binary>>, acc) do
    with {codepoint, ""} when codepoint <= 0x10FFFF <- Integer.parse(hex, 16) do
      take_string(rest, acc <> <<codepoint::utf8>>)
    else
      _ -> :error
    end
  end

  defp take_string(<<"\\", char::utf8, rest::binary>>, acc),
    do: take_string(rest, acc <> "\\" <> <<char::utf8>>)

  defp take_string(<<char::utf8, rest::binary>>, acc),
    do: take_string(rest, acc <> <<char::utf8>>)

  defp take_string(<<>>, _acc), do: :error

  defp take_while(binary, predicate), do: take_while(binary, predicate, "")

  defp take_number(binary) do
    case Regex.run(~r/^(?:\d+(?:\.\d+)?|\.\d+)(?:[eE][+-]?\d+)?/, binary) do
      [number] ->
        rest = String.slice(binary, String.length(number)..-1//1) || ""
        {number, rest}

      _ ->
        {"0", binary}
    end
  end

  defp take_while(<<char::utf8, rest::binary>>, predicate, acc) do
    if predicate.(char) do
      take_while(rest, predicate, acc <> <<char::utf8>>)
    else
      {acc, <<char::utf8, rest::binary>>}
    end
  end

  defp take_while(<<>>, _predicate, acc), do: {acc, ""}

  defp error(code, message), do: %Error{code: code, message: message}
  defp decimal_new(value), do: apply(Decimal, :new, [value])
end
