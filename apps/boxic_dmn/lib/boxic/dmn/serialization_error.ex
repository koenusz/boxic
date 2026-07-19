defmodule Boxic.DMN.SerializationError do
  @moduledoc "A structured error returned while encoding a normalized DMN model."

  @enforce_keys [:code, :path, :message]
  defstruct [:code, :path, :message, :details]

  @type path_segment :: atom() | String.t() | non_neg_integer()
  @type t :: %__MODULE__{
          code: atom(),
          path: [path_segment()],
          message: String.t(),
          details: term()
        }
end
