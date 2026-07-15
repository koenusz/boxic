defmodule TCKCompatibilityDelta do
  @moduledoc false

  @metrics [
    {"Passed", "passed"},
    {"Supported compatibility (%)", "compatibility_percent"},
    {"Suite coverage (%)", "suite_coverage_percent"},
    {"Total-corpus coverage (%)", "coverage_percent"},
    {"Failed", "failed"},
    {"Errors", "error"},
    {"Unsupported", "unsupported"},
    {"Missing", "missing"}
  ]

  def run(args) do
    {opts, paths, invalid} = OptionParser.parse(args, strict: [output: :string])

    case {paths, invalid} do
      {[baseline_path, current_path], []} ->
        baseline = load!(baseline_path)
        current = load!(current_path)
        markdown = render(baseline_path, current_path, baseline, current)

        case opts[:output] do
          nil -> IO.write(markdown)
          path -> File.write!(path, markdown)
        end

      _ ->
        IO.puts(
          :stderr,
          "usage: mix run scripts/tck_compatibility_delta.exs BASELINE.json CURRENT.json [--output PATH]"
        )

        System.halt(2)
    end
  end

  defp load!(path), do: path |> File.read!() |> Jason.decode!()

  defp render(baseline_path, current_path, baseline, current) do
    rows =
      Enum.map_join(@metrics, "\n", fn {label, key} ->
        before = baseline["summary"][key]
        after_value = current["summary"][key]
        "| #{label} | #{before} | #{after_value} | #{delta(before, after_value)} |"
      end)

    """
    # TCK compatibility delta

    - Baseline: `#{baseline_path}`
    - Current: `#{current_path}`
    - Pinned TCK: `#{current["metadata"]["dmn_tck_commit"]}`
    - Suite: `#{current["metadata"]["suite"]}`

    | Metric | Baseline | Current | Delta |
    | --- | ---: | ---: | ---: |
    #{rows}
    """
  end

  defp delta(before, after_value) when is_number(before) and is_number(after_value) do
    change = after_value - before
    if change > 0, do: "+#{change}", else: to_string(change)
  end

  defp delta(_before, _after_value), do: "n/a"
end

TCKCompatibilityDelta.run(System.argv())
