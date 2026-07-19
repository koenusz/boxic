defmodule Boxic.DMN.XML.Element do
  @moduledoc false
  defstruct [:name, attrs: [], children: []]

  @type child :: t() | {:text, String.t()}
  @type t :: %__MODULE__{name: String.t(), attrs: [{String.t(), String.t()}], children: [child()]}
end
