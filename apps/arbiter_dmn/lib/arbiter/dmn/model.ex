defmodule Arbiter.DMN.Model do
  @moduledoc """
  Namespace-independent, normalized representation of a DMN definitions document.

  XML nodes are converted into explicit domain values at the loading boundary so
  validation and execution do not depend on `:xmerl` records or namespace prefixes.
  Maps are keyed by DMN identifiers; duplicate identifiers are retained as loader
  issues instead of being silently overwritten.
  """

  alias Arbiter.DMN.Model.Definitions

  defstruct [
    :definitions,
    imports: %{},
    decisions: %{},
    input_data: %{},
    bkms: %{},
    item_definitions: %{},
    decision_services: %{},
    issues: []
  ]

  @type issue :: term()
  @type t :: %__MODULE__{
          definitions: Definitions.t(),
          imports: %{optional(String.t()) => String.t()},
          decisions: %{optional(String.t()) => Arbiter.DMN.Model.Decision.t()},
          input_data: %{optional(String.t()) => Arbiter.DMN.Model.InputData.t()},
          bkms: map(),
          item_definitions: map(),
          decision_services: map(),
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
  @type kind :: :input_data | :decision | :knowledge
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

  @type expression ::
          Arbiter.DMN.Model.LiteralExpression.t()
          | Arbiter.DMN.Model.DecisionTable.t()
          | Arbiter.DMN.Model.ContextExpression.t()
          | Arbiter.DMN.Model.Invocation.t()
          | Arbiter.DMN.Model.FunctionDefinition.t()
          | Arbiter.DMN.Model.Relation.t()
          | {:unsupported, String.t()}
          | nil
  @type t :: %__MODULE__{
          id: String.t() | nil,
          name: String.t() | nil,
          variable: Arbiter.DMN.Model.Variable.t() | nil,
          expression: expression(),
          requirements: [Arbiter.DMN.Model.InformationRequirement.t()]
        }
end

defmodule Arbiter.DMN.Model.Relation do
  @moduledoc "Normalized boxed relation: named columns and ordered expression rows."
  defstruct [:id, columns: [], rows: []]
  @type t :: %__MODULE__{}
end

defmodule Arbiter.DMN.Model.ListExpression do
  @moduledoc "Normalized boxed list expression."
  defstruct [:id, items: []]
  @type t :: %__MODULE__{}
end

defmodule Arbiter.DMN.Model.ConditionalExpression do
  @moduledoc "Boxed conditional expression."
  defstruct [:id, :condition, :then_branch, :else_branch]
  @type t :: %__MODULE__{}
end

defmodule Arbiter.DMN.Model.FilterExpression do
  @moduledoc "Boxed filter expression."
  defstruct [:id, :source, :match]
  @type t :: %__MODULE__{}
end

defmodule Arbiter.DMN.Model.IteratorExpression do
  @moduledoc "Boxed for, some, or every expression."
  defstruct [:id, :kind, :variable, :source, :body]
  @type t :: %__MODULE__{}
end

defmodule Arbiter.DMN.Model.RelationColumn do
  @moduledoc "One named column in a boxed relation."
  defstruct [:id, :name, :type_ref]
  @type t :: %__MODULE__{}
end

defmodule Arbiter.DMN.Model.FunctionDefinition do
  @moduledoc "Normalized boxed function definition."
  defstruct [:id, :body, parameters: []]
  @type t :: %__MODULE__{}
end

defmodule Arbiter.DMN.Model.BusinessKnowledgeModel do
  @moduledoc "Normalized callable business knowledge model."
  defstruct [:id, :name, :variable, :expression, parameters: [], requirements: []]
  @type t :: %__MODULE__{}
end

defmodule Arbiter.DMN.Model.Invocation do
  @moduledoc "Normalized DMN invocation and named parameter bindings."
  defstruct [:id, :function, :type_ref, bindings: []]
  @type t :: %__MODULE__{}
end

defmodule Arbiter.DMN.Model.Binding do
  @moduledoc "Named invocation argument expression."
  defstruct [:parameter, :expression]
  @type t :: %__MODULE__{}
end

defmodule Arbiter.DMN.Model.DecisionService do
  @moduledoc "Normalized callable decision service."
  defstruct [:id, :name, :variable, output_decisions: [], input_decisions: [], input_data: []]
  @type t :: %__MODULE__{}
end

defmodule Arbiter.DMN.Model.ItemDefinition do
  @moduledoc "Normalized DMN item definition with recursive components."
  defstruct [:id, :name, :type_ref, :allowed_values, :is_collection, components: []]
  @type t :: %__MODULE__{}
end

defmodule Arbiter.DMN.Model.ItemComponent do
  @moduledoc "Normalized component of a DMN item definition."
  defstruct [:id, :name, :type_ref, :allowed_values, :is_collection, components: []]
  @type t :: %__MODULE__{}
end

defmodule Arbiter.DMN.Model.ContextExpression do
  @moduledoc "Normalized boxed DMN context expression."
  defstruct [:id, entries: []]
  @type t :: %__MODULE__{id: String.t() | nil, entries: [Arbiter.DMN.Model.ContextEntry.t()]}
end

defmodule Arbiter.DMN.Model.ContextEntry do
  @moduledoc "One ordered entry in a boxed DMN context; the final entry may be unnamed."
  defstruct [:id, :variable, :expression]
  @type t :: %__MODULE__{}
end

defmodule Arbiter.DMN.Model.DecisionTable do
  @moduledoc "Normalized decision table independent of XML layout."
  defstruct [:id, :hit_policy, :aggregation, :output_label, inputs: [], outputs: [], rules: []]

  @type t :: %__MODULE__{
          id: String.t() | nil,
          hit_policy: String.t() | nil,
          aggregation: String.t() | nil,
          output_label: String.t() | nil,
          inputs: [Arbiter.DMN.Model.InputClause.t()],
          outputs: [Arbiter.DMN.Model.OutputClause.t()],
          rules: [Arbiter.DMN.Model.DecisionRule.t()]
        }
end

defmodule Arbiter.DMN.Model.InputClause do
  @moduledoc "Normalized decision-table input clause."
  defstruct [:id, :label, :expression, :type_ref, :allowed_values]
  @type t :: %__MODULE__{}
end

defmodule Arbiter.DMN.Model.OutputClause do
  @moduledoc "Normalized decision-table output clause."
  defstruct [:id, :name, :label, :type_ref, :allowed_values, :default_output]
  @type t :: %__MODULE__{}
end

defmodule Arbiter.DMN.Model.DecisionRule do
  @moduledoc "Normalized decision-table rule with ordered input and output entries."
  defstruct [:id, input_entries: [], output_entries: []]

  @type t :: %__MODULE__{
          id: String.t() | nil,
          input_entries: [String.t()],
          output_entries: [String.t()]
        }
end
