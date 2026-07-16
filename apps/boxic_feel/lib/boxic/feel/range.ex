defmodule Boxic.FEEL.Range do
  @moduledoc """
  FEEL range value.
  """

  defstruct [:start, :end, :start_inclusive, :end_inclusive]

  @type t :: %__MODULE__{
          start: term(),
          end: term(),
          start_inclusive: boolean(),
          end_inclusive: boolean()
        }
end
