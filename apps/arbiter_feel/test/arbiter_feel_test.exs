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
    assert {:ok, false} == Arbiter.FEEL.evaluate_unary_test("[1..10)", Decimal.new("10"), %{})
  end

  test "context entries scope and shadow outer context" do
    assert {:ok, %Decimal{} = value} =
             Arbiter.FEEL.evaluate("{x: 2, y: x + 1}.y", %{"x" => Decimal.new("99")})

    assert Decimal.equal?(value, Decimal.new("3"))
  end

  test "function parameter shadows captured name" do
    assert {:ok, %Decimal{} = value} =
             Arbiter.FEEL.evaluate("(function(x) x + 1)(2)", %{"x" => Decimal.new("100")})

    assert Decimal.equal?(value, Decimal.new("3"))
  end

  test "string and numeric built-ins" do
    assert {:ok, %Decimal{} = len} = Arbiter.FEEL.evaluate("string_length(\"hello\")", %{})
    assert Decimal.equal?(len, Decimal.new("5"))

    assert {:ok, "HE"} == Arbiter.FEEL.evaluate("substring(upper_case(\"hello\"), 1, 2)", %{})
    assert {:ok, %Decimal{} = sum} = Arbiter.FEEL.evaluate("sum([1,2,3])", %{})
    assert Decimal.equal?(sum, Decimal.new("6"))
  end

  test "list built-ins" do
    assert {:ok, %Decimal{} = count} = Arbiter.FEEL.evaluate("count([1,2,3])", %{})
    assert Decimal.equal?(count, Decimal.new("3"))

    assert {:ok, [%Decimal{} = one, %Decimal{} = two, %Decimal{} = three]} =
             Arbiter.FEEL.evaluate("append([1,2], 3)", %{})

    assert Decimal.equal?(one, Decimal.new("1"))
    assert Decimal.equal?(two, Decimal.new("2"))
    assert Decimal.equal?(three, Decimal.new("3"))
  end

  test "temporal constructors and arithmetic" do
    assert {:ok, %Date{year: 2026, month: 7, day: 16}} =
             Arbiter.FEEL.evaluate("date(\"2026-07-15\") + duration(\"P1D\")", %{})

    assert {:ok, %Time{} = time} =
             Arbiter.FEEL.evaluate("time(\"10:00:00\") + duration(\"PT90M\")", %{})

    assert time.hour == 11
    assert time.minute == 30
  end

  test "timezone-aware datetime comparison" do
    assert {:ok, true} =
             Arbiter.FEEL.evaluate(
               "date_time(\"2026-07-15T10:00:00+00:00\") = date_time(\"2026-07-15T12:00:00+02:00\")",
               %{}
             )
  end
end
