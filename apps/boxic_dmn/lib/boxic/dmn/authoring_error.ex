defmodule Boxic.DMN.AuthoringError do
  @moduledoc "A structured error returned by immutable DMN authoring operations."

  @enforce_keys [:code, :path, :message]
  defstruct [:code, :path, :message, :details]

  @type t :: %__MODULE__{
          code: atom(),
          path: [atom() | String.t() | non_neg_integer()],
          message: String.t(),
          details: term()
        }
end
