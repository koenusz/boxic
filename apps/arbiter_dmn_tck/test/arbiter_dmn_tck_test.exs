defmodule Arbiter.DMN.TCKTest do
  use ExUnit.Case

  alias Arbiter.DMN.TCK.Loader
  alias Arbiter.DMN.TCK.Runner
  alias Arbiter.DMN.TCK

  test "loads the complete pinned upstream corpus" do
    stats = Loader.corpus_stats()

    assert stats == %{
             test_documents: 150,
             dmn_models: 154,
             result_entries: 3_545,
             expected_errors: 1_412,
             load_errors: 0,
             missing_models: 0
           }

    pin_path = Path.expand("../../../vendor/dmn-tck/PINNED_COMMIT", __DIR__)
    assert File.read!(pin_path) |> String.trim() == "0dbcaf9b98bc3af4e36d44a7aed95e9e85703a13"

    cases = Loader.load_all()

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

  test "malformed test metadata becomes an explicit error case" do
    root = temporary_corpus_root()
    group = Path.join(root, "TestCases/compliance-level-3/broken-case")
    File.mkdir_p!(group)

    File.write!(
      Path.join(group, "broken-case-test-01.xml"),
      "<testCases><testCase id=\"001\"/></testCases>"
    )

    assert [test_case] = Loader.load_all(root: root)
    assert {:invalid_test_document, message} = test_case.load_error
    assert message =~ "modelName"
    assert Runner.execute(test_case).status == :error
  end

  test "discovers every numbered test document and rejects empty documents explicitly" do
    root = temporary_corpus_root()
    group = Path.join(root, "TestCases/compliance-level-3/numbered-case")
    File.mkdir_p!(group)

    File.write!(
      Path.join(group, "numbered-case-test-02.xml"),
      "<testCases><modelName>numbered-case.dmn</modelName></testCases>"
    )

    assert [test_case] = Loader.load_all(root: root)
    assert {:invalid_test_document, message} = test_case.load_error
    assert message =~ "no testCase elements"

    assert Loader.corpus_stats(root: root) == %{
             test_documents: 1,
             dmn_models: 0,
             result_entries: 1,
             expected_errors: 0,
             load_errors: 1,
             missing_models: 0
           }
  end

  test "missing model artifacts receive missing status" do
    root = temporary_corpus_root()
    group = Path.join(root, "TestCases/compliance-level-2/missing-model")
    File.mkdir_p!(group)

    File.write!(
      Path.join(group, "missing-model-test-01.xml"),
      """
      <testCases xmlns="http://www.omg.org/spec/DMN/20160719/testcase">
        <modelName>missing-model.dmn</modelName>
        <testCase id="001">
          <resultNode name="Decision" type="decision">
            <expected><value>expected</value></expected>
          </resultNode>
        </testCase>
      </testCases>
      """
    )

    assert [test_case] = Loader.load_all(root: root)
    assert is_nil(test_case.load_error)
    assert Runner.execute(test_case).status == :missing
    assert Loader.corpus_stats(root: root).missing_models == 1
  end

  test "expected-error results pass only when evaluation returns an error" do
    root = temporary_corpus_root()
    model_path = Path.join(root, "error-model.dmn")

    File.mkdir_p!(root)

    File.write!(
      model_path,
      """
      <definitions name="error model" namespace="urn:test">
        <decision id="d1" name="Decision">
          <literalExpression><text>1 +</text></literalExpression>
        </decision>
      </definitions>
      """
    )

    test_case = %Arbiter.DMN.TCK.Case{
      group: "expected-error",
      id: "001",
      labels: [],
      model_path: model_path,
      decision_name: "Decision",
      inputs: %{},
      expected: nil,
      expect_error: true,
      load_error: nil,
      metadata: %{}
    }

    assert %{status: :passed, error: %Arbiter.FEEL.Error{}} = Runner.execute(test_case)
    assert Runner.execute(%{test_case | expect_error: false}).status == :error
  end

  test "implemented profile is an explicit passing baseline" do
    result = TCK.run(suite: "feel", profile: "implemented")
    expected_passes = 1_005

    assert result.summary.corpus_total == 3_545
    assert result.summary.suite_total > expected_passes
    assert result.summary.total == expected_passes
    assert result.summary.disabled == result.summary.suite_total - expected_passes
    assert result.summary.excluded_by_suite == 3_545 - result.summary.suite_total
    assert result.summary.passed == expected_passes
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

  defp temporary_corpus_root do
    root =
      Path.join(
        System.tmp_dir!(),
        "arbiter-tck-#{System.unique_integer([:positive, :monotonic])}"
      )

    on_exit(fn -> File.rm_rf!(root) end)
    root
  end
end
