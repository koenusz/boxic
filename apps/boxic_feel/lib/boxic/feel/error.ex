defmodule Boxic.FEEL.Error do
  @moduledoc """
  Structured FEEL evaluation error.
  """

  @enforce_keys [:code, :message]
  defstruct [:code, :message]

  @type t :: %__MODULE__{code: atom(), message: String.t()}

  @spec new(atom(), String.t()) :: t()
  def new(code, message) when is_atom(code) and is_binary(message) do
    %__MODULE__{code: code, message: message}
  end
end
