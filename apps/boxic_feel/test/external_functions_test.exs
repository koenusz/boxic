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
    external("count", {HostFunctions, :identity}, parameters: [:number], returns: :number)
  end

  test "an allowlisted Elixir function is callable from an isolated environment" do
    assert {:ok, result} =
             Boxic.FEEL.evaluate("max(123.45, 456.78)", %{}, external_functions: Registry)

    assert Decimal.equal?(result, Decimal.new("456.78"))

    assert {:ok, cosine} =
             Boxic.FEEL.evaluate("cos(123)", %{}, external_functions: Registry)

    assert Decimal.equal?(Decimal.round(cosine, 8), Decimal.new("-0.88796891"))

    assert {:ok, count} =
             Boxic.FEEL.evaluate("count(7)", %{},
               external_functions: Registry,
               external_function_precedence: :registered
             )

    assert Decimal.equal?(count, Decimal.new(7))
  end

  test "the boundary converts integer, character, and vararg values" do
    opts = [external_functions: Registry]

    assert {:ok, integer} = Boxic.FEEL.evaluate("integer(456)", %{}, opts)
    assert Decimal.equal?(integer, Decimal.new(456))
    assert {:ok, "a"} = Boxic.FEEL.evaluate(~S|char("a")|, %{}, opts)
    assert {:ok, "foo bar baz"} = Boxic.FEEL.evaluate(~S|join("foo", "bar", "baz")|, %{}, opts)
  end

  test "invalid arity, conversion, and host exceptions remain structured FEEL errors" do
    opts = [external_functions: Registry]

    assert {:error, %{code: :arity_error}} = Boxic.FEEL.evaluate("max(1)", %{}, opts)
    assert {:error, %{code: :type_error}} = Boxic.FEEL.evaluate(~S|char("abc")|, %{}, opts)

    assert {:error,
            %{
              code: :external_function_error,
              message: "registered external function failed"
            }} = Boxic.FEEL.evaluate("explode(1)", %{}, opts)
  end
end
