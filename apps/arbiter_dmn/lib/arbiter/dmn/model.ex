defmodule Arbiter.DMN.Model do
  @moduledoc """
  Normalized DMN model representation for Iteration A.
  """

  defstruct [
    :namespace,
    :name,
    :definitions,
    :decisions,
    :input_data,
    :bkms,
    :item_definitions
  ]

  @type t :: %__MODULE__{
          namespace: String.t() | nil,
          name: String.t() | nil,
          definitions: map(),
          decisions: %{optional(String.t()) => String.t()},
          input_data: map(),
          bkms: map(),
          item_definitions: map()
        }
end
