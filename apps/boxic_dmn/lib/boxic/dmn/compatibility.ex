defmodule Boxic.DMN.Compatibility do
  @moduledoc """
  The DMN compatibility profile supported by this Boxic release.

  Boxic targets the formally released DMN 1.5 profile for strict loading,
  validation, evaluation, and XML encoding. Inspection remains tolerant of
  older and namespace-less documents, but compatibility with those profiles is
  not part of the executable contract.
  """

  @dmn_1_5_model_namespace "https://www.omg.org/spec/DMN/20230324/MODEL/"
  @dmn_1_4_model_namespace "https://www.omg.org/spec/DMN/20211108/MODEL/"
  @dmn_1_3_model_namespace "https://www.omg.org/spec/DMN/20191111/MODEL/"
  @feel_namespace "https://www.omg.org/spec/DMN/20230324/FEEL/"
  @dmndi_namespace "https://www.omg.org/spec/DMN/20230324/DMNDI/"
  @dc_namespace "http://www.omg.org/spec/DMN/20180521/DC/"
  @di_namespace "http://www.omg.org/spec/DMN/20180521/DI/"
  @tck_revision "a162739daee85fb28e9d3bec2f306505992dae0f"

  @type source_profile ::
          :dmn_1_5 | :dmn_1_4 | :dmn_1_3 | :unqualified | {:unknown, String.t()}

  @type profile :: %{
          version: String.t(),
          source_profile: :dmn_1_5,
          model_namespace: String.t(),
          feel_namespace: String.t(),
          dmndi_namespace: String.t(),
          dc_namespace: String.t(),
          di_namespace: String.t(),
          schema: String.t(),
          tck_revision: String.t()
        }

  @doc "Returns the single DMN profile emitted and evaluated by this release."
  @spec pinned_profile() :: profile()
  def pinned_profile do
    %{
      version: "1.5",
      source_profile: :dmn_1_5,
      model_namespace: @dmn_1_5_model_namespace,
      feel_namespace: @feel_namespace,
      dmndi_namespace: @dmndi_namespace,
      dc_namespace: @dc_namespace,
      di_namespace: @di_namespace,
      schema: "DMN15.xsd",
      tck_revision: @tck_revision
    }
  end

  @doc "Classifies the namespace used by a loaded definitions element."
  @spec source_profile(String.t() | nil) :: source_profile()
  def source_profile(nil), do: :unqualified
  def source_profile(""), do: :unqualified
  def source_profile(@dmn_1_5_model_namespace), do: :dmn_1_5
  def source_profile(@dmn_1_4_model_namespace), do: :dmn_1_4
  def source_profile(@dmn_1_3_model_namespace), do: :dmn_1_3
  def source_profile(namespace) when is_binary(namespace), do: {:unknown, namespace}

  @doc """
  Resolves the effective expression language for a source profile.

  The local declaration takes precedence over the definitions declaration.
  Omission at both levels selects the DMN 1.5 FEEL default. The internal
  `"feel"` marker is accepted for authored normalized models but is never a
  standards namespace emitted by the writer.
  """
  @spec expression_language(source_profile(), String.t() | nil, String.t() | nil) ::
          {:ok, String.t()} | {:error, {:unsupported_expression_language, term()}}
  def expression_language(:dmn_1_5, definitions_declaration, local_declaration) do
    effective = local_declaration || definitions_declaration || @feel_namespace

    if effective in ["feel", @feel_namespace] do
      {:ok, @feel_namespace}
    else
      {:error, {:unsupported_expression_language, effective}}
    end
  end

  def expression_language(source_profile, _definitions_declaration, local_declaration) do
    {:error,
     {:unsupported_expression_language,
      %{source_profile: source_profile, declaration: local_declaration}}}
  end
end
