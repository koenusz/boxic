defmodule Arbiter.DMN.TCK.Comparator do
  @moduledoc """
  Semantic comparator for expected and actual values.

  Lists are ordered by default. Callers comparing a TCK result whose semantics
  are explicitly unordered can pass `ordered: false`; duplicate values are
  still significant.
  """

  alias Arbiter.FEEL.Duration

  @spec semantic_equal?(term(), term(), keyword()) :: boolean()
  def semantic_equal?(left, right, opts \\ []) do
    compare(left, right, Keyword.get(opts, :ordered, true))
  end

  defp compare(%Decimal{} = left, %Decimal{} = right, _ordered),
    do: Decimal.equal?(left, right)

  defp compare(%Decimal{} = left, right, _ordered) when is_integer(right),
    do: Decimal.equal?(left, Decimal.new(right))

  defp compare(left, %Decimal{} = right, _ordered) when is_integer(left),
    do: Decimal.equal?(Decimal.new(left), right)

  defp compare(%Date{} = left, %Date{} = right, _ordered),
    do: Date.compare(left, right) == :eq

  defp compare(%Time{} = left, %Time{} = right, _ordered),
    do: Time.compare(left, right) == :eq

  defp compare(%DateTime{} = left, %DateTime{} = right, _ordered),
    do: DateTime.compare(left, right) == :eq

  defp compare(%Duration{} = left, %Duration{} = right, _ordered),
    do: left.months == right.months and left.seconds == right.seconds

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

  defp unordered_equal?(left, right) when length(left) != length(right), do: false

  defp unordered_equal?([], []), do: true

  defp unordered_equal?([value | rest], right) do
    case Enum.find_index(right, &compare(value, &1, true)) do
      nil -> false
      index -> unordered_equal?(rest, List.delete_at(right, index))
    end
  end
end
