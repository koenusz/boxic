defmodule TCKRegression do
  @moduledoc false

  alias Boxic.DMN.TCK.Regression

  def run([baseline_path, current_path]) do
    baseline = load!(baseline_path)
    current = load!(current_path)

    failures = Regression.check(baseline, current)

    case failures do
      [] ->
        summary = current["summary"]

        IO.puts(
          "TCK regression gate passed: #{summary["passed"]} passed, " <>
            "#{summary["unsupported"]} expected unsupported, " <>
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
end

TCKRegression.run(System.argv())
