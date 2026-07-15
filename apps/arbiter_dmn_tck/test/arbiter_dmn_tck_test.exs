defmodule Arbiter.DMN.TCKTest do
  use ExUnit.Case

  alias Arbiter.DMN.TCK.Loader
  alias Arbiter.DMN.TCK.Runner
  alias Arbiter.DMN.TCK

  test "loads the complete pinned upstream corpus" do
    cases = Loader.load_all()

    assert length(cases) == 3_545

    assert Enum.any?(cases, fn test_case ->
             test_case.group == "0001-input-data-string" and
               test_case.metadata.compliance_level == "compliance-level-2"
           end)

    assert Enum.any?(cases, fn test_case ->
             test_case.group == "0007-date-time" and
               test_case.metadata.compliance_level == "compliance-level-3"
           end)
  end

  test "normalizes an official scalar test case" do
    case_entry =
      Loader.load_all()
      |> Enum.find(fn test_case ->
        test_case.group == "0001-input-data-string" and
          test_case.metadata.upstream_id == "001"
      end)

    assert case_entry
    assert case_entry.decision_name == "Greeting Message"
    assert case_entry.inputs == %{"Full Name" => "John Doe"}
    assert case_entry.expected == "Hello John Doe"
    assert File.exists?(case_entry.model_path)
  end

  test "normalizes official nested component values" do
    case_entry =
      Loader.load_all()
      |> Enum.find(fn test_case ->
        test_case.group == "0035-test-structure-output" and
          test_case.metadata.upstream_id == "001"
      end)

    assert case_entry.expected["RGB notation"] == %{
             "R" => Decimal.new(0),
             "G" => Decimal.new(65),
             "B" => Decimal.new(83)
           }
  end

  test "official cases receive an explicit runner status" do
    case_entry =
      Loader.load_all()
      |> Enum.find(&(&1.group == "0001-input-data-string"))

    result = Runner.execute(case_entry)
    assert result.status in [:passed, :failed, :unsupported, :missing, :error]
  end

  test "implemented profile is an explicit passing baseline" do
    result = TCK.run(suite: "feel", profile: "implemented")

    assert result.summary.corpus_total == 3_545
    assert result.summary.suite_total > 27
    assert result.summary.total == 27
    assert result.summary.disabled == result.summary.suite_total - 27
    assert result.summary.excluded_by_suite == 3_545 - result.summary.suite_total
    assert result.summary.passed == 27
    assert result.summary.failed == 0
    assert result.summary.error == 0

    assert Enum.sort(Enum.uniq_by(result.selected_cases, & &1.group) |> Enum.map(& &1.group)) ==
             Enum.sort(TCK.profile_groups("feel", "implemented"))
  end

  test "DMN implemented profile is explicitly empty until an official group passes" do
    result = TCK.run(suite: "dmn", profile: "implemented")

    assert result.summary.corpus_total == 3_545
    assert result.summary.suite_total > 0
    assert result.summary.total == 0
    assert result.summary.disabled == result.summary.suite_total
    assert result.results == []
    assert TCK.profile_groups("dmn", "implemented") == []
  end
end
