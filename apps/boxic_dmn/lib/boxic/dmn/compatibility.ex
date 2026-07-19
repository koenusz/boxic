defmodule Boxic.DMN.Compatibility do
  @moduledoc """
  The DMN compatibility profile supported by this Boxic release.

  Boxic targets DMN 1.4 for validation, evaluation, and XML encoding. Loading
  remains tolerant of legacy and namespace-less documents so callers can
  inspect them, but their source profile is retained on the normalized model.
  """

  @dmn_1_4_model_namespace "https://www.omg.org/spec/DMN/20211108/MODEL/"
  @dmn_1_3_model_namespace "https://www.omg.org/spec/DMN/20191111/MODEL/"
  @feel_namespace "https://www.omg.org/spec/DMN/20211108/FEEL/"
  @dmndi_namespace "https://www.omg.org/spec/DMN/20191111/DMNDI/"
  @dc_namespace "http://www.omg.org/spec/DMN/20180521/DC/"
  @di_namespace "http://www.omg.org/spec/DMN/20180521/DI/"
  @tck_revision "0dbcaf9b98bc3af4e36d44a7aed95e9e85703a13"

  @type source_profile :: :dmn_1_4 | :dmn_1_3 | :unqualified | {:unknown, String.t()}

  @type profile :: %{
          version: String.t(),
          source_profile: :dmn_1_4,
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
      version: "1.4",
      source_profile: :dmn_1_4,
      model_namespace: @dmn_1_4_model_namespace,
      feel_namespace: @feel_namespace,
      dmndi_namespace: @dmndi_namespace,
      dc_namespace: @dc_namespace,
      di_namespace: @di_namespace,
      schema: "DMN14.xsd",
      tck_revision: @tck_revision
    }
  end

  @doc "Classifies the namespace used by a loaded definitions element."
  @spec source_profile(String.t() | nil) :: source_profile()
  def source_profile(nil), do: :unqualified
  def source_profile(""), do: :unqualified
  def source_profile(@dmn_1_4_model_namespace), do: :dmn_1_4
  def source_profile(@dmn_1_3_model_namespace), do: :dmn_1_3
  def source_profile(namespace) when is_binary(namespace), do: {:unknown, namespace}
end
