defmodule Arbiter.DMN.TCK.Reporter do
  @moduledoc """
  Generates versioned, machine-readable TCK reports.
  """

  alias Arbiter.FEEL.Duration
  alias Arbiter.FEEL.DateTime, as: FeelDateTime
  alias Arbiter.FEEL.Time, as: FeelTime

  @schema_version "1.0"
  @formats [:csv, :json, :both]

  @spec write(list(), map(), keyword()) :: :ok
  def write(results, summary, opts) do
    if report_path = Keyword.get(opts, :report) do
      format = normalize_format(Keyword.get(opts, :format, :both))
      metadata = metadata(opts)

      report_path
      |> report_paths(format)
      |> Enum.each(fn
        {:csv, path} -> write_csv(path, metadata, summary, results)
        {:json, path} -> write_json(path, metadata, summary, results)
      end)
    end

    :ok
  end

  @spec supported_formats() :: [atom()]
  def supported_formats, do: @formats

  @doc "Converts a result value or error into stable JSON-compatible data."
  @spec encode_value(term()) :: term()
  def encode_value(nil), do: nil

  def encode_value(value) when is_binary(value) or is_boolean(value) or is_number(value),
    do: value

  def encode_value(%Decimal{} = value),
    do: %{"type" => "number", "value" => Decimal.to_string(value, :normal)}

  def encode_value(%Date{} = value),
    do: %{"type" => "date", "value" => Date.to_iso8601(value)}

  def encode_value(%Time{} = value),
    do: %{"type" => "time", "value" => Time.to_iso8601(value)}

  def encode_value(%DateTime{} = value),
    do: %{"type" => "date_time", "value" => DateTime.to_iso8601(value)}

  def encode_value(%NaiveDateTime{} = value),
    do: %{"type" => "date_time", "value" => NaiveDateTime.to_iso8601(value)}

  def encode_value(%FeelTime{} = value),
    do: %{"type" => "time", "value" => FeelTime.to_string(value)}

  def encode_value(%FeelDateTime{} = value),
    do: %{"type" => "date_time", "value" => FeelDateTime.to_string(value)}

  def encode_value(%Duration{} = value),
    do: %{
      "type" => "duration",
      "kind" => Atom.to_string(value.kind),
      "months" => value.months,
      "seconds" => value.seconds
    }

  def encode_value(%Arbiter.FEEL.Error{} = error),
    do: %{
      "type" => "feel_error",
      "code" => Atom.to_string(error.code),
      "message" => error.message
    }

  def encode_value(%{__exception__: true} = exception),
    do: %{
      "type" => "exception",
      "module" => module_name(exception),
      "message" => Exception.message(exception)
    }

  def encode_value(value) when is_list(value), do: Enum.map(value, &encode_value/1)

  def encode_value(value) when is_map(value) and not is_struct(value) do
    Map.new(value, fn {key, entry} -> {to_string(key), encode_value(entry)} end)
  end

  def encode_value(value) when is_struct(value) do
    %{
      "type" => "struct",
      "module" => module_name(value),
      "fields" => value |> Map.from_struct() |> encode_value()
    }
  end

  def encode_value(value) when is_tuple(value),
    do: %{"type" => "tuple", "items" => value |> Tuple.to_list() |> Enum.map(&encode_value/1)}

  def encode_value(value) when is_atom(value),
    do: %{"type" => "atom", "value" => Atom.to_string(value)}

  def encode_value(value),
    do: %{"type" => "opaque", "encoding" => "erlang_external_term", "value" => encode_term(value)}

  defp metadata(opts) do
    %{
      report_schema_version: @schema_version,
      engine_version: "0.1.0",
      feel_package_version: "0.1.0",
      dmn_package_version: "0.1.0",
      dmn_tck_commit: tck_commit(opts),
      dmn_specification_version: "1.4",
      elixir_version: System.version(),
      otp_version: otp_version(),
      execution_date: DateTime.utc_now() |> DateTime.to_iso8601(),
      suite: Keyword.get(opts, :suite),
      profile: Keyword.get(opts, :profile)
    }
  end

  defp write_csv(path, metadata, summary, results) do
    columns = [
      "report_schema_version",
      "engine_version",
      "feel_package_version",
      "dmn_package_version",
      "dmn_tck_commit",
      "dmn_specification_version",
      "elixir_version",
      "otp_version",
      "execution_date",
      "suite",
      "profile",
      "compatibility_percent",
      "suite_coverage_percent",
      "coverage_percent",
      "group",
      "id",
      "status",
      "decision",
      "expected_error",
      "expected",
      "actual",
      "error",
      "case_file",
      "compliance_level"
    ]

    rows =
      [Enum.join(columns, ",")] ++
        Enum.map(results, fn result ->
          [
            metadata.report_schema_version,
            metadata.engine_version,
            metadata.feel_package_version,
            metadata.dmn_package_version,
            metadata.dmn_tck_commit,
            metadata.dmn_specification_version,
            metadata.elixir_version,
            metadata.otp_version,
            metadata.execution_date,
            metadata.suite,
            metadata.profile,
            summary.compatibility_percent,
            summary.suite_coverage_percent,
            summary.coverage_percent,
            result.case.group,
            result.case.id,
            Atom.to_string(result.status),
            result.case.decision_name,
            result.case.expect_error,
            json_cell(result.case.expected),
            json_cell(result.actual),
            json_cell(result.error),
            result.case.metadata[:case_file],
            result.case.metadata[:compliance_level]
          ]
          |> Enum.map(&csv_escape/1)
          |> Enum.join(",")
        end)

    write_file(path, Enum.join(rows, "\n") <> "\n")
  end

  defp write_json(path, metadata, summary, results) do
    payload = %{
      metadata: metadata,
      summary: summary,
      results: Enum.map(results, &result_payload/1)
    }

    write_file(path, Jason.encode_to_iodata!(payload, pretty: true))
  end

  defp result_payload(result) do
    %{
      group: result.case.group,
      id: result.case.id,
      status: Atom.to_string(result.status),
      decision: result.case.decision_name,
      expected_error: result.case.expect_error,
      expected: encode_value(result.case.expected),
      actual: encode_value(result.actual),
      error: encode_value(result.error),
      case_file: result.case.metadata[:case_file],
      compliance_level: result.case.metadata[:compliance_level]
    }
  end

  defp report_paths(path, :csv), do: [{:csv, path}]
  defp report_paths(path, :json), do: [{:json, path}]

  defp report_paths(path, :both) do
    case Path.extname(path) do
      ".csv" -> [{:csv, path}, {:json, Path.rootname(path) <> ".json"}]
      ".json" -> [{:csv, Path.rootname(path) <> ".csv"}, {:json, path}]
      _ -> [{:csv, path <> ".csv"}, {:json, path <> ".json"}]
    end
  end

  defp normalize_format(value) when value in @formats, do: value
  defp normalize_format(value) when is_binary(value), do: String.to_existing_atom(value)

  defp tck_commit(opts) do
    case Keyword.get(opts, :tck_commit) do
      nil ->
        pin_file = Path.join(File.cwd!(), "vendor/dmn-tck/PINNED_COMMIT")
        if File.exists?(pin_file), do: File.read!(pin_file) |> String.trim(), else: "unknown"

      commit ->
        commit
    end
  end

  defp write_file(path, contents) do
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, contents)
  end

  defp json_cell(value), do: value |> encode_value() |> Jason.encode!()
  defp otp_version, do: :erlang.system_info(:otp_release) |> to_string()
  defp module_name(%module{}), do: module |> Module.split() |> Enum.join(".")
  defp encode_term(value), do: value |> :erlang.term_to_binary() |> Base.encode64()

  defp csv_escape(value) do
    escaped = value |> to_string() |> String.replace("\"", "\"\"")
    "\"#{escaped}\""
  end
end
