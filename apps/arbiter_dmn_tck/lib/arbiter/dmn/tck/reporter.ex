defmodule Arbiter.DMN.TCK.Reporter do
  @moduledoc """
  Generates machine-readable TCK reports.
  """

  @spec write(list(), map(), keyword()) :: :ok
  def write(results, summary, opts) do
    report_path = Keyword.get(opts, :report)

    if report_path do
      metadata = %{
        engine_version: "0.1.0",
        feel_package_version: "0.1.0",
        dmn_package_version: "0.1.0",
        dmn_tck_commit: tck_commit(opts),
        dmn_specification_version: "1.4",
        elixir_version: System.version(),
        otp_version: otp_version(),
        execution_date: DateTime.utc_now() |> DateTime.to_iso8601()
      }

      write_csv(report_path, results)
      write_json(json_path(report_path), metadata, summary, results)
    end

    :ok
  end

  defp write_csv(path, results) do
    rows =
      ["group,id,status,decision"] ++
        Enum.map(results, fn result ->
          [
            result.case.group,
            result.case.id,
            Atom.to_string(result.status),
            result.case.decision_name
          ]
          |> Enum.map(&csv_escape/1)
          |> Enum.join(",")
        end)

    File.mkdir_p!(Path.dirname(path))
    File.write!(path, Enum.join(rows, "\n") <> "\n")
  end

  defp write_json(path, metadata, summary, results) do
    payload = %{
      metadata: metadata,
      summary: summary,
      results:
        Enum.map(results, fn result ->
          %{
            group: result.case.group,
            id: result.case.id,
            status: result.status,
            decision: result.case.decision_name,
            expected: inspect(result.case.expected),
            actual: inspect(result.actual),
            error: inspect(result.error)
          }
        end)
    }

    File.write!(path, Jason.encode_to_iodata!(payload, pretty: true))
  end

  defp tck_commit(opts) do
    case Keyword.get(opts, :tck_commit) do
      nil ->
        pin_file = Path.join(File.cwd!(), "vendor/dmn-tck/PINNED_COMMIT")
        if File.exists?(pin_file), do: File.read!(pin_file) |> String.trim(), else: "unknown"

      commit ->
        commit
    end
  end

  defp otp_version do
    :erlang.system_info(:otp_release) |> to_string()
  end

  defp json_path(csv_path), do: Path.rootname(csv_path) <> ".json"

  defp csv_escape(value) do
    escaped = value |> to_string() |> String.replace("\"", "\"\"")
    "\"#{escaped}\""
  end
end
