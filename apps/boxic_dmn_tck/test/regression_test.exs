defmodule Boxic.DMN.TCK.RegressionTest do
  use ExUnit.Case, async: true

  alias Boxic.DMN.TCK.Regression

  test "accepts the exact unsupported cases recorded in the baseline" do
    baseline = report([unsupported_result("java_1"), unsupported_result("java_2")])

    assert Regression.check(baseline, baseline) == []
  end

  test "rejects a changed unsupported count" do
    baseline = report([unsupported_result("java_1"), unsupported_result("java_2")])
    current = report([unsupported_result("java_1")], passed: 11)

    assert "unsupported entries changed from 2 to 1" in Regression.check(baseline, current)
  end

  test "rejects an unexpected unsupported case even when the count is unchanged" do
    baseline = report([unsupported_result("java_1"), unsupported_result("java_2")])
    current = report([unsupported_result("java_1"), unsupported_result("unrelated")])

    assert Enum.any?(Regression.check(baseline, current), fn failure ->
             failure =~ "unsupported case set changed" and
               failure =~ ~s({"0076-feel-external-java", "java_2"}) and
               failure =~ ~s({"other-group", "unrelated"})
           end)
  end

  defp report(results, opts \\ []) do
    unsupported = Enum.count(results, &(&1["status"] == "unsupported"))

    %{
      "metadata" => %{"dmn_tck_commit" => "pinned"},
      "results" => results,
      "summary" => %{
        "passed" => Keyword.get(opts, :passed, 10),
        "compatibility_percent" => 100.0,
        "suite_coverage_percent" => 99.0,
        "failed" => 0,
        "error" => 0,
        "missing" => 0,
        "unsupported" => unsupported
      }
    }
  end

  defp unsupported_result("unrelated") do
    %{"group" => "other-group", "id" => "unrelated", "status" => "unsupported"}
  end

  defp unsupported_result(id) do
    %{"group" => "0076-feel-external-java", "id" => id, "status" => "unsupported"}
  end
end
