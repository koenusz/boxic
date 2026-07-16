defmodule Boxic.FEEL.Function do
  @moduledoc """
  FEEL user-defined function closure.
  """

  defstruct [:params, :body, :closure]

  @type t :: %__MODULE__{
          params: [{String.t(), String.t() | nil}],
          body: term(),
          closure: map()
        }
end
