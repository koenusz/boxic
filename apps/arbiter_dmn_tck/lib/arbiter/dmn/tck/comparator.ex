defmodule Arbiter.DMN.TCK.Comparator do
  @moduledoc """
  Semantic comparator for expected and actual values.
  """

  @spec semantic_equal?(term(), term()) :: boolean()
  def semantic_equal?(%Decimal{} = left, %Decimal{} = right), do: Decimal.equal?(left, right)
  def semantic_equal?(%Date{} = left, %Date{} = right), do: Date.compare(left, right) == :eq
  def semantic_equal?(%Time{} = left, %Time{} = right), do: Time.compare(left, right) == :eq

  def semantic_equal?(%DateTime{} = left, %DateTime{} = right),
    do: DateTime.compare(left, right) == :eq

  def semantic_equal?(left, right) when is_list(left) and is_list(right) do
    length(left) == length(right) and
      Enum.zip(left, right) |> Enum.all?(fn {l, r} -> semantic_equal?(l, r) end)
  end

  def semantic_equal?(left, right)
      when is_map(left) and is_map(right) and not is_struct(left) and not is_struct(right) do
    Map.keys(left) |> Enum.sort() == Map.keys(right) |> Enum.sort() and
      Enum.all?(left, fn {k, v} -> semantic_equal?(v, Map.get(right, k)) end)
  end

  def semantic_equal?(left, right), do: left == right
end
