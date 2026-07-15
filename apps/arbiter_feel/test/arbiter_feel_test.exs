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

  test "range literals evaluate to FEEL ranges" do
    assert {:ok, %Arbiter.FEEL.Range{start_inclusive: true, end_inclusive: false} = range} =
             Arbiter.FEEL.evaluate("[1..3)", %{})

    assert Decimal.equal?(range.start, Decimal.new("1"))
    assert Decimal.equal?(range.end, Decimal.new("3"))
  end

  test "path expressions resolve context entries" do
    assert {:ok, %Decimal{} = value} = Arbiter.FEEL.evaluate("{a: 2}.a", %{})
    assert Decimal.equal?(value, Decimal.new("2"))
  end

  test "bracket filters retain matching list items" do
    assert {:ok, [%Decimal{} = two, %Decimal{} = three]} =
             Arbiter.FEEL.evaluate("[1,2,3][item > 1]", %{})

    assert Decimal.equal?(two, Decimal.new("2"))
    assert Decimal.equal?(three, Decimal.new("3"))
  end

  test "for-expressions project over lists" do
    assert {:ok, [%Decimal{} = two, %Decimal{} = three, %Decimal{} = four]} =
             Arbiter.FEEL.evaluate("for x in [1,2,3] return x + 1", %{})

    assert Decimal.equal?(two, Decimal.new("2"))
    assert Decimal.equal?(three, Decimal.new("3"))
    assert Decimal.equal?(four, Decimal.new("4"))
  end

  test "some and every quantifiers evaluate predicates" do
    assert {:ok, true} == Arbiter.FEEL.evaluate("some x in [1,2,3] satisfies x > 2", %{})
    assert {:ok, false} == Arbiter.FEEL.evaluate("every x in [1,2,3] satisfies x > 2", %{})
  end

  test "function closures capture surrounding context" do
    assert {:ok, %Decimal{} = value} =
             Arbiter.FEEL.evaluate("(function(x) x + inc)(2)", %{"inc" => Decimal.new("5")})

    assert Decimal.equal?(value, Decimal.new("7"))
  end

  test "unary test evaluation supports comparators and ranges" do
    assert {:ok, true} == Arbiter.FEEL.evaluate_unary_test("> 5", Decimal.new("7"), %{})
    assert {:ok, false} == Arbiter.FEEL.evaluate_unary_test("<= 5", Decimal.new("7"), %{})
    assert {:ok, true} == Arbiter.FEEL.evaluate_unary_test("[1..10]", Decimal.new("7"), %{})
  end
end
