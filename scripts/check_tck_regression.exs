defmodule TCKRegression do
  @moduledoc false

  def run([baseline_path, current_path]) do
    baseline = load!(baseline_path)
    current = load!(current_path)

    failures =
      []
      |> require_equal("DMN TCK commit", baseline, current, ["metadata", "dmn_tck_commit"])
      |> require_not_lower("passed entries", baseline, current, ["summary", "passed"])
      |> require_not_lower(
        "supported compatibility",
        baseline,
        current,
        ["summary", "compatibility_percent"]
      )
      |> require_not_lower(
        "suite coverage",
        baseline,
        current,
        ["summary", "suite_coverage_percent"]
      )
      |> require_zero("failed entries", current, ["summary", "failed"])
      |> require_zero("errored entries", current, ["summary", "error"])
      |> require_zero("missing entries", current, ["summary", "missing"])
      |> require_zero("unsupported entries", current, ["summary", "unsupported"])

    case Enum.reverse(failures) do
      [] ->
        summary = current["summary"]

        IO.puts(
          "TCK regression gate passed: #{summary["passed"]} passed, " <>
            "#{summary["compatibility_percent"]}% compatibility, " <>
            "#{summary["suite_coverage_percent"]}% suite coverage"
        )

      failures ->
        Enum.each(failures, &IO.puts(:stderr, "TCK regression: #{&1}"))
        System.halt(1)
    end
  end

  def run(_args) do
    IO.puts(:stderr, "usage: mix run scripts/check_tck_regression.exs BASELINE.json CURRENT.json")
    System.halt(2)
  end

  defp load!(path), do: path |> File.read!() |> Jason.decode!()
  defp value(report, path), do: get_in(report, path)

  defp require_equal(errors, label, baseline, current, path) do
    expected = value(baseline, path)
    actual = value(current, path)

    if actual == expected,
      do: errors,
      else: ["#{label} changed from #{inspect(expected)} to #{inspect(actual)}" | errors]
  end

  defp require_not_lower(errors, label, baseline, current, path) do
    expected = value(baseline, path)
    actual = value(current, path)

    if is_number(actual) and is_number(expected) and actual >= expected,
      do: errors,
      else: ["#{label} regressed from #{inspect(expected)} to #{inspect(actual)}" | errors]
  end

  defp require_zero(errors, label, current, path) do
    actual = value(current, path)
    if actual == 0, do: errors, else: ["#{label} must be zero, got #{inspect(actual)}" | errors]
  end
end

TCKRegression.run(System.argv())
