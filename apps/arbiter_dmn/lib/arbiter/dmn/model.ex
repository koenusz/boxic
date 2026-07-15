defmodule Arbiter.DMN.Model do
  @moduledoc """
  Namespace-independent, normalized representation of a DMN definitions document.

  XML nodes are converted into explicit domain values at the loading boundary so
  validation and execution do not depend on `:xmerl` records or namespace prefixes.
  Maps are keyed by DMN identifiers; duplicate identifiers are retained as loader
  issues instead of being silently overwritten.
  """

  alias Arbiter.DMN.Model.Definitions

  defstruct [:definitions, decisions: %{}, input_data: %{}, issues: []]

  @type issue :: term()
  @type t :: %__MODULE__{
          definitions: Definitions.t(),
          decisions: %{optional(String.t()) => Arbiter.DMN.Model.Decision.t()},
          input_data: %{optional(String.t()) => Arbiter.DMN.Model.InputData.t()},
          issues: [issue()]
        }
end

defmodule Arbiter.DMN.Model.Definitions do
  @moduledoc "Normalized DMN definitions metadata."
  defstruct [:id, :name, :namespace, :expression_language, :type_language]

  @type t :: %__MODULE__{
          id: String.t() | nil,
          name: String.t() | nil,
          namespace: String.t() | nil,
          expression_language: String.t() | nil,
          type_language: String.t() | nil
        }
end

defmodule Arbiter.DMN.Model.Variable do
  @moduledoc "Normalized variable declaration attached to input data or a decision."
  defstruct [:id, :name, :type_ref]
  @type t :: %__MODULE__{id: String.t() | nil, name: String.t() | nil, type_ref: String.t() | nil}
end

defmodule Arbiter.DMN.Model.InputData do
  @moduledoc "Normalized DMN input-data node."
  defstruct [:id, :name, :variable]

  @type t :: %__MODULE__{
          id: String.t() | nil,
          name: String.t() | nil,
          variable: Arbiter.DMN.Model.Variable.t() | nil
        }
end

defmodule Arbiter.DMN.Model.InformationRequirement do
  @moduledoc "Normalized decision or input dependency reference."
  defstruct [:kind, :href]
  @type kind :: :input_data | :decision
  @type t :: %__MODULE__{kind: kind() | nil, href: String.t() | nil}
end

defmodule Arbiter.DMN.Model.LiteralExpression do
  @moduledoc "Normalized FEEL literal expression."
  defstruct [:id, :text, :type_ref, expression_language: "feel"]

  @type t :: %__MODULE__{
          id: String.t() | nil,
          text: String.t() | nil,
          type_ref: String.t() | nil,
          expression_language: String.t() | nil
        }
end

defmodule Arbiter.DMN.Model.Decision do
  @moduledoc "Normalized DMN decision and its dependency declarations."
  defstruct [:id, :name, :variable, :expression, requirements: []]

  @type expression :: Arbiter.DMN.Model.LiteralExpression.t() | {:unsupported, String.t()} | nil
  @type t :: %__MODULE__{
          id: String.t() | nil,
          name: String.t() | nil,
          variable: Arbiter.DMN.Model.Variable.t() | nil,
          expression: expression(),
          requirements: [Arbiter.DMN.Model.InformationRequirement.t()]
        }
end
