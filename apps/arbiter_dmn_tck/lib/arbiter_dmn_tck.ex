defmodule Arbiter.DMN.TCK do
  @moduledoc """
  TCK harness entry point for Arbiter.
  """

  alias Arbiter.DMN.TCK.Loader
  alias Arbiter.DMN.TCK.Reporter
  alias Arbiter.DMN.TCK.Runner

  @spec run(keyword()) :: %{cases: list(), results: list(), summary: map()}
  def run(opts \\ []) do
    cases = Loader.load_all(opts)

    results =
      cases
      |> maybe_filter_group(opts)
      |> maybe_filter_label(opts)
      |> Enum.map(&Runner.execute/1)

    summary = summarize(results)
    Reporter.write(results, summary, opts)
    %{cases: cases, results: results, summary: summary}
  end

  defp maybe_filter_group(cases, opts) do
    case Keyword.get(opts, :group) do
      nil -> cases
      group -> Enum.filter(cases, &(&1.group == group))
    end
  end

  defp maybe_filter_label(cases, opts) do
    case Keyword.get(opts, :label) do
      nil -> cases
      label -> Enum.filter(cases, &(label in &1.labels))
    end
  end

  defp summarize(results) do
    counts = Enum.frequencies_by(results, & &1.status)

    %{
      total: length(results),
      passed: Map.get(counts, :passed, 0),
      failed: Map.get(counts, :failed, 0),
      unsupported: Map.get(counts, :unsupported, 0),
      missing: Map.get(counts, :missing, 0),
      error: Map.get(counts, :error, 0)
    }
  end
end

defmodule ArbiterDmnTck do
  @moduledoc false

  @spec hello() :: atom()
  def hello, do: :world
end
