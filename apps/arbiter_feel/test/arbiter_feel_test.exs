defmodule Arbiter.FEELTest do
  use ExUnit.Case

  test "parse builds AST without evaluation" do
    assert {:ok, {:binary, :plus, {:identifier, "a"}, {:literal, %Decimal{} = _one}}} =
             Arbiter.FEEL.parse("a + 1")
  end

  test "arithmetic uses decimal semantics" do
    assert {:ok, %Decimal{} = result} = Arbiter.FEEL.evaluate("1 + 2 * 3", %{})
    assert Decimal.equal?(result, Decimal.new("7"))
  end

  test "comparison evaluates against decimal values" do
    assert {:ok, true} == Arbiter.FEEL.evaluate("7 > 2", %{})
    assert {:ok, false} == Arbiter.FEEL.evaluate("1 >= 2", %{})
  end

  test "three-valued boolean logic" do
    assert {:ok, false} == Arbiter.FEEL.evaluate("false and null", %{})
    assert {:ok, true} == Arbiter.FEEL.evaluate("true or null", %{})
    assert {:ok, nil} == Arbiter.FEEL.evaluate("not null", %{})
  end

  test "null propagates in arithmetic and ordering comparisons" do
    assert {:ok, nil} == Arbiter.FEEL.evaluate("null + 1", %{})
    assert {:ok, nil} == Arbiter.FEEL.evaluate("2 < null", %{})
  end

  test "context values resolve by name" do
    assert {:ok, %Decimal{} = value} =
             Arbiter.FEEL.evaluate("input + 1", %{"input" => Decimal.new("2")})

    assert Decimal.equal?(value, Decimal.new("3"))
  end
end
