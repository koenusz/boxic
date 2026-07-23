defmodule Boxic.FEEL do
  @moduledoc """
  Parses and evaluates FEEL expressions.

  The public facade accepts FEEL source through `parse/1` and `evaluate/2`, or
  an already parsed syntax tree through `evaluate_ast/2`.
  """

  alias Boxic.FEEL.{AST, Error, Evaluator, ExternalFunctions, Parser, Tokenizer}

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
          | {:in, ast(), ast()}
          | {:unary_test, atom(), ast()}
          | {:unary_tests, [ast()]}
          | {:sequence, ast(), ast()}
          | {:if, ast(), ast(), ast()}
          | {:for, String.t(), ast(), ast()}
          | {:for, [{String.t(), ast()}], ast()}
          | {:quantifier, :some | :every, String.t(), ast(), ast()}
          | {:between, ast(), ast(), ast()}
          | {:instance_of, ast(), String.t()}
          | {:function, [String.t()], ast()}
          | {:call, ast(), [ast()]}
  @type context :: %{optional(String.t()) => term()}

  @doc """
  Parses a FEEL expression into Boxic's public AST representation.

      iex> Boxic.FEEL.parse("1 + 2")
      {:ok, {:binary, :plus, {:literal, Decimal.new("1")}, {:literal, Decimal.new("2")}}}
  """
  @spec parse(String.t()) :: {:ok, ast()} | {:error, Error.t()}
  def parse(expression) when is_binary(expression) do
    trimmed = String.trim(expression)

    if trimmed == "" do
      {:error, %Error{code: :empty_expression, message: "expression cannot be empty"}}
    else
      with {:ok, tokens} <- Tokenizer.tokenize(trimmed),
           {:ok, ast, []} <- Parser.parse_expression(tokens),
           :ok <- AST.validate(ast) do
        {:ok, ast}
      else
        {:ok, _ast, rest} ->
          {:error, %Error{code: :invalid_syntax, message: "unexpected tokens: #{inspect(rest)}"}}

        {:error, %Error{} = error} ->
          {:error, error}
      end
    end
  end

  @doc """
  Parses and evaluates a FEEL expression.

      iex> Boxic.FEEL.evaluate("price * quantity", %{
      ...>   "price" => Decimal.new("12.50"),
      ...>   "quantity" => Decimal.new("2")
      ...> })
      {:ok, Decimal.new("25.00")}
  """
  @spec evaluate(String.t(), context()) :: {:ok, term()} | {:error, Error.t()}
  def evaluate(expression, context \\ %{}) when is_binary(expression) and is_map(context) do
    with {:ok, ast} <- parse(expression), do: evaluate_ast(ast, context)
  end

  @doc "Evaluates FEEL with a trusted external-function environment."
  @spec evaluate(String.t(), context(), keyword()) :: {:ok, term()} | {:error, Error.t()}
  def evaluate(expression, context, opts)
      when is_binary(expression) and is_map(context) and is_list(opts) do
    with {:ok, context} <- evaluator_context(context, opts),
         {:ok, ast} <- parse(expression) do
      evaluate_ast(ast, context)
    end
  end

  @doc "Evaluates an AST previously returned by `parse/1`."
  @spec evaluate_ast(ast(), context()) :: {:ok, term()} | {:error, Error.t()}
  def evaluate_ast(ast, context) when is_map(context) do
    with :ok <- AST.validate(ast), do: Evaluator.eval(ast, context)
  end

  @doc "Evaluates a parsed AST with a trusted external-function environment."
  @spec evaluate_ast(ast(), context(), keyword()) :: {:ok, term()} | {:error, Error.t()}
  def evaluate_ast(ast, context, opts) when is_map(context) and is_list(opts) do
    with {:ok, context} <- evaluator_context(context, opts), do: evaluate_ast(ast, context)
  end

  @doc """
  Evaluates a FEEL unary test against `value`.

      iex> Boxic.FEEL.evaluate_unary_test(">= 18", Decimal.new("21"))
      {:ok, true}
  """
  @spec evaluate_unary_test(String.t(), term(), context()) ::
          {:ok, boolean()} | {:error, Error.t()}
  def evaluate_unary_test(test_expression, value, context \\ %{})
      when is_binary(test_expression) and is_map(context) do
    Evaluator.evaluate_unary_test(test_expression, value, context)
  end

  @doc "Evaluates a unary test with a trusted external-function environment."
  @spec evaluate_unary_test(String.t(), term(), context(), keyword()) ::
          {:ok, boolean()} | {:error, Error.t()}
  def evaluate_unary_test(test_expression, value, context, opts)
      when is_binary(test_expression) and is_map(context) and is_list(opts) do
    with {:ok, context} <- evaluator_context(context, opts) do
      Evaluator.evaluate_unary_test(test_expression, value, context)
    end
  end

  defp evaluator_context(context, opts) do
    case Keyword.get(opts, :external_functions) do
      nil ->
        {:ok, context}

      registry ->
        precedence = Keyword.get(opts, :external_function_precedence, :builtins)

        if precedence in [:builtins, :registered] do
          {:ok, ExternalFunctions.attach(context, registry, precedence)}
        else
          {:error,
           Error.new(
             :invalid_option,
             "external_function_precedence must be :builtins or :registered"
           )}
        end
    end
  end
end
