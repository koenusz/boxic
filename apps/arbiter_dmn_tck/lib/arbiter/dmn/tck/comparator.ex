defmodule Arbiter.DMN.TCK.Comparator do
  @moduledoc """
  Semantic comparator for expected and actual values.

  Lists are ordered by default. Callers comparing a TCK result whose semantics
  are explicitly unordered can pass `ordered: false`; duplicate values are
  still significant.
  """

  alias Arbiter.FEEL.Duration
  alias Arbiter.FEEL.DateTime, as: FeelDateTime
  alias Arbiter.FEEL.Time, as: FeelTime

  @spec semantic_equal?(term(), term(), keyword()) :: boolean()
  def semantic_equal?(left, right, opts \\ []) do
    compare(left, right, Keyword.get(opts, :ordered, true))
  end

  defp compare(%Decimal{} = left, %Decimal{} = right, _ordered),
    do: decimal_equal?(left, right)

  defp compare(%Decimal{} = left, right, _ordered) when is_integer(right),
    do: Decimal.equal?(left, Decimal.new(right))

  defp compare(left, %Decimal{} = right, _ordered) when is_integer(left),
    do: Decimal.equal?(Decimal.new(left), right)

  # Early TCK documents sometimes omit xsi:type for boolean result values even
  # when the referenced DMN decision is explicitly typed as boolean.
  defp compare(value, "true", _ordered) when is_boolean(value), do: value
  defp compare(value, "false", _ordered) when is_boolean(value), do: not value
  defp compare("true", value, _ordered) when is_boolean(value), do: value
  defp compare("false", value, _ordered) when is_boolean(value), do: not value

  defp compare(%Date{} = left, %Date{} = right, _ordered),
    do: Date.compare(left, right) == :eq

  defp compare(%Time{} = left, %Time{} = right, _ordered),
    do: Time.compare(left, right) == :eq

  defp compare(%DateTime{} = left, %DateTime{} = right, _ordered),
    do: DateTime.compare(left, right) == :eq

  defp compare(%NaiveDateTime{} = left, %NaiveDateTime{} = right, _ordered),
    do: NaiveDateTime.compare(left, right) == :eq

  defp compare(%FeelTime{} = left, %FeelTime{} = right, _ordered) do
    left.hour == right.hour and left.minute == right.minute and left.zone == right.zone and
      Decimal.equal?(left.second, right.second)
  end

  defp compare(%FeelDateTime{} = left, %FeelDateTime{} = right, ordered),
    do: compare(left.date, right.date, ordered) and compare(left.time, right.time, ordered)

  defp compare(%Duration{} = left, %Duration{} = right, _ordered),
    do:
      left.kind == right.kind and left.months == right.months and
        numeric_equal?(left.seconds, right.seconds)

  defp compare(left, right, true) when is_list(left) and is_list(right) do
    length(left) == length(right) and
      Enum.zip(left, right) |> Enum.all?(fn {l, r} -> compare(l, r, true) end)
  end

  defp compare(left, right, false) when is_list(left) and is_list(right) do
    unordered_equal?(left, right)
  end

  defp compare(left, right, ordered)
       when is_map(left) and is_map(right) and not is_struct(left) and not is_struct(right) do
    Map.keys(left) |> Enum.sort() == Map.keys(right) |> Enum.sort() and
      Enum.all?(left, fn {k, v} -> compare(v, Map.get(right, k), ordered) end)
  end

  defp compare(left, right, _ordered), do: left == right

  defp numeric_equal?(%Decimal{} = left, %Decimal{} = right), do: Decimal.equal?(left, right)
  defp numeric_equal?(%Decimal{} = left, right), do: Decimal.equal?(left, Decimal.new(right))
  defp numeric_equal?(left, %Decimal{} = right), do: Decimal.equal?(Decimal.new(left), right)
  defp numeric_equal?(left, right), do: left == right

  defp decimal_equal?(left, right) do
    if Decimal.equal?(left, right) do
      true
    else
      difference = left |> Decimal.sub(right) |> Decimal.abs()

      scale =
        Enum.reduce([Decimal.abs(left), Decimal.abs(right), Decimal.new(1)], fn value, current ->
          if Decimal.compare(value, current) == :gt, do: value, else: current
        end)

      Decimal.compare(difference, Decimal.mult(scale, Decimal.new("1e-12"))) != :gt
    end
  end

  defp unordered_equal?(left, right) when length(left) != length(right), do: false

  defp unordered_equal?([], []), do: true

  defp unordered_equal?([value | rest], right) do
    case Enum.find_index(right, &compare(value, &1, true)) do
      nil -> false
      index -> unordered_equal?(rest, List.delete_at(right, index))
    end
  end
end
