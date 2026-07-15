defmodule Arbiter.DMN.TCKTest do
  use ExUnit.Case

  alias Arbiter.DMN.TCK.Loader
  alias Arbiter.DMN.TCK.Runner

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
end
