defmodule Boxic.FEEL.Parser do
  @moduledoc false
  alias Boxic.FEEL.Error

  def parse_expression([:if | _] = tokens), do: parse_if(tokens)
  def parse_expression([:for | _] = tokens), do: parse_for(tokens)
  def parse_expression([:some | _] = tokens), do: parse_quantifier(tokens)
  def parse_expression([:every | _] = tokens), do: parse_quantifier(tokens)
  def parse_expression([:function | _] = tokens), do: parse_function(tokens)
  def parse_expression(tokens), do: parse_or(tokens)

  defp parse_if([:if | rest]) do
    with {:ok, condition, [:then | rest2]} <- parse_expression(rest),
         {:ok, then_branch, [:else | rest3]} <- parse_expression(rest2),
         {:ok, else_branch, rest4} <- parse_expression(rest3) do
      {:ok, {:if, condition, then_branch, else_branch}, rest4}
    else
      _ -> {:error, error(:invalid_syntax, "invalid if-expression")}
    end
  end

  defp parse_if(_tokens), do: {:error, error(:invalid_syntax, "invalid if-expression")}

  defp parse_for([:for, {:identifier, variable}, :in | rest]) do
    with {:ok, source, rest2} <- parse_for_source(rest),
         {:ok, bindings, [:return | rest3]} <-
           parse_for_bindings([{variable, source}], rest2),
         {:ok, body, rest4} <- parse_expression(rest3) do
      {:ok, {:for, bindings, body}, rest4}
    else
      _ -> {:error, error(:invalid_syntax, "invalid for-expression")}
    end
  end

  defp parse_for(_tokens), do: {:error, error(:invalid_syntax, "invalid for-expression")}

  defp parse_for_source(tokens) do
    with {:ok, source, rest} <- parse_expression(tokens) do
      case rest do
        [:range_dots | rest2] ->
          with {:ok, finish, rest3} <- parse_expression(rest2) do
            {:ok, {:sequence, source, finish}, rest3}
          end

        _ ->
          {:ok, source, rest}
      end
    end
  end

  defp parse_for_bindings(bindings, [:comma, {:identifier, variable}, :in | rest]) do
    with {:ok, source, rest2} <- parse_for_source(rest) do
      parse_for_bindings(bindings ++ [{variable, source}], rest2)
    end
  end

  defp parse_for_bindings(bindings, rest), do: {:ok, bindings, rest}

  defp parse_quantifier([kind, {:identifier, var}, :in | rest]) when kind in [:some, :every] do
    with {:ok, source, [:satisfies | rest2]} <- parse_expression(rest),
         {:ok, predicate, rest3} <- parse_expression(rest2) do
      {:ok, {:quantifier, kind, var, source, predicate}, rest3}
    else
      _ -> {:error, error(:invalid_syntax, "invalid quantifier expression")}
    end
  end

  defp parse_quantifier(_tokens),
    do: {:error, error(:invalid_syntax, "invalid quantifier expression")}

  defp parse_function([:function, :lparen | rest]) do
    with {:ok, params, [:rparen | rest2]} <- parse_param_list(rest),
         {:ok, body, rest3} <- parse_expression(rest2) do
      {:ok, {:function, params, body}, rest3}
    else
      _ -> {:error, error(:invalid_syntax, "invalid function expression")}
    end
  end

  defp parse_function(_tokens),
    do: {:error, error(:invalid_syntax, "invalid function expression")}

  defp parse_param_list([:rparen | _] = rest), do: {:ok, [], rest}

  defp parse_param_list([{:identifier, param} | rest]) do
    {type, rest} = take_parameter_type(rest)
    parse_param_list_tail([{param, type}], rest)
  end

  defp parse_param_list(_tokens), do: {:error, error(:invalid_syntax, "invalid parameter list")}

  defp parse_param_list_tail(params, [:comma, {:identifier, param} | rest]) do
    {type, rest} = take_parameter_type(rest)
    parse_param_list_tail(params ++ [{param, type}], rest)
  end

  defp parse_param_list_tail(params, rest), do: {:ok, params, rest}

  defp take_parameter_type([:colon, {:identifier, type} | rest]), do: {type, rest}
  defp take_parameter_type(rest), do: {nil, rest}

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
    with {:ok, left, rest} <- parse_in_expression(tokens) do
      parse_equality_tail(left, rest)
    end
  end

  defp parse_equality_tail(left, [:eq | rest]) do
    with {:ok, right, rest2} <- parse_in_expression(rest) do
      parse_equality_tail({:binary, :eq, left, right}, rest2)
    end
  end

  defp parse_equality_tail(left, [:neq | rest]) do
    with {:ok, right, rest2} <- parse_in_expression(rest) do
      parse_equality_tail({:binary, :neq, left, right}, rest2)
    end
  end

  defp parse_equality_tail(left, rest), do: {:ok, left, rest}

  defp parse_in_expression(tokens) do
    with {:ok, left, rest} <- parse_comparison(tokens) do
      case rest do
        [:in | rest2] ->
          with {:ok, tests, rest3} <- parse_in_tests(rest2) do
            {:ok, {:in, left, tests}, rest3}
          end

        _ ->
          {:ok, left, rest}
      end
    end
  end

  defp parse_in_tests([:lparen | _] = tokens) do
    case parse_postfix(tokens) do
      {:ok, expression, rest} -> {:ok, expression, rest}
      {:error, _error} -> parse_unary_test_list(tl(tokens), [])
    end
  end

  defp parse_in_tests(tokens), do: parse_unary_test(tokens)

  defp parse_unary_test([op | rest]) when op in [:eq, :neq, :lt, :lte, :gt, :gte] do
    with {:ok, operand, rest2} <- parse_addition(rest) do
      {:ok, {:unary_test, op, operand}, rest2}
    end
  end

  defp parse_unary_test(tokens), do: parse_comparison(tokens)

  defp parse_unary_test_list([:rparen | rest], tests) when tests != [],
    do: {:ok, {:unary_tests, Enum.reverse(tests)}, rest}

  defp parse_unary_test_list(tokens, tests) do
    with {:ok, test, rest} <- parse_unary_test(tokens) do
      case rest do
        [:comma | rest2] -> parse_unary_test_list(rest2, [test | tests])
        [:rparen | rest2] -> {:ok, {:unary_tests, Enum.reverse([test | tests])}, rest2}
        _ -> {:error, error(:invalid_syntax, "invalid unary-test list")}
      end
    end
  end

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

  defp parse_comparison_tail(left, [:between | rest]) do
    with {:ok, lower, [:and | rest2]} <- parse_addition(rest),
         {:ok, upper, rest3} <- parse_addition(rest2) do
      {:ok, {:between, left, lower, upper}, rest3}
    else
      _ -> {:error, error(:invalid_syntax, "invalid between expression")}
    end
  end

  defp parse_comparison_tail(left, [:instance, :of | rest]) when rest != [] do
    {:ok, {:instance_of, left, type_tokens_to_string(rest)}, []}
  end

  defp parse_comparison_tail(left, rest), do: {:ok, left, rest}

  defp type_tokens_to_string(tokens) do
    tokens
    |> Enum.map(fn
      {:identifier, value} -> value
      :lt -> "<"
      :gt -> ">"
      :comma -> ","
      :colon -> ":"
      :minus -> "-"
      :and -> "and"
      token -> Atom.to_string(token)
    end)
    |> Enum.join(" ")
    |> String.replace(~r/\s*<\s*/, "<")
    |> String.replace(~r/\s*>\s*/, ">")
    |> String.replace(~r/\s*,\s*/, ",")
    |> String.replace(~r/\s*:\s*/, ":")
    |> String.replace(~r/\s*-\s*>/, "->")
  end

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
    with {:ok, left, rest} <- parse_power(tokens) do
      parse_multiplication_tail(left, rest)
    end
  end

  defp parse_multiplication_tail(left, [:mul | rest]) do
    with {:ok, right, rest2} <- parse_power(rest) do
      parse_multiplication_tail({:binary, :mul, left, right}, rest2)
    end
  end

  defp parse_multiplication_tail(left, [:div | rest]) do
    with {:ok, right, rest2} <- parse_power(rest) do
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

  defp parse_unary(tokens), do: parse_postfix(tokens)

  defp parse_power(tokens) do
    with {:ok, base, rest} <- parse_unary(tokens) do
      parse_power_tail(base, rest)
    end
  end

  defp parse_power_tail(base, [:pow | rest]) do
    with {:ok, exponent, rest2} <- parse_unary(rest) do
      parse_power_tail({:binary, :pow, base, exponent}, rest2)
    end
  end

  defp parse_power_tail(base, rest), do: {:ok, base, rest}

  defp parse_postfix(tokens) do
    with {:ok, base, rest} <- parse_primary(tokens) do
      parse_postfix_tail(base, rest)
    end
  end

  defp parse_postfix_tail(base, [:dot, {:identifier, key} | rest]) do
    parse_postfix_tail({:path, base, key}, rest)
  end

  defp parse_postfix_tail(base, [:lbracket]), do: {:ok, base, [:lbracket]}

  defp parse_postfix_tail(base, [:lbracket, operator | _] = rest)
       when operator in [:eq, :neq, :gt, :gte, :lt, :lte],
       do: {:ok, base, rest}

  defp parse_postfix_tail(base, [:lbracket | rest]) do
    with {:ok, predicate, [:rbracket | rest2]} <- parse_expression(rest) do
      parse_postfix_tail({:filter, base, predicate}, rest2)
    else
      _ -> {:error, error(:invalid_syntax, "invalid bracket filter")}
    end
  end

  defp parse_postfix_tail(base, [:lparen | rest]) do
    with {:ok, args, [:rparen | rest2]} <- parse_call_args(rest) do
      parse_postfix_tail({:call, base, args}, rest2)
    else
      _ -> {:error, error(:invalid_syntax, "invalid call expression")}
    end
  end

  defp parse_postfix_tail(base, rest), do: {:ok, base, rest}

  defp parse_call_args([:rparen | _] = rest), do: {:ok, [], rest}

  defp parse_call_args([{:identifier, name}, :colon | rest]) do
    with {:ok, value, rest2} <- parse_expression(rest) do
      parse_call_args_tail([{:named_arg, name, value}], rest2)
    end
  end

  defp parse_call_args(tokens) do
    with {:ok, first, rest} <- parse_expression(tokens) do
      parse_call_args_tail([first], rest)
    end
  end

  defp parse_call_args_tail(args, [:comma | rest]) do
    with {:ok, arg, rest2} <- parse_call_arg(rest) do
      parse_call_args_tail(args ++ [arg], rest2)
    end
  end

  defp parse_call_args_tail(args, rest), do: {:ok, args, rest}

  defp parse_call_arg([{:identifier, name}, :colon | rest]) do
    with {:ok, value, rest2} <- parse_expression(rest) do
      {:ok, {:named_arg, name, value}, rest2}
    end
  end

  defp parse_call_arg(tokens), do: parse_expression(tokens)

  defp parse_primary([{:number, value} | rest]), do: {:ok, {:literal, value}, rest}
  defp parse_primary([{:string, value} | rest]), do: {:ok, {:literal, value}, rest}
  defp parse_primary([{:boolean, value} | rest]), do: {:ok, {:literal, value}, rest}
  defp parse_primary([{:null, nil} | rest]), do: {:ok, {:literal, nil}, rest}
  defp parse_primary([{:literal, value} | rest]), do: {:ok, {:literal, value}, rest}
  defp parse_primary([{:identifier, name} | rest]), do: {:ok, {:identifier, name}, rest}
  defp parse_primary([:lbrace | rest]), do: parse_context_literal(rest)
  defp parse_primary([:lbracket | rest]), do: parse_list_or_range(rest)
  defp parse_primary([:rbracket | rest]), do: parse_alternative_range(rest)

  defp parse_primary([:lparen, op | rest]) when op in [:eq, :neq, :lt, :lte, :gt, :gte] do
    with {:ok, operand, [:rparen | rest2]} <- parse_addition(rest) do
      {:ok, {:unary_test, op, operand}, rest2}
    else
      _ -> {:error, error(:invalid_syntax, "invalid unary-test value")}
    end
  end

  defp parse_primary([:lparen | rest]), do: parse_group_or_range(rest)

  defp parse_primary(_tokens), do: {:error, error(:invalid_syntax, "expected expression")}

  defp parse_context_literal([:rbrace | rest]), do: {:ok, {:context, []}, rest}

  defp parse_context_literal(tokens) do
    with {:ok, key, [:colon | rest]} <- parse_context_key(tokens),
         {:ok, expr, rest2} <- parse_expression(rest),
         {:ok, entries, rest3} <- parse_context_tail([{key, expr}], rest2) do
      {:ok, {:context, entries}, rest3}
    else
      _ -> {:error, error(:invalid_syntax, "invalid context literal")}
    end
  end

  defp parse_context_tail(entries, [:comma | rest]) do
    with {:ok, key, [:colon | rest2]} <- parse_context_key(rest),
         {:ok, expr, rest3} <- parse_expression(rest2) do
      parse_context_tail(entries ++ [{key, expr}], rest3)
    end
  end

  defp parse_context_tail(entries, [:rbrace | rest]), do: {:ok, entries, rest}

  defp parse_context_tail(_entries, _rest),
    do: {:error, error(:invalid_syntax, "invalid context literal")}

  defp parse_context_key(tokens) do
    {key_tokens, rest} = Enum.split_while(tokens, &(&1 != :colon))

    case {context_key(key_tokens), rest} do
      {{:ok, key}, [_colon | remaining]} -> {:ok, key, [:colon | remaining]}
      _ -> {:error, error(:invalid_syntax, "invalid context key")}
    end
  end

  defp context_key([{:string, key}]), do: {:ok, key}
  defp context_key([]), do: :error

  defp context_key(tokens) do
    tokens
    |> Enum.reduce_while({:ok, "", nil}, fn token, {:ok, acc, previous} ->
      case context_key_token(token) do
        {:word, value} ->
          separator = if previous == :word, do: " ", else: ""
          {:cont, {:ok, acc <> separator <> value, :word}}

        {:operator, value} ->
          {:cont, {:ok, acc <> value, :operator}}

        :error ->
          {:halt, :error}
      end
    end)
    |> case do
      {:ok, key, _previous} -> {:ok, key}
      :error -> :error
    end
  end

  defp context_key_token({:identifier, value}), do: {:word, value}
  defp context_key_token(:plus), do: {:operator, "+"}
  defp context_key_token(:minus), do: {:operator, "-"}
  defp context_key_token(:mul), do: {:operator, "*"}
  defp context_key_token(:div), do: {:operator, "/"}
  defp context_key_token(_token), do: :error

  defp parse_list_or_range([:rbracket | rest]), do: {:ok, {:list, []}, rest}

  defp parse_list_or_range(tokens) do
    with {:ok, first, rest} <- parse_expression(tokens) do
      case rest do
        [:range_dots | rest2] -> parse_range_rest(true, first, rest2)
        _ -> parse_list_tail([first], rest)
      end
    end
  end

  defp parse_alternative_range(tokens) do
    with {:ok, first, [:range_dots | rest]} <- parse_expression(tokens) do
      parse_range_rest(false, first, rest)
    else
      _ -> {:error, error(:invalid_syntax, "invalid alternative range literal")}
    end
  end

  defp parse_group_or_range(tokens) do
    with {:ok, expr, rest} <- parse_expression(tokens) do
      case rest do
        [:range_dots | rest2] -> parse_range_rest(false, expr, rest2)
        [:rparen | rest2] -> {:ok, expr, rest2}
        _ -> {:error, error(:invalid_syntax, "missing closing parenthesis")}
      end
    end
  end

  defp parse_range_rest(start_inclusive, start_ast, [token, :lbracket | rest]) do
    case token do
      {:number, value} ->
        {:ok, {:range, start_inclusive, false, start_ast, {:literal, value}}, rest}

      {:string, value} ->
        {:ok, {:range, start_inclusive, false, start_ast, {:literal, value}}, rest}

      {:identifier, value} ->
        {:ok, {:range, start_inclusive, false, start_ast, {:identifier, value}}, rest}

      _ ->
        {:error, error(:invalid_syntax, "invalid range end delimiter")}
    end
  end

  defp parse_range_rest(start_inclusive, start_ast, tokens) do
    with {:ok, finish_ast, rest} <- parse_addition(tokens) do
      case rest do
        [:rbracket | rest2] ->
          {:ok, {:range, start_inclusive, true, start_ast, finish_ast}, rest2}

        [:rparen | rest2] ->
          {:ok, {:range, start_inclusive, false, start_ast, finish_ast}, rest2}

        [:lbracket | rest2] ->
          {:ok, {:range, start_inclusive, false, start_ast, finish_ast}, rest2}

        _ ->
          {:error, error(:invalid_syntax, "invalid range end delimiter")}
      end
    end
  end

  defp parse_list_tail(items, [:comma | rest]) do
    with {:ok, next_item, rest2} <- parse_expression(rest) do
      parse_list_tail(items ++ [next_item], rest2)
    end
  end

  defp parse_list_tail(items, [:rbracket | rest]), do: {:ok, {:list, items}, rest}

  defp parse_list_tail(_items, _rest),
    do: {:error, error(:invalid_syntax, "invalid list literal")}

  defp error(code, message), do: %Error{code: code, message: message}
end
