defmodule Arbiter.DMN.TCK.Case do
  @moduledoc """
  Normalized TCK test case model.
  """

  defstruct [
    :group,
    :id,
    :labels,
    :model_path,
    :decision_name,
    :inputs,
    :expected,
    :metadata
  ]

  @type t :: %__MODULE__{
          group: String.t(),
          id: String.t(),
          labels: [String.t()],
          model_path: String.t(),
          decision_name: String.t(),
          inputs: map(),
          expected: term(),
          metadata: map()
        }
end
