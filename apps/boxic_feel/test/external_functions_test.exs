defmodule Boxic.FEEL.ExternalFunctionsTest do
  use ExUnit.Case

  alias Boxic.FEEL.ExternalFunctions

  defmodule HostFunctions do
    def max(left, right), do: Kernel.max(left, right)
    def cosine(value), do: :math.cos(value)
    def identity(value), do: value
    def join(first, rest), do: Enum.join([first | rest], " ")
    def explode(_value), do: raise("host failure")
  end

  defmodule Registry do
    use ExternalFunctions

    external("max", {HostFunctions, :max}, parameters: [:float, :float], returns: :number)
    external("cos", {HostFunctions, :cosine}, parameters: [:float], returns: :number)
    external("integer", {HostFunctions, :identity}, parameters: [:integer], returns: :integer)
    external("char", {HostFunctions, :identity}, parameters: [:char], returns: :char)

    external("join", {HostFunctions, :join},
      parameters: [:string, {:varargs, :string}],
      returns: :string
    )

    external("explode", {HostFunctions, :explode}, parameters: [:feel], returns: :feel)
  end

  test "an allowlisted Elixir function is callable from FEEL and may shadow a built-in" do
    context = Registry.external_functions() |> ExternalFunctions.to_context()

    assert {:ok, result} = Boxic.FEEL.evaluate("max(123.45, 456.78)", context)
    assert Decimal.equal?(result, Decimal.new("456.78"))

    assert {:ok, cosine} = Boxic.FEEL.evaluate("cos(123)", context)
    assert Decimal.equal?(Decimal.round(cosine, 8), Decimal.new("-0.88796891"))
  end

  test "the boundary converts integer, character, and vararg values" do
    context = ExternalFunctions.to_context(Registry)

    assert {:ok, integer} = Boxic.FEEL.evaluate("integer(456)", context)
    assert Decimal.equal?(integer, Decimal.new(456))
    assert {:ok, "a"} = Boxic.FEEL.evaluate(~S|char("a")|, context)
    assert {:ok, "foo bar baz"} = Boxic.FEEL.evaluate(~S|join("foo", "bar", "baz")|, context)
  end

  test "invalid arity, conversion, and host exceptions remain structured FEEL errors" do
    context = ExternalFunctions.to_context(Registry)

    assert {:error, %{code: :arity_error}} = Boxic.FEEL.evaluate("max(1)", context)
    assert {:error, %{code: :type_error}} = Boxic.FEEL.evaluate(~S|char("abc")|, context)

    assert {:error, %{code: :external_function_error, message: "host failure"}} =
             Boxic.FEEL.evaluate("explode(1)", context)
  end
end
