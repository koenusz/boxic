defmodule Boxic.FEEL.Semantics do
  @moduledoc false

  @spec equal?(term(), term()) :: boolean()
  def equal?(%Decimal{} = left, %Decimal{} = right), do: Decimal.equal?(left, right)
  def equal?(left, right), do: left == right
end
