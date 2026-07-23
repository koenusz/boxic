defmodule Boxic.Scripts.GenerateWriterAudit do
  alias Boxic.DMN.Compatibility
  alias Boxic.DMN.Diagnostic
  alias Boxic.DMN.SerializationError
  alias Boxic.DMN.TCK.WriterAudit

  def run([output_path]) do
    audit = WriterAudit.run(profile: "implemented")
    profile = Compatibility.pinned_profile()

    payload = %{
      metadata: %{
        report_schema_version: "1.0",
        dmn_package_version: app_version(:boxic_dmn),
        dmn_specification_version: profile.version,
        dmn_model_namespace: profile.model_namespace,
        feel_namespace: profile.feel_namespace,
        dmn_tck_commit: profile.tck_revision,
        source_commit: source_commit(),
        source_dirty: source_dirty?()
      },
      summary: audit.summary,
      results:
        Enum.map(audit.results, fn result ->
          %{
            path: Path.relative_to_cwd(result.path),
            status: result.status,
            reason: safe(result.reason)
          }
        end)
    }

    File.write!(output_path, Jason.encode_to_iodata!(payload, pretty: true))
  end

  def run(_args) do
    raise "usage: mix run scripts/generate_writer_audit.exs -- OUTPUT.json"
  end

  defp app_version(app), do: app |> Application.spec(:vsn) |> to_string()

  defp source_commit do
    case System.cmd("git", ["rev-parse", "HEAD"], stderr_to_stdout: true) do
      {commit, 0} -> String.trim(commit)
      _error -> "unknown"
    end
  end

  defp source_dirty? do
    case System.cmd("git", ["status", "--porcelain"], stderr_to_stdout: true) do
      {"", 0} -> false
      {_status, 0} -> true
      _error -> nil
    end
  end

  defp safe(%Diagnostic{} = diagnostic), do: Diagnostic.to_map(diagnostic)

  defp safe(%SerializationError{} = error) do
    %{
      code: error.code,
      path: error.path,
      message: error.message,
      details: safe(error.details)
    }
  end

  defp safe(value) when is_map(value) and not is_struct(value),
    do: Map.new(value, fn {key, entry} -> {to_string(key), safe(entry)} end)

  defp safe(nil), do: nil
  defp safe(value) when is_list(value), do: Enum.map(value, &safe/1)
  defp safe(value) when is_tuple(value), do: value |> Tuple.to_list() |> safe()
  defp safe(value) when is_atom(value), do: Atom.to_string(value)
  defp safe(value) when is_binary(value) or is_number(value) or is_boolean(value), do: value
  defp safe(value), do: inspect(value, limit: 20, printable_limit: 200)
end

Boxic.Scripts.GenerateWriterAudit.run(System.argv())
