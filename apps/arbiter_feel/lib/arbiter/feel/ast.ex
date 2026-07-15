defmodule Arbiter.FEEL.AST do
  @moduledoc """
  Structural validation for FEEL abstract syntax trees.

  Parsing uses this boundary before returning an AST. Callers constructing an
  AST directly can use `validate/1` before passing it to the evaluator.
  """

  alias Arbiter.FEEL.Error

  @unary_operators [:negate, :not]
  @binary_operators [:plus, :minus, :mul, :div, :pow, :eq, :neq, :lt, :lte, :gt, :gte, :and, :or]

  @spec validate(term()) :: :ok | {:error, Error.t()}
  def validate(ast) do
    case validate_node(ast) do
      :ok -> :ok
      {:error, reason} -> {:error, Error.new(:invalid_ast, reason)}
    end
  end

  defp validate_node({:literal, _value}), do: :ok
  defp validate_node({:identifier, name}) when is_binary(name) and name != "", do: :ok

  defp validate_node({:unary, operator, operand}) when operator in @unary_operators,
    do: validate_node(operand)

  defp validate_node({:binary, operator, left, right}) when operator in @binary_operators,
    do: validate_children([left, right])

  defp validate_node({:list, items}) when is_list(items), do: validate_children(items)

  defp validate_node({:context, entries}) when is_list(entries) do
    names = Enum.map(entries, fn {name, _value} -> name end)

    if length(names) == length(Enum.uniq(names)) do
      Enum.reduce_while(entries, :ok, fn
        {name, value}, :ok when is_binary(name) -> continue_or_halt(validate_node(value))
        entry, :ok -> {:halt, {:error, "invalid context entry: #{inspect(entry)}"}}
      end)
    else
      {:error, "context keys must be unique"}
    end
  end

  defp validate_node({:path, source, name}) when is_binary(name) and name != "",
    do: validate_node(source)

  defp validate_node({:filter, source, predicate}),
    do: validate_children([source, predicate])

  defp validate_node({:range, start_inclusive, end_inclusive, first, last})
       when is_boolean(start_inclusive) and is_boolean(end_inclusive),
       do: validate_children([first, last])

  defp validate_node({:if, condition, then_branch, else_branch}),
    do: validate_children([condition, then_branch, else_branch])

  defp validate_node({:in, value, tests}), do: validate_children([value, tests])

  defp validate_node({:unary_test, operator, operand})
       when operator in [:eq, :neq, :lt, :lte, :gt, :gte],
       do: validate_node(operand)

  defp validate_node({:unary_tests, tests}) when is_list(tests) and tests != [],
    do: validate_children(tests)

  defp validate_node({:sequence, first, last}), do: validate_children([first, last])

  defp validate_node({:for, variable, source, body}) when is_binary(variable) and variable != "",
    do: validate_children([source, body])

  defp validate_node({:for, bindings, body}) when is_list(bindings) and bindings != [] do
    variables = Enum.map(bindings, fn {variable, _source} -> variable end)

    if Enum.all?(variables, &(is_binary(&1) and &1 != "")) and
         length(variables) == length(Enum.uniq(variables)) do
      validate_children(Enum.map(bindings, &elem(&1, 1)) ++ [body])
    else
      {:error, "for bindings must use unique, non-empty names"}
    end
  end

  defp validate_node({:quantifier, kind, variable, source, predicate})
       when kind in [:some, :every] and is_binary(variable) and variable != "",
       do: validate_children([source, predicate])

  defp validate_node({:function, parameters, body}) when is_list(parameters) do
    if Enum.all?(parameters, &(is_binary(&1) and &1 != "")) and
         length(parameters) == length(Enum.uniq(parameters)) do
      validate_node(body)
    else
      {:error, "function parameters must be unique, non-empty names"}
    end
  end

  defp validate_node({:call, function, arguments}) when is_list(arguments),
    do: validate_children([function | arguments])

  defp validate_node(ast), do: {:error, "invalid AST node: #{inspect(ast)}"}

  defp validate_children(nodes) do
    Enum.reduce_while(nodes, :ok, fn node, :ok -> continue_or_halt(validate_node(node)) end)
  end

  defp continue_or_halt(:ok), do: {:cont, :ok}
  defp continue_or_halt({:error, _reason} = error), do: {:halt, error}
end
