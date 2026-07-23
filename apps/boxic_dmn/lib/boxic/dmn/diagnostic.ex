defmodule Boxic.DMN.Diagnostic do
  @moduledoc """
  A stable diagnostic returned by DMN validation, preflight, and execution.

  `to_map/1` converts the diagnostic into a persistence-safe representation for
  downstream consumers. Boxic intentionally does not assign lifecycle severity.
  """

  @enforce_keys [:code, :category, :path, :message]
  defstruct [
    :code,
    :category,
    :path,
    :message,
    :specification,
    :clause,
    :source_profile,
    :cause,
    :details
  ]

  @type category ::
          :xml_schema
          | :dmn_model
          | :feel
          | :executable_profile
          | :import
          | :serialization
          | :evaluation_preflight
          | :evaluation
  @type path_segment :: atom() | String.t() | non_neg_integer()
  @type json_scalar :: nil | boolean() | number() | String.t()
  @type json_value :: json_scalar() | [json_value()] | %{optional(String.t()) => json_value()}
  @type t :: %__MODULE__{
          code: atom(),
          category: category(),
          path: [path_segment()],
          message: String.t(),
          specification: String.t() | nil,
          clause: String.t() | nil,
          source_profile: term(),
          cause: term(),
          details: term()
        }

  @doc "Returns a stable map containing only JSON-compatible values."
  @spec to_map(t()) :: %{String.t() => json_value()}
  def to_map(%__MODULE__{} = diagnostic) do
    %{
      "code" => Atom.to_string(diagnostic.code),
      "category" => Atom.to_string(diagnostic.category),
      "path" => Enum.map(diagnostic.path, &path_segment/1),
      "message" => diagnostic.message,
      "specification" => diagnostic.specification,
      "clause" => diagnostic.clause,
      "source_profile" => safe_value(diagnostic.source_profile),
      "cause" => safe_value(diagnostic.cause),
      "details" => safe_value(diagnostic.details)
    }
  end

  defp path_segment(value) when is_atom(value), do: Atom.to_string(value)
  defp path_segment(value) when is_binary(value) or is_integer(value), do: value

  defp safe_value(nil), do: nil

  defp safe_value(value)
       when is_binary(value) or is_boolean(value) or is_integer(value) or is_float(value),
       do: value

  defp safe_value(value) when is_atom(value), do: Atom.to_string(value)
  defp safe_value(value) when is_list(value), do: Enum.map(value, &safe_value/1)

  defp safe_value(%Boxic.FEEL.Error{} = error) do
    %{
      "type" => "feel_error",
      "code" => Atom.to_string(error.code),
      "message" => error.message
    }
  end

  defp safe_value(value) when is_map(value) and not is_struct(value) do
    Map.new(value, fn {key, entry} -> {to_string(key), safe_value(entry)} end)
  end

  defp safe_value(value) when is_tuple(value), do: value |> Tuple.to_list() |> safe_value()
  defp safe_value(value), do: inspect(value, limit: 20, printable_limit: 200)
end
