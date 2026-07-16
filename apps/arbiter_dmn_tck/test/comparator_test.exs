defmodule Arbiter.DMN.TCK.ComparatorTest do
  use ExUnit.Case, async: true

  alias Arbiter.DMN.TCK.Comparator
  alias Arbiter.FEEL.Duration

  test "compares nested canonical values semantically" do
    {:ok, equivalent_datetime, _offset} = DateTime.from_iso8601("2026-07-15T12:30:00+02:00")

    left = %{
      "number" => Decimal.new("1.00"),
      "date" => ~D[2026-07-15],
      "time" => ~T[10:30:00],
      "date_time" => ~U[2026-07-15 10:30:00Z],
      "duration" => %Duration{kind: :year_month, months: 2, seconds: 90},
      "items" => [Decimal.new("2.0"), %{"ok" => true}]
    }

    right = %{
      "number" => Decimal.new("1"),
      "date" => ~D[2026-07-15],
      "time" => ~T[10:30:00],
      "date_time" => equivalent_datetime,
      "duration" => %Duration{kind: :year_month, months: 2, seconds: 90},
      "items" => [Decimal.new("2"), %{"ok" => true}]
    }

    assert Comparator.semantic_equal?(left, right)
    assert Comparator.semantic_equal?(Decimal.new("2.0"), 2)

    assert Comparator.semantic_equal?(
             Decimal.new("966.396742204988"),
             Decimal.new("966.3967422049753602")
           )

    refute Comparator.semantic_equal?(Decimal.new("1"), Decimal.new("1.000001"))
    assert Comparator.semantic_equal?(true, "true")
    assert Comparator.semantic_equal?("false", false)
  end

  test "supports explicit unordered list comparison without losing multiplicity" do
    assert Comparator.semantic_equal?(
             [Decimal.new("1.0"), Decimal.new("2"), Decimal.new("1")],
             [Decimal.new("1"), Decimal.new("1.00"), Decimal.new("2.0")],
             ordered: false
           )

    refute Comparator.semantic_equal?([1, 1, 2], [1, 2, 2], ordered: false)
    refute Comparator.semantic_equal?([1, 2], [2, 1])
    refute Comparator.semantic_equal?([[1, 2]], [[2, 1]], ordered: false)
  end
end
