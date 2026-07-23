defmodule Boxic.DMN.Model do
  @moduledoc """
  Namespace-independent, normalized representation of a DMN definitions document.

  XML nodes are converted into explicit domain values at the loading boundary so
  validation and execution do not depend on `:xmerl` records or namespace prefixes.
  Maps are keyed by DMN identifiers; duplicate identifiers are retained as loader
  issues instead of being silently overwritten.
  """

  alias Boxic.DMN.Model.Definitions

  @typedoc "Any normalized expression supported by the DMN evaluator."
  @type expression ::
          Boxic.DMN.Model.LiteralExpression.t()
          | Boxic.DMN.Model.DecisionTable.t()
          | Boxic.DMN.Model.ContextExpression.t()
          | Boxic.DMN.Model.Invocation.t()
          | Boxic.DMN.Model.FunctionDefinition.t()
          | Boxic.DMN.Model.Relation.t()
          | Boxic.DMN.Model.ListExpression.t()
          | Boxic.DMN.Model.ConditionalExpression.t()
          | Boxic.DMN.Model.FilterExpression.t()
          | Boxic.DMN.Model.IteratorExpression.t()
          | {:unsupported, String.t()}
          | nil

  defstruct [
    :definitions,
    :source_profile,
    imports: %{},
    decisions: %{},
    input_data: %{},
    bkms: %{},
    item_definitions: %{},
    decision_services: %{},
    serialization_fidelity: :complete,
    issues: []
  ]

  @type issue ::
          {atom(), term()}
          | {atom(), term(), term()}
          | {atom(), term(), term(), term()}
  @type t :: %__MODULE__{
          definitions: Definitions.t(),
          source_profile: Boxic.DMN.Compatibility.source_profile() | nil,
          imports: %{optional(String.t()) => Boxic.DMN.Model.Import.t()},
          decisions: %{optional(String.t()) => Boxic.DMN.Model.Decision.t()},
          input_data: %{optional(String.t()) => Boxic.DMN.Model.InputData.t()},
          bkms: map(),
          item_definitions: map(),
          decision_services: map(),
          serialization_fidelity: :complete | {:lossy, [term()]},
          issues: [issue()]
        }
end

defmodule Boxic.DMN.Model.Import do
  @moduledoc "Normalized DMN import declaration."
  defstruct [:name, :namespace, :location_uri, :import_type]

  @type t :: %__MODULE__{
          name: String.t() | nil,
          namespace: String.t() | nil,
          location_uri: String.t() | nil,
          import_type: String.t() | nil
        }
end

defmodule Boxic.DMN.Model.Definitions do
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

defmodule Boxic.DMN.Model.Variable do
  @moduledoc "Normalized variable declaration attached to input data or a decision."
  defstruct [:id, :name, :type_ref]
  @type t :: %__MODULE__{id: String.t() | nil, name: String.t() | nil, type_ref: String.t() | nil}
end

defmodule Boxic.DMN.Model.InputData do
  @moduledoc "Normalized DMN input-data node."
  defstruct [:id, :name, :variable]

  @type t :: %__MODULE__{
          id: String.t() | nil,
          name: String.t() | nil,
          variable: Boxic.DMN.Model.Variable.t() | nil
        }
end

defmodule Boxic.DMN.Model.InformationRequirement do
  @moduledoc "Normalized decision or input dependency reference."
  defstruct [:kind, :href]
  @type kind :: :input_data | :decision | :knowledge
  @type t :: %__MODULE__{kind: kind() | nil, href: String.t() | nil}
end

defmodule Boxic.DMN.Model.LiteralExpression do
  @moduledoc "Normalized FEEL literal expression."
  defstruct [:id, :text, :type_ref, :expression_language]

  @type t :: %__MODULE__{
          id: String.t() | nil,
          text: String.t() | nil,
          type_ref: String.t() | nil,
          expression_language: String.t() | nil
        }
end

defmodule Boxic.DMN.Model.Decision do
  @moduledoc "Normalized DMN decision and its dependency declarations."
  defstruct [:id, :name, :variable, :expression, requirements: []]

  @type expression ::
          Boxic.DMN.Model.LiteralExpression.t()
          | Boxic.DMN.Model.DecisionTable.t()
          | Boxic.DMN.Model.ContextExpression.t()
          | Boxic.DMN.Model.Invocation.t()
          | Boxic.DMN.Model.FunctionDefinition.t()
          | Boxic.DMN.Model.Relation.t()
          | {:unsupported, String.t()}
          | nil
  @type t :: %__MODULE__{
          id: String.t() | nil,
          name: String.t() | nil,
          variable: Boxic.DMN.Model.Variable.t() | nil,
          expression: expression(),
          requirements: [Boxic.DMN.Model.InformationRequirement.t()]
        }
end

defmodule Boxic.DMN.Model.Relation do
  @moduledoc "Normalized boxed relation: named columns and ordered expression rows."
  defstruct [:id, columns: [], rows: []]

  @type t :: %__MODULE__{
          id: String.t() | nil,
          columns: [Boxic.DMN.Model.RelationColumn.t()],
          rows: [[Boxic.DMN.Model.expression()]]
        }
end

defmodule Boxic.DMN.Model.ListExpression do
  @moduledoc "Normalized boxed list expression."
  defstruct [:id, items: []]
  @type t :: %__MODULE__{id: String.t() | nil, items: [Boxic.DMN.Model.expression()]}
end

defmodule Boxic.DMN.Model.ConditionalExpression do
  @moduledoc "Boxed conditional expression."
  defstruct [:id, :condition, :then_branch, :else_branch]

  @type t :: %__MODULE__{
          id: String.t() | nil,
          condition: Boxic.DMN.Model.expression(),
          then_branch: Boxic.DMN.Model.expression(),
          else_branch: Boxic.DMN.Model.expression()
        }
end

defmodule Boxic.DMN.Model.FilterExpression do
  @moduledoc "Boxed filter expression."
  defstruct [:id, :source, :match]

  @type t :: %__MODULE__{
          id: String.t() | nil,
          source: Boxic.DMN.Model.expression(),
          match: Boxic.DMN.Model.expression()
        }
end

defmodule Boxic.DMN.Model.IteratorExpression do
  @moduledoc "Boxed for, some, or every expression."
  defstruct [:id, :kind, :variable, :source, :body]

  @type t :: %__MODULE__{
          id: String.t() | nil,
          kind: :for | :some | :every | nil,
          variable: Boxic.DMN.Model.Variable.t() | nil,
          source: Boxic.DMN.Model.expression(),
          body: Boxic.DMN.Model.expression()
        }
end

defmodule Boxic.DMN.Model.RelationColumn do
  @moduledoc "One named column in a boxed relation."
  defstruct [:id, :name, :type_ref]

  @type t :: %__MODULE__{
          id: String.t() | nil,
          name: String.t() | nil,
          type_ref: String.t() | nil
        }
end

defmodule Boxic.DMN.Model.FunctionDefinition do
  @moduledoc "Normalized boxed function definition."
  defstruct [:id, :body, parameters: []]

  @type t :: %__MODULE__{
          id: String.t() | nil,
          body: Boxic.DMN.Model.expression(),
          parameters: [Boxic.DMN.Model.Variable.t()]
        }
end

defmodule Boxic.DMN.Model.BusinessKnowledgeModel do
  @moduledoc "Normalized callable business knowledge model."
  defstruct [:id, :name, :variable, :expression, parameters: [], requirements: []]

  @type t :: %__MODULE__{
          id: String.t() | nil,
          name: String.t() | nil,
          variable: Boxic.DMN.Model.Variable.t() | nil,
          expression: Boxic.DMN.Model.expression(),
          parameters: [Boxic.DMN.Model.Variable.t()],
          requirements: [Boxic.DMN.Model.InformationRequirement.t()]
        }
end

defmodule Boxic.DMN.Model.Invocation do
  @moduledoc "Normalized DMN invocation and named parameter bindings."
  defstruct [:id, :function, :type_ref, bindings: []]

  @type t :: %__MODULE__{
          id: String.t() | nil,
          function: Boxic.DMN.Model.expression(),
          type_ref: String.t() | nil,
          bindings: [Boxic.DMN.Model.Binding.t()]
        }
end

defmodule Boxic.DMN.Model.Binding do
  @moduledoc "Named invocation argument expression."
  defstruct [:parameter, :expression]

  @type t :: %__MODULE__{
          parameter: String.t() | nil,
          expression: Boxic.DMN.Model.expression()
        }
end

defmodule Boxic.DMN.Model.DecisionService do
  @moduledoc "Normalized callable decision service."
  defstruct [:id, :name, :variable, output_decisions: [], input_decisions: [], input_data: []]

  @type t :: %__MODULE__{
          id: String.t() | nil,
          name: String.t() | nil,
          variable: Boxic.DMN.Model.Variable.t() | nil,
          output_decisions: [String.t()],
          input_decisions: [String.t()],
          input_data: [String.t()]
        }
end

defmodule Boxic.DMN.Model.ItemDefinition do
  @moduledoc "Normalized DMN item definition with recursive components."
  defstruct [:id, :name, :type_ref, :allowed_values, :is_collection, components: []]

  @type t :: %__MODULE__{
          id: String.t() | nil,
          name: String.t() | nil,
          type_ref: String.t() | nil,
          allowed_values: String.t() | nil,
          is_collection: boolean() | nil,
          components: [Boxic.DMN.Model.ItemComponent.t()]
        }
end

defmodule Boxic.DMN.Model.ItemComponent do
  @moduledoc "Normalized component of a DMN item definition."
  defstruct [:id, :name, :type_ref, :allowed_values, :is_collection, components: []]

  @type t :: %__MODULE__{
          id: String.t() | nil,
          name: String.t() | nil,
          type_ref: String.t() | nil,
          allowed_values: String.t() | nil,
          is_collection: boolean() | nil,
          components: [t()]
        }
end

defmodule Boxic.DMN.Model.ContextExpression do
  @moduledoc "Normalized boxed DMN context expression."
  defstruct [:id, entries: []]
  @type t :: %__MODULE__{id: String.t() | nil, entries: [Boxic.DMN.Model.ContextEntry.t()]}
end

defmodule Boxic.DMN.Model.ContextEntry do
  @moduledoc "One ordered entry in a boxed DMN context; the final entry may be unnamed."
  defstruct [:id, :variable, :expression]

  @type t :: %__MODULE__{
          id: String.t() | nil,
          variable: Boxic.DMN.Model.Variable.t() | nil,
          expression: Boxic.DMN.Model.expression()
        }
end

defmodule Boxic.DMN.Model.DecisionTable do
  @moduledoc "Normalized decision table independent of XML layout."
  defstruct [:id, :hit_policy, :aggregation, :output_label, inputs: [], outputs: [], rules: []]

  @type t :: %__MODULE__{
          id: String.t() | nil,
          hit_policy: String.t() | nil,
          aggregation: String.t() | nil,
          output_label: String.t() | nil,
          inputs: [Boxic.DMN.Model.InputClause.t()],
          outputs: [Boxic.DMN.Model.OutputClause.t()],
          rules: [Boxic.DMN.Model.DecisionRule.t()]
        }
end

defmodule Boxic.DMN.Model.InputClause do
  @moduledoc "Normalized decision-table input clause."
  defstruct [:id, :label, :expression, :type_ref, :allowed_values]

  @type t :: %__MODULE__{
          id: String.t() | nil,
          label: String.t() | nil,
          expression: String.t() | nil,
          type_ref: String.t() | nil,
          allowed_values: String.t() | nil
        }
end

defmodule Boxic.DMN.Model.OutputClause do
  @moduledoc "Normalized decision-table output clause."
  defstruct [:id, :name, :label, :type_ref, :allowed_values, :default_output]

  @type t :: %__MODULE__{
          id: String.t() | nil,
          name: String.t() | nil,
          label: String.t() | nil,
          type_ref: String.t() | nil,
          allowed_values: String.t() | nil,
          default_output: String.t() | nil
        }
end

defmodule Boxic.DMN.Model.DecisionRule do
  @moduledoc "Normalized decision-table rule with ordered input and output entries."
  defstruct [:id, input_entries: [], output_entries: []]

  @type t :: %__MODULE__{
          id: String.t() | nil,
          input_entries: [String.t()],
          output_entries: [String.t()]
        }
end
