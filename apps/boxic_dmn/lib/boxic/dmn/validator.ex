defmodule Boxic.DMN.Validator do
  @moduledoc false

  defdelegate validate(model), to: Boxic.DMN.Engine
end
