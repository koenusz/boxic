defmodule Arbiter.FEEL do
  @moduledoc """
  FEEL entry point.

  Iteration B supports an AST-backed parser and core evaluator semantics:
  literals, arithmetic, comparisons, boolean operations, null handling, and
  name resolution from context.
  """

  alias Arbiter.FEEL.Error

  @type ast ::
          {:literal, term()}
          | {:identifier, String.t()}
          | {:unary, atom(), ast()}
          | {:binary, atom(), ast(), ast()}
  @type context :: %{optional(String.t()) => term()}

  @spec parse(String.t()) :: {:ok, ast()} | {:error, Error.t()}
  def parse(expression) when is_binary(expression) do
    trimmed = String.trim(expression)

    if trimmed == "" do
      {:error, error(:empty_expression, "expression cannot be empty")}
    else
      with {:ok, tokens} <- tokenize(trimmed),
           {:ok, ast, []} <- parse_expression(tokens) do
        {:ok, ast}
      else
        {:ok, _ast, rest} ->
          {:error, error(:invalid_syntax, "unexpected tokens: #{inspect(rest)}")}

        {:error, %Error{} = error} ->
          {:error, error}
      end
    end
  end

  @spec evaluate(String.t(), context()) :: {:ok, term()} | {:error, Error.t()}
  def evaluate(expression, context \\ %{}) when is_binary(expression) and is_map(context) do
    with {:ok, ast} <- parse(expression) do
      evaluate_ast(ast, context)
    end
  end

  @spec evaluate_ast(ast(), context()) :: {:ok, term()} | {:error, Error.t()}
  def evaluate_ast(ast, context) when is_map(context) do
    eval(ast, context)
  end

  # ---------- Tokenizer ----------

  defp tokenize(expression), do: tokenize(expression, [])

  defp tokenize(<<>>, acc), do: {:ok, Enum.reverse(acc)}

  defp tokenize(<<char::utf8, rest::binary>>, acc) when char in [?\n, ?\s, ?\t, ?\r] do
    tokenize(rest, acc)
  end

  defp tokenize(<<"\"", rest::binary>>, acc) do
    case take_string(rest, "") do
      {:ok, value, remaining} -> tokenize(remaining, [{:string, value} | acc])
      :error -> {:error, error(:invalid_syntax, "unterminated string literal")}
    end
  end

  defp tokenize(<<"(", rest::binary>>, acc), do: tokenize(rest, [:lparen | acc])
  defp tokenize(<<")", rest::binary>>, acc), do: tokenize(rest, [:rparen | acc])
  defp tokenize(<<"+", rest::binary>>, acc), do: tokenize(rest, [:plus | acc])
  defp tokenize(<<"-", rest::binary>>, acc), do: tokenize(rest, [:minus | acc])
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
    {number, remaining} = take_while(input, &(&1 in [?0, ?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?.]))
    tokenize(remaining, [{:number, decimal_new(number)} | acc])
  end

  defp tokenize(<<char::utf8, _rest::binary>> = input, acc)
       when (char >= ?a and char <= ?z) or (char >= ?A and char <= ?Z) or char == ?_ do
    {word, remaining} = take_while(input, &identifier_char?/1)

    token =
      case word do
        "true" -> {:boolean, true}
        "false" -> {:boolean, false}
        "null" -> {:null, nil}
        "and" -> :and
        "or" -> :or
        "not" -> :not
        _ -> {:identifier, word}
      end

    tokenize(remaining, [token | acc])
  end

  defp tokenize(_input, _acc), do: {:error, error(:invalid_syntax, "invalid token")}

  defp identifier_char?(char) do
    (char >= ?a and char <= ?z) or
      (char >= ?A and char <= ?Z) or
      (char >= ?0 and char <= ?9) or
      char == ?_
  end

  defp take_string(<<"\"", rest::binary>>, acc), do: {:ok, acc, rest}

  defp take_string(<<char::utf8, rest::binary>>, acc),
    do: take_string(rest, acc <> <<char::utf8>>)

  defp take_string(<<>>, _acc), do: :error

  defp take_while(binary, predicate), do: take_while(binary, predicate, "")

  defp take_while(<<char::utf8, rest::binary>>, predicate, acc) do
    if predicate.(char) do
      take_while(rest, predicate, acc <> <<char::utf8>>)
    else
      {acc, <<char::utf8, rest::binary>>}
    end
  end

  defp take_while(<<>>, _predicate, acc), do: {acc, ""}

  # ---------- Parser ----------

  defp parse_expression(tokens), do: parse_or(tokens)

  defp parse_or(tokens) do
    with {:ok, left, rest} <- parse_and(tokens) do
      parse_or_tail(left, rest)
    end
  end

  defp parse_or_tail(left, [:or | rest]) do
    with {:ok, right, rest2} <- parse_and(rest) do
      parse_or_tail({:binary, :or, left, right}, rest2)
    end
  end

  defp parse_or_tail(left, rest), do: {:ok, left, rest}

  defp parse_and(tokens) do
    with {:ok, left, rest} <- parse_equality(tokens) do
      parse_and_tail(left, rest)
    end
  end

  defp parse_and_tail(left, [:and | rest]) do
    with {:ok, right, rest2} <- parse_equality(rest) do
      parse_and_tail({:binary, :and, left, right}, rest2)
    end
  end

  defp parse_and_tail(left, rest), do: {:ok, left, rest}

  defp parse_equality(tokens) do
    with {:ok, left, rest} <- parse_comparison(tokens) do
      parse_equality_tail(left, rest)
    end
  end

  defp parse_equality_tail(left, [:eq | rest]) do
    with {:ok, right, rest2} <- parse_comparison(rest) do
      parse_equality_tail({:binary, :eq, left, right}, rest2)
    end
  end

  defp parse_equality_tail(left, [:neq | rest]) do
    with {:ok, right, rest2} <- parse_comparison(rest) do
      parse_equality_tail({:binary, :neq, left, right}, rest2)
    end
  end

  defp parse_equality_tail(left, rest), do: {:ok, left, rest}

  defp parse_comparison(tokens) do
    with {:ok, left, rest} <- parse_addition(tokens) do
      parse_comparison_tail(left, rest)
    end
  end

  defp parse_comparison_tail(left, [op | rest]) when op in [:gt, :lt, :gte, :lte] do
    with {:ok, right, rest2} <- parse_addition(rest) do
      parse_comparison_tail({:binary, op, left, right}, rest2)
    end
  end

  defp parse_comparison_tail(left, rest), do: {:ok, left, rest}

  defp parse_addition(tokens) do
    with {:ok, left, rest} <- parse_multiplication(tokens) do
      parse_addition_tail(left, rest)
    end
  end

  defp parse_addition_tail(left, [:plus | rest]) do
    with {:ok, right, rest2} <- parse_multiplication(rest) do
      parse_addition_tail({:binary, :plus, left, right}, rest2)
    end
  end

  defp parse_addition_tail(left, [:minus | rest]) do
    with {:ok, right, rest2} <- parse_multiplication(rest) do
      parse_addition_tail({:binary, :minus, left, right}, rest2)
    end
  end

  defp parse_addition_tail(left, rest), do: {:ok, left, rest}

  defp parse_multiplication(tokens) do
    with {:ok, left, rest} <- parse_unary(tokens) do
      parse_multiplication_tail(left, rest)
    end
  end

  defp parse_multiplication_tail(left, [:mul | rest]) do
    with {:ok, right, rest2} <- parse_unary(rest) do
      parse_multiplication_tail({:binary, :mul, left, right}, rest2)
    end
  end

  defp parse_multiplication_tail(left, [:div | rest]) do
    with {:ok, right, rest2} <- parse_unary(rest) do
      parse_multiplication_tail({:binary, :div, left, right}, rest2)
    end
  end

  defp parse_multiplication_tail(left, rest), do: {:ok, left, rest}

  defp parse_unary([:not | rest]) do
    with {:ok, expr, rest2} <- parse_unary(rest) do
      {:ok, {:unary, :not, expr}, rest2}
    end
  end

  defp parse_unary([:minus | rest]) do
    with {:ok, expr, rest2} <- parse_unary(rest) do
      {:ok, {:unary, :negate, expr}, rest2}
    end
  end

  defp parse_unary(tokens), do: parse_primary(tokens)

  defp parse_primary([{:number, value} | rest]), do: {:ok, {:literal, value}, rest}
  defp parse_primary([{:string, value} | rest]), do: {:ok, {:literal, value}, rest}
  defp parse_primary([{:boolean, value} | rest]), do: {:ok, {:literal, value}, rest}
  defp parse_primary([{:null, nil} | rest]), do: {:ok, {:literal, nil}, rest}
  defp parse_primary([{:identifier, name} | rest]), do: {:ok, {:identifier, name}, rest}

  defp parse_primary([:lparen | rest]) do
    with {:ok, expr, [:rparen | rest2]} <- parse_expression(rest) do
      {:ok, expr, rest2}
    else
      {:ok, _expr, _rest} -> {:error, error(:invalid_syntax, "missing closing parenthesis")}
      {:error, %Error{} = error} -> {:error, error}
    end
  end

  defp parse_primary(_tokens), do: {:error, error(:invalid_syntax, "expected expression")}

  # ---------- Evaluator ----------

  defp eval({:literal, value}, _context), do: {:ok, value}

  defp eval({:identifier, name}, context) do
    {:ok, Map.get(context, name)}
  end

  defp eval({:unary, :not, expr}, context) do
    with {:ok, value} <- eval(expr, context) do
      {:ok, feel_not(value)}
    end
  end

  defp eval({:unary, :negate, expr}, context) do
    with {:ok, value} <- eval(expr, context) do
      case value do
        nil -> {:ok, nil}
        %Decimal{} = decimal -> {:ok, decimal_negate(decimal)}
        _ -> {:error, error(:type_error, "negation requires a number")}
      end
    end
  end

  defp eval({:binary, op, left, right}, context) do
    with {:ok, left_value} <- eval(left, context),
         {:ok, right_value} <- eval(right, context) do
      eval_binary(op, left_value, right_value)
    end
  end

  defp eval_binary(:plus, left, right), do: decimal_binary(left, right, &decimal_add/2)
  defp eval_binary(:minus, left, right), do: decimal_binary(left, right, &decimal_sub/2)
  defp eval_binary(:mul, left, right), do: decimal_binary(left, right, &decimal_mult/2)

  defp eval_binary(:div, left, right) do
    case {left, right} do
      {nil, _} ->
        {:ok, nil}

      {_, nil} ->
        {:ok, nil}

      {%Decimal{} = l, %Decimal{} = r} ->
        if decimal_equal?(r, decimal_new("0")) do
          {:error, error(:evaluation_error, "division by zero")}
        else
          {:ok, decimal_div(l, r)}
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
        cmp = decimal_compare(left, right)

        value =
          case op do
            :gt -> cmp == :gt
            :gte -> cmp in [:gt, :eq]
            :lt -> cmp == :lt
            :lte -> cmp in [:lt, :eq]
          end

        {:ok, value}

      true ->
        {:error, error(:type_error, "comparison requires compatible values")}
    end
  end

  defp eval_binary(:eq, left, right), do: {:ok, equal_semantic?(left, right)}
  defp eval_binary(:neq, left, right), do: {:ok, not equal_semantic?(left, right)}

  defp eval_binary(:and, left, right), do: {:ok, feel_and(left, right)}
  defp eval_binary(:or, left, right), do: {:ok, feel_or(left, right)}

  defp decimal_binary(left, right, operation) do
    case {left, right} do
      {nil, _} -> {:ok, nil}
      {_, nil} -> {:ok, nil}
      {%Decimal{} = l, %Decimal{} = r} -> {:ok, operation.(l, r)}
      _ -> {:error, error(:type_error, "arithmetic requires numbers")}
    end
  end

  defp equal_semantic?(%Decimal{} = left, %Decimal{} = right), do: decimal_equal?(left, right)
  defp equal_semantic?(left, right), do: left == right

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

defmodule ArbiterFeel do
  @moduledoc false

  @spec hello() :: atom()
  def hello, do: :world
end
