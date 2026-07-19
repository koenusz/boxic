defmodule Boxic.DMN.TCK.WriterAudit do
  @moduledoc """
  Audits vendored TCK models against the pinned Boxic XML writer profile.

  Models outside the pinned DMN version or containing XML content that Boxic
  cannot preserve are reported as rejected. Load, encode, or reload failures
  are reported separately and are never counted as supported.
  """

  alias Boxic.DMN.TCK
  alias Boxic.DMN.TCK.Loader

  @type result :: %{
          path: Path.t(),
          status: :supported | :rejected | :failed,
          reason: term()
        }

  @spec run(keyword()) :: %{results: [result()], summary: map()}
  def run(opts \\ []) do
    paths =
      opts
      |> Loader.load_all()
      |> select_cases(opts)
      |> Enum.map(& &1.model_path)
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()
      |> Enum.sort()

    audit_paths(paths)
  end

  @spec audit_paths([Path.t()]) :: %{results: [result()], summary: map()}
  def audit_paths(paths) do
    results = Enum.map(paths, &audit_path/1)
    counts = Enum.frequencies_by(results, & &1.status)

    %{
      results: results,
      summary: %{
        total: length(results),
        supported: Map.get(counts, :supported, 0),
        rejected: Map.get(counts, :rejected, 0),
        failed: Map.get(counts, :failed, 0)
      }
    }
  end

  defp select_cases(cases, opts) do
    case Keyword.get(opts, :profile) do
      nil ->
        cases

      "implemented" ->
        groups = TCK.profile_groups("dmn", "implemented")
        Enum.filter(cases, &(&1.group in groups))

      profile ->
        raise ArgumentError, "unknown writer audit profile: #{profile}"
    end
  end

  defp audit_path(path) do
    with {:ok, xml} <- File.read(path),
         {:ok, model} <- Boxic.DMN.load_xml(xml) do
      case Boxic.DMN.validate_serializable(model) do
        :ok ->
          encode_and_reload(path, model)

        {:error, errors} ->
          %{path: path, status: :rejected, reason: errors}
      end
    else
      {:error, reason} -> %{path: path, status: :failed, reason: reason}
    end
  rescue
    exception ->
      %{path: path, status: :failed, reason: {exception.__struct__, Exception.message(exception)}}
  end

  defp encode_and_reload(path, model) do
    with {:ok, xml} <- Boxic.DMN.encode_xml(model),
         {:ok, reloaded} <- Boxic.DMN.load_xml(xml),
         :ok <- Boxic.DMN.validate(reloaded),
         {:ok, second_xml} <- Boxic.DMN.encode_xml(reloaded),
         true <- xml == second_xml do
      %{path: path, status: :supported, reason: nil}
    else
      {:error, reason} -> %{path: path, status: :failed, reason: reason}
      false -> %{path: path, status: :failed, reason: :non_idempotent_output}
    end
  end
end
