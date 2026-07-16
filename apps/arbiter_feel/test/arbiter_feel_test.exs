defmodule Arbiter.FEELTest do
  use ExUnit.Case

  alias Arbiter.FEEL.Duration
  alias Arbiter.FEEL.Time, as: FeelTime

  test "parse builds AST without evaluation" do
    assert {:ok, {:binary, :plus, {:identifier, "a"}, {:literal, %Decimal{} = _one}}} =
             Arbiter.FEEL.parse("a + 1")
  end

  test "AST validation accepts parser output and rejects malformed trees" do
    assert {:ok, ast} = Arbiter.FEEL.parse("for x in [1, 2] return x + 1")
    assert :ok = Arbiter.FEEL.AST.validate(ast)

    assert {:error, %Arbiter.FEEL.Error{code: :invalid_ast, message: message}} =
             Arbiter.FEEL.AST.validate({:binary, :unknown, {:literal, 1}, {:literal, 2}})

    assert message =~ "invalid AST node"

    assert {:error, %Arbiter.FEEL.Error{code: :invalid_ast}} =
             Arbiter.FEEL.evaluate_ast({:call, :not_an_ast, []}, %{})
  end

  test "if expression evaluates only the selected branch" do
    assert {:ok, Decimal.new("2")} == Arbiter.FEEL.evaluate("if true then 1 + 1 else missing + 1")
    assert {:ok, Decimal.new("3")} == Arbiter.FEEL.evaluate("if false then missing + 1 else 3")
    assert {:ok, "else"} == Arbiter.FEEL.evaluate("if null then \"then\" else \"else\"")

    assert {:error, %Arbiter.FEEL.Error{code: :type_error}} =
             Arbiter.FEEL.evaluate("if 1 then true else false")
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
    assert {:ok, false} == Arbiter.FEEL.evaluate_unary_test("not(2)", Decimal.new("2"), %{})

    assert {:ok, true} ==
             Arbiter.FEEL.evaluate_unary_test("choices", "silver", %{
               "choices" => ["gold", "silver"]
             })
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

    assert {:ok, true} == Arbiter.FEEL.evaluate("list contains([1, 2], 2)")
    assert {:ok, [one, two, three]} == Arbiter.FEEL.evaluate("concatenate([1], [2, 3])")
    assert {:ok, [one, two, three]} == Arbiter.FEEL.evaluate("insert before([1, 3], 2, 2)")
    assert {:ok, [one, three]} == Arbiter.FEEL.evaluate("remove([1, 2, 3], 2)")
    assert {:ok, [three, two, one]} == Arbiter.FEEL.evaluate("reverse([1, 2, 3])")
    assert {:ok, [one, three]} == Arbiter.FEEL.evaluate("index of([2, 1, 2], 2)")
    assert {:ok, [one, two, three]} == Arbiter.FEEL.evaluate("union([1, 2], [2, 3])")
    assert {:ok, [one, two]} == Arbiter.FEEL.evaluate("distinct values([1, 1, 2])")
    assert {:ok, [one, two, three]} == Arbiter.FEEL.evaluate("flatten([1, [2, [3]]])")
    assert {:ok, [two, three]} == Arbiter.FEEL.evaluate("sublist([1, 2, 3], 2)")
  end

  test "boolean aggregate and statistical built-ins" do
    assert {:ok, false} == Arbiter.FEEL.evaluate("all([true, false, true])")
    assert {:ok, nil} == Arbiter.FEEL.evaluate("any(false, null)")
    assert {:ok, Decimal.new("2.5")} == Arbiter.FEEL.evaluate("median([1, 2, 3, 4])")

    assert {:ok, modes} = Arbiter.FEEL.evaluate("mode([3, 1, 3, 1, 2])")
    assert Enum.map(modes, &Decimal.to_string/1) == ["1", "3"]

    assert {:ok, stddev} = Arbiter.FEEL.evaluate("stddev([2, 4, 7, 5])")
    assert Decimal.equal?(stddev, Decimal.new("2.0816659994661"))
  end

  test "Unicode escapes, regex functions, and canonical string conversion" do
    assert {:ok, "🐎"} = Arbiter.FEEL.evaluate("\"\\U01F40E\"")
    assert {:ok, true} = Arbiter.FEEL.evaluate(~S|matches("aA", "(a)\1", "i")|)
    assert {:ok, ["John", "Doe"]} = Arbiter.FEEL.evaluate(~S|split("John Doe", "\s")|)

    assert {:ok, "{a: \"foo\", b: [1, \"bar\"]}"} =
             Arbiter.FEEL.evaluate(~S|string({a: "foo", b: [1, "bar"]})|)
  end

  test "type predicates, between, comments, and context functions" do
    assert {:ok, true} = Arbiter.FEEL.evaluate("5 between 1 and 10")
    assert {:ok, true} = Arbiter.FEEL.evaluate("[1, 2] instance of list<number>")
    assert {:ok, two} = Arbiter.FEEL.evaluate("1 + /* ignored */ 1")
    assert Decimal.equal?(two, Decimal.new("2"))

    assert {:ok, %{"a" => updated}} = Arbiter.FEEL.evaluate(~S|context put({a: 1}, "a", 2)|)
    assert Decimal.equal?(updated, Decimal.new("2"))
  end

  test "calendar extraction and interval relations" do
    assert {:ok, day} = Arbiter.FEEL.evaluate(~S|day of year(@"2020-12-31")|)
    assert Decimal.equal?(day, Decimal.new("366"))
    assert {:ok, "Tuesday"} = Arbiter.FEEL.evaluate(~S|day of week(@"2019-09-17")|)
    assert {:ok, true} = Arbiter.FEEL.evaluate("overlaps([1..5], [5..8])")
    assert {:ok, true} = Arbiter.FEEL.evaluate("includes([1..10], (1..5])")
  end

  test "temporal constructors and arithmetic" do
    assert {:ok, %Date{year: 2026, month: 7, day: 16}} =
             Arbiter.FEEL.evaluate("date(\"2026-07-15\") + duration(\"P1D\")", %{})

    assert {:ok, %FeelTime{} = time} =
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

  test "named-zone date-time arithmetic follows IANA transitions" do
    assert {:ok, %Arbiter.FEEL.DateTime{} = result} =
             Arbiter.FEEL.evaluate(
               "date and time(\"2026-03-28T12:00:00@Europe/Paris\") + duration(\"PT24H\")"
             )

    assert Arbiter.FEEL.DateTime.to_string(result) ==
             "2026-03-29T13:00:00@Europe/Paris"
  end

  test "general string conversion preserves temporal forms" do
    assert {:ok, "P1Y2M"} = Arbiter.FEEL.evaluate("string(duration(\"P1Y2M\"))")
    assert {:ok, "12.50"} = Arbiter.FEEL.evaluate("string(12.50)")
    assert {:ok, "true"} = Arbiter.FEEL.evaluate("string(true)")
  end

  test "duration arithmetic preserves kinds and temporal boundary semantics" do
    assert {:ok, %Duration{kind: :day_time} = scaled} =
             Arbiter.FEEL.evaluate(~S|duration("PT1H") * 2.5|)

    assert Decimal.equal?(Decimal.new(scaled.seconds), Decimal.new(9_000))

    assert {:ok, %Duration{kind: :year_month, months: 6}} =
             Arbiter.FEEL.evaluate(~S|duration("P1Y") / 2|)

    assert {:error, %{code: :type_error}} =
             Arbiter.FEEL.evaluate(~S|duration("P1Y") + duration("P1D")|)

    assert {:ok, ~D[2021-01-01]} =
             Arbiter.FEEL.evaluate(~S|@"2021-01-02" - @"PT1S"|)
  end
end
