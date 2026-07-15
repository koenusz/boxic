defmodule Arbiter.FEEL do
  @moduledoc """
  FEEL entry point.

  Supports an AST-backed parser and evaluator for core FEEL semantics and
  WP-06 structural features: ranges, unary tests, path/filter expressions,
  for-expressions, quantifiers, and user-defined closures.
  """

  alias Arbiter.FEEL.Error
  alias Arbiter.FEEL.AST
  alias Arbiter.FEEL.Builtins
  alias Arbiter.FEEL.Function
  alias Arbiter.FEEL.Range
  alias Arbiter.FEEL.Duration

  @type ast ::
          {:literal, term()}
          | {:identifier, String.t()}
          | {:unary, atom(), ast()}
          | {:binary, atom(), ast(), ast()}
          | {:list, [ast()]}
          | {:context, [{String.t(), ast()}]}
          | {:path, ast(), String.t()}
          | {:filter, ast(), ast()}
          | {:range, boolean(), boolean(), ast(), ast()}
          | {:if, ast(), ast(), ast()}
          | {:for, String.t(), ast(), ast()}
          | {:quantifier, :some | :every, String.t(), ast(), ast()}
          | {:function, [String.t()], ast()}
          | {:call, ast(), [ast()]}
  @type context :: %{optional(String.t()) => term()}

  @spec parse(String.t()) :: {:ok, ast()} | {:error, Error.t()}
  def parse(expression) when is_binary(expression) do
    trimmed = String.trim(expression)

    if trimmed == "" do
      {:error, error(:empty_expression, "expression cannot be empty")}
    else
      with {:ok, tokens} <- tokenize(trimmed),
           {:ok, ast, []} <- parse_expression(tokens),
           :ok <- AST.validate(ast) do
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
    with :ok <- AST.validate(ast) do
      eval(ast, context)
    end
  end

  @spec evaluate_unary_test(String.t(), term(), context()) ::
          {:ok, boolean()} | {:error, Error.t()}
  def evaluate_unary_test(test_expression, value, context \\ %{})
      when is_binary(test_expression) and is_map(context) do
    trimmed = String.trim(test_expression)

    cond do
      trimmed == "-" ->
        {:ok, true}

      comparator_unary_test?(trimmed) ->
        eval_comparator_unary_test(trimmed, value, context)

      range_unary_test?(trimmed) ->
        with {:ok, range_value} <- evaluate(trimmed, context),
             true <- match?(%Range{}, range_value) do
          {:ok, range_contains?(range_value, value)}
        else
          false -> {:error, error(:type_error, "range unary test expected a range")}
          {:error, %Error{} = e} -> {:error, e}
        end

      true ->
        with {:ok, expected} <- evaluate(trimmed, context) do
          {:ok, equal_semantic?(value, expected)}
        end
    end
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

  defp tokenize(<<"substring before", rest::binary>>, acc),
    do: tokenize(rest, [{:identifier, "substring_before"} | acc])

  defp tokenize(<<"substring after", rest::binary>>, acc),
    do: tokenize(rest, [{:identifier, "substring_after"} | acc])

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

  # ---------- Parser ----------

  defp parse_expression([:if | _] = tokens), do: parse_if(tokens)
  defp parse_expression([:for | _] = tokens), do: parse_for(tokens)
  defp parse_expression([:some | _] = tokens), do: parse_quantifier(tokens)
  defp parse_expression([:every | _] = tokens), do: parse_quantifier(tokens)
  defp parse_expression([:function | _] = tokens), do: parse_function(tokens)
  defp parse_expression(tokens), do: parse_or(tokens)

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

  defp parse_for([:for, {:identifier, var}, :in | rest]) do
    with {:ok, source, [:return | rest2]} <- parse_expression(rest),
         {:ok, body, rest3} <- parse_expression(rest2) do
      {:ok, {:for, var, source, body}, rest3}
    else
      _ -> {:error, error(:invalid_syntax, "invalid for-expression")}
    end
  end

  defp parse_for(_tokens), do: {:error, error(:invalid_syntax, "invalid for-expression")}

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
  defp parse_param_list([{:identifier, param} | rest]), do: parse_param_list_tail([param], rest)
  defp parse_param_list(_tokens), do: {:error, error(:invalid_syntax, "invalid parameter list")}

  defp parse_param_list_tail(params, [:comma, {:identifier, param} | rest]),
    do: parse_param_list_tail(params ++ [param], rest)

  defp parse_param_list_tail(params, rest), do: {:ok, params, rest}

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

  defp parse_unary(tokens), do: parse_power(tokens)

  defp parse_power(tokens) do
    with {:ok, base, rest} <- parse_postfix(tokens) do
      case rest do
        [:pow | rest2] ->
          with {:ok, exponent, rest3} <- parse_unary(rest2) do
            {:ok, {:binary, :pow, base, exponent}, rest3}
          end

        _ ->
          {:ok, base, rest}
      end
    end
  end

  defp parse_postfix(tokens) do
    with {:ok, base, rest} <- parse_primary(tokens) do
      parse_postfix_tail(base, rest)
    end
  end

  defp parse_postfix_tail(base, [:dot, {:identifier, key} | rest]) do
    parse_postfix_tail({:path, base, key}, rest)
  end

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

  defp parse_call_args(tokens) do
    with {:ok, first, rest} <- parse_expression(tokens) do
      parse_call_args_tail([first], rest)
    end
  end

  defp parse_call_args_tail(args, [:comma | rest]) do
    with {:ok, arg, rest2} <- parse_expression(rest) do
      parse_call_args_tail(args ++ [arg], rest2)
    end
  end

  defp parse_call_args_tail(args, rest), do: {:ok, args, rest}

  defp parse_primary([{:number, value} | rest]), do: {:ok, {:literal, value}, rest}
  defp parse_primary([{:string, value} | rest]), do: {:ok, {:literal, value}, rest}
  defp parse_primary([{:boolean, value} | rest]), do: {:ok, {:literal, value}, rest}
  defp parse_primary([{:null, nil} | rest]), do: {:ok, {:literal, nil}, rest}
  defp parse_primary([{:identifier, name} | rest]), do: {:ok, {:identifier, name}, rest}
  defp parse_primary([:lbrace | rest]), do: parse_context_literal(rest)
  defp parse_primary([:lbracket | rest]), do: parse_list_or_range(rest)
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

  defp parse_group_or_range(tokens) do
    with {:ok, expr, rest} <- parse_expression(tokens) do
      case rest do
        [:range_dots | rest2] -> parse_range_rest(false, expr, rest2)
        [:rparen | rest2] -> {:ok, expr, rest2}
        _ -> {:error, error(:invalid_syntax, "missing closing parenthesis")}
      end
    end
  end

  defp parse_range_rest(start_inclusive, start_ast, tokens) do
    with {:ok, finish_ast, rest} <- parse_expression(tokens) do
      case rest do
        [:rbracket | rest2] ->
          {:ok, {:range, start_inclusive, true, start_ast, finish_ast}, rest2}

        [:rparen | rest2] ->
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

  # ---------- Evaluator ----------

  defp eval({:literal, value}, _context), do: {:ok, value}

  defp eval({:identifier, name}, context) do
    case Map.fetch(context, name) do
      {:ok, value} ->
        {:ok, value}

      :error ->
        Builtins.resolve(name)
    end
  end

  defp eval({:list, items}, context) do
    eval_list(items, context, [])
  end

  defp eval({:context, entries}, context) do
    eval_context_entries(entries, context, %{})
  end

  defp eval({:path, expr, key}, context) do
    with {:ok, value} <- eval(expr, context) do
      case value do
        list when is_list(list) ->
          {:ok, Enum.map(list, fn item -> if is_map(item), do: Map.get(item, key), else: nil end)}

        map when is_map(map) ->
          {:ok, Map.get(map, key)}

        _ ->
          {:ok, nil}
      end
    end
  end

  defp eval({:filter, source_expr, predicate}, context) do
    with {:ok, source} <- eval(source_expr, context) do
      case source do
        list when is_list(list) ->
          eval_list_filter(list, predicate, context)

        scalar ->
          eval_scalar_filter(scalar, predicate, context)
      end
    end
  end

  defp eval({:range, start_inclusive, end_inclusive, start_ast, end_ast}, context) do
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

  defp eval({:if, condition_ast, then_ast, else_ast}, context) do
    with {:ok, condition} <- eval(condition_ast, context) do
      case condition do
        true -> eval(then_ast, context)
        false -> eval(else_ast, context)
        nil -> eval(else_ast, context)
        _ -> {:error, error(:type_error, "if condition must be boolean")}
      end
    end
  end

  defp eval({:for, var, source_ast, body_ast}, context) do
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

  defp eval({:quantifier, kind, var, source_ast, predicate_ast}, context) do
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

  defp eval({:function, params, body}, context) do
    {:ok, %Function{params: params, body: body, closure: context}}
  end

  defp eval({:call, callee_ast, args_ast}, context) do
    with {:ok, callee} <- eval(callee_ast, context),
         {:ok, arg_values} <- eval_list(args_ast, context, []) do
      apply_function(callee, arg_values)
    end
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

  defp apply_function(%Function{params: params, body: body, closure: closure}, args)
       when length(params) == length(args) do
    call_context =
      params
      |> Enum.zip(args)
      |> Enum.reduce(closure, fn {name, value}, acc -> Map.put(acc, name, value) end)

    eval(body, call_context)
  end

  defp apply_function({:builtin, name}, args) do
    Builtins.invoke(name, args)
  end

  defp apply_function(%Function{}, _args),
    do: {:error, error(:arity_error, "function called with invalid arity")}

  defp apply_function(fun, args) when is_function(fun, length(args)) do
    {:ok, apply(fun, args)}
  end

  defp apply_function(_callee, _args),
    do: {:error, error(:type_error, "attempted to call a non-function value")}

  defp eval_binary(:plus, left, right), do: plus(left, right)
  defp eval_binary(:minus, left, right), do: minus(left, right)
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

  defp plus(left, right) do
    case {left, right} do
      {nil, _} ->
        {:ok, nil}

      {_, nil} ->
        {:ok, nil}

      {%Decimal{} = l, %Decimal{} = r} ->
        {:ok, decimal_add(l, r)}

      {%Date{} = date, %Duration{} = duration} ->
        {:ok, Duration.add_to_date(date, duration)}

      {%Duration{} = duration, %Date{} = date} ->
        {:ok, Duration.add_to_date(date, duration)}

      {%DateTime{} = datetime, %Duration{} = duration} ->
        {:ok, Duration.add_to_datetime(datetime, duration)}

      {%Duration{} = duration, %DateTime{} = datetime} ->
        {:ok, Duration.add_to_datetime(datetime, duration)}

      {%Time{} = time, %Duration{} = duration} ->
        {:ok, Duration.add_to_time(time, duration)}

      {%Duration{} = duration, %Time{} = time} ->
        {:ok, Duration.add_to_time(time, duration)}

      {%Duration{} = l, %Duration{} = r} ->
        {:ok, Duration.add(l, r)}

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

      {%Date{} = date, %Duration{} = duration} ->
        {:ok, Duration.add_to_date(date, Duration.negate(duration))}

      {%DateTime{} = datetime, %Duration{} = duration} ->
        {:ok, Duration.add_to_datetime(datetime, Duration.negate(duration))}

      {%Time{} = time, %Duration{} = duration} ->
        {:ok, Duration.add_to_time(time, Duration.negate(duration))}

      {%Duration{} = l, %Duration{} = r} ->
        {:ok, Duration.subtract(l, r)}

      _ ->
        {:error, error(:type_error, "subtraction requires compatible values")}
    end
  end

  defp compare_from_op(op, cmp) do
    case op do
      :gt -> cmp == :gt
      :gte -> cmp in [:gt, :eq]
      :lt -> cmp == :lt
      :lte -> cmp in [:lt, :eq]
    end
  end

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
        {:error, error(:type_error, "exponent must be an integer")}
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
  defp feel_equal(left, right) when is_boolean(left) and is_boolean(right), do: left == right
  defp feel_equal(left, right) when is_binary(left) and is_binary(right), do: left == right
  defp feel_equal(%Date{} = left, %Date{} = right), do: Date.compare(left, right) == :eq
  defp feel_equal(%Time{} = left, %Time{} = right), do: Time.compare(left, right) == :eq

  defp feel_equal(%DateTime{} = left, %DateTime{} = right),
    do: DateTime.compare(left, right) == :eq

  defp feel_equal(%Duration{} = left, %Duration{} = right),
    do: left.months == right.months and left.seconds == right.seconds

  defp feel_equal(%Range{} = left, %Range{} = right) do
    left.start_inclusive == right.start_inclusive and
      left.end_inclusive == right.end_inclusive and
      feel_equal(left.start, right.start) == true and
      feel_equal(left.end, right.end) == true
  end

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

  defp equal_semantic?(%Decimal{} = left, %Decimal{} = right), do: decimal_equal?(left, right)
  defp equal_semantic?(left, right), do: left == right

  defp comparator_unary_test?(expression) do
    Regex.match?(~r/^(<=|>=|<|>|!=|=)\s*.+$/, expression)
  end

  defp range_unary_test?(expression) do
    String.starts_with?(expression, "[") or String.starts_with?(expression, "(")
  end

  defp eval_comparator_unary_test(expression, value, context) do
    %{"op" => op, "rhs" => rhs} =
      Regex.named_captures(~r/^(?<op><=|>=|<|>|!=|=)\s*(?<rhs>.+)$/, expression)

    with {:ok, rhs_value} <- evaluate(rhs, context) do
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

  defp compare_for_unary_test(op, lhs, rhs) when op in ["=", "!="] do
    eq = equal_semantic?(lhs, rhs)
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

  defp range_contains?(%Range{} = range, value) do
    lower_ok = range_lower_ok?(range, value)
    upper_ok = range_upper_ok?(range, value)
    lower_ok and upper_ok
  end

  defp range_lower_ok?(%Range{start: nil}, _value), do: true

  defp range_lower_ok?(%Range{start: start, start_inclusive: inclusive}, value) do
    case compare_for_bounds(value, start) do
      :gt -> true
      :eq -> inclusive
      _ -> false
    end
  end

  defp range_upper_ok?(%Range{end: nil}, _value), do: true

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

defmodule ArbiterFeel do
  @moduledoc false

  @spec hello() :: atom()
  def hello, do: :world
end
