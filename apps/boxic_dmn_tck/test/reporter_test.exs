defmodule Boxic.DMN.TCK.ReporterTest do
  use ExUnit.Case

  alias Boxic.DMN.TCK.Case
  alias Boxic.DMN.TCK.Reporter
  alias Boxic.FEEL.Duration

  test "JSON report has versioned metadata, metrics, and typed values" do
    root = temporary_directory()
    path = Path.join(root, "report.json")
    result = sample_result()
    summary = sample_summary()

    assert :ok =
             Reporter.write([result], summary,
               report: path,
               format: "json",
               tck_commit: "abc123",
               source_commit: "def456",
               source_dirty: true,
               suite: "feel",
               profile: "implemented"
             )

    payload = path |> File.read!() |> Jason.decode!()

    assert payload["metadata"]["report_schema_version"] == "2.1"
    assert payload["metadata"]["dmn_tck_commit"] == "abc123"
    assert payload["metadata"]["source_commit"] == "def456"
    assert payload["metadata"]["source_dirty"] == true
    assert payload["metadata"]["suite"] == "feel"
    assert payload["metadata"]["engine_version"] == "0.1.0"
    assert payload["metadata"]["feel_package_version"] == "0.1.0"
    assert payload["metadata"]["dmn_package_version"] == "0.2.0"
    assert payload["metadata"]["dmn_specification_version"] == "1.5"

    assert payload["metadata"]["dmn_model_namespace"] ==
             "https://www.omg.org/spec/DMN/20230324/MODEL/"

    assert payload["metadata"]["feel_namespace"] ==
             "https://www.omg.org/spec/DMN/20230324/FEEL/"

    assert Map.take(payload["metadata"], [
             "engine_version",
             "feel_package_version",
             "dmn_package_version",
             "dmn_specification_version",
             "dmn_model_namespace",
             "feel_namespace",
             "source_commit",
             "source_dirty",
             "elixir_version",
             "otp_version"
           ])
           |> map_size() == 10

    assert {:ok, _date, _offset} = DateTime.from_iso8601(payload["metadata"]["execution_date"])
    assert payload["summary"]["compatibility_percent"] == 100.0

    assert [entry] = payload["results"]
    assert entry["status"] == "passed"
    assert entry["expected_error"] == false
    assert entry["expected"]["amount"] == %{"type" => "number", "value" => "1.25"}

    assert entry["expected"]["duration"] == %{
             "type" => "duration",
             "kind" => "year_month",
             "months" => 1,
             "seconds" => 30
           }

    assert entry["actual"] == entry["expected"]
    assert entry["error"] == nil
  end

  test "CSV report exposes stable schema and both format writes sibling files" do
    root = temporary_directory()
    base = Path.join(root, "report")

    assert :ok =
             Reporter.write([sample_result()], sample_summary(),
               report: base,
               format: "both",
               tck_commit: "abc123",
               source_commit: "def456",
               source_dirty: true
             )

    assert File.exists?(base <> ".json")
    csv = File.read!(base <> ".csv")

    assert csv =~
             "report_schema_version,engine_version,feel_package_version,dmn_package_version,dmn_tck_commit,dmn_specification_version,dmn_model_namespace,feel_namespace,source_commit,source_dirty,elixir_version,otp_version,execution_date,suite,profile,compatibility_percent,suite_coverage_percent,coverage_percent,group,id,status,decision,expected_error,expected,actual,error,case_file,compliance_level"

    assert csv =~ "\"abc123\""
    assert csv =~ "\"def456\""
    assert csv =~ "\"report-group\""
    refute csv =~ "%Decimal{"

    [header, row] = String.split(csv, "\n", trim: true)
    assert length(String.split(header, ",")) == length(Regex.scan(~r/"(?:[^"]|"")*"/, row))
  end

  defp sample_result do
    value = %{
      "amount" => Decimal.new("1.25"),
      "duration" => %Duration{kind: :year_month, months: 1, seconds: 30}
    }

    test_case = %Case{
      group: "report-group",
      id: "001",
      labels: [],
      model_path: "/tmp/report.dmn",
      decision_name: "Decision",
      inputs: %{},
      expected: value,
      expect_error: false,
      load_error: nil,
      metadata: %{case_file: "TestCases/report-test-01.xml", compliance_level: "level-3"}
    }

    %{case: test_case, status: :passed, actual: value, error: nil}
  end

  defp sample_summary do
    %{
      total: 1,
      passed: 1,
      failed: 0,
      unsupported: 0,
      missing: 0,
      error: 0,
      supported: 1,
      corpus_total: 1,
      suite_total: 1,
      excluded_by_suite: 0,
      disabled: 0,
      compatibility_percent: 100.0,
      suite_coverage_percent: 100.0,
      coverage_percent: 100.0
    }
  end

  defp temporary_directory do
    path = Path.join(System.tmp_dir!(), "boxic-report-#{System.unique_integer([:positive])}")
    File.mkdir_p!(path)
    on_exit(fn -> File.rm_rf!(path) end)
    path
  end
end
