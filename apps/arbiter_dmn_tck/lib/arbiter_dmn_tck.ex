defmodule Arbiter.DMN.TCK do
  @moduledoc """
  TCK harness entry point for Arbiter.
  """

  alias Arbiter.DMN.TCK.Loader
  alias Arbiter.DMN.TCK.Reporter
  alias Arbiter.DMN.TCK.Runner

  @feel_implemented_groups ~w(
    0064-feel-conjunction
    0065-feel-disjunction
    0066-feel-negation
    0100-feel-constants
    0102-feel-constants
    0106-feel-ternary-logic
    0107-feel-ternary-logic-not
  )

  @spec run(keyword()) :: %{cases: list(), results: list(), summary: map()}
  def run(opts \\ []) do
    cases = Loader.load_all(opts)

    suite_cases = maybe_filter_suite(cases, opts)

    selected_cases =
      suite_cases
      |> maybe_filter_profile(opts)
      |> maybe_filter_group(opts)
      |> maybe_filter_label(opts)

    results =
      selected_cases
      |> Enum.map(&Runner.execute/1)

    summary = summarize(results, length(cases), length(suite_cases))
    Reporter.write(results, summary, opts)

    %{
      cases: cases,
      selected_cases: selected_cases,
      results: results,
      summary: summary
    }
  end

  @spec profile_groups(String.t(), String.t()) :: [String.t()]
  def profile_groups("feel", "implemented"), do: @feel_implemented_groups
  def profile_groups("dmn", "implemented"), do: []
  def profile_groups(_suite, _profile), do: []

  defp maybe_filter_suite(cases, opts) do
    case Keyword.get(opts, :suite) do
      nil -> cases
      "feel" -> Enum.filter(cases, &feel_case?/1)
      "dmn" -> Enum.reject(cases, &feel_case?/1)
      suite -> raise ArgumentError, "unknown TCK suite: #{suite}"
    end
  end

  defp feel_case?(test_case) do
    test_case.group
    |> String.downcase()
    |> String.contains?("feel")
  end

  defp maybe_filter_profile(cases, opts) do
    case Keyword.get(opts, :profile) do
      nil ->
        cases

      "implemented" ->
        groups = profile_groups(Keyword.get(opts, :suite), "implemented")
        Enum.filter(cases, &(&1.group in groups))

      profile ->
        raise ArgumentError, "unknown TCK profile: #{profile}"
    end
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

  defp summarize(results, corpus_total, suite_total) do
    counts = Enum.frequencies_by(results, & &1.status)
    selected_total = length(results)

    %{
      total: selected_total,
      corpus_total: corpus_total,
      suite_total: suite_total,
      excluded_by_suite: corpus_total - suite_total,
      disabled: suite_total - selected_total,
      passed: Map.get(counts, :passed, 0),
      failed: Map.get(counts, :failed, 0),
      unsupported: Map.get(counts, :unsupported, 0),
      missing: Map.get(counts, :missing, 0),
      error: Map.get(counts, :error, 0),
      supported: supported_count(counts),
      compatibility_percent: compatibility_percent(counts),
      suite_coverage_percent: coverage_percent(counts, suite_total),
      coverage_percent: coverage_percent(counts, corpus_total)
    }
  end

  defp supported_count(counts) do
    Map.get(counts, :passed, 0) + Map.get(counts, :failed, 0)
  end

  defp compatibility_percent(counts) do
    supported = supported_count(counts)

    percentage(Map.get(counts, :passed, 0), supported)
  end

  defp coverage_percent(counts, total) do
    percentage(supported_count(counts), total)
  end

  defp percentage(_part, 0), do: 0.0
  defp percentage(part, whole), do: Float.round(part / whole * 100, 2)
end

defmodule ArbiterDmnTck do
  @moduledoc false

  @spec hello() :: atom()
  def hello, do: :world
end
