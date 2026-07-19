defmodule Boxic.DMN.TCK do
  @moduledoc """
  TCK harness entry point for Boxic.
  """

  alias Boxic.DMN.TCK.Loader
  alias Boxic.DMN.TCK.Reporter
  alias Boxic.DMN.TCK.Runner

  @feel_implemented_groups ~w(
    0001-filter
    0050-feel-abs-function
    0051-feel-sqrt-function
    0052-feel-exp-function
    0053-feel-log-function
    0054-feel-even-function
    0055-feel-odd-function
    0056-feel-modulo-function
    0058-feel-number-function
    0059-feel-all-function
    0060-feel-any-function
    0061-feel-median-function
    0062-feel-mode-function
    0063-feel-stddev-function
    0032-conditionals
    0057-feel-context
    0064-feel-conjunction
    0065-feel-disjunction
    0066-feel-negation
    0067-feel-split-function
    0068-feel-equality
    0069-feel-list
    0070-feel-instance-of
    0071-feel-between
    0072-feel-in
    0073-feel-comments
    0074-feel-properties
    0075-feel-exponent
    0076-feel-external-java
    0077-feel-nan
    0078-feel-infinity
    0079-feel-string-function
    0080-feel-getvalue-function
    0081-feel-getentries-function
    0082-feel-coercion
    0083-feel-unicode
    0084-feel-for-loops
    0090-feel-paths
    0092-feel-lambda
    0093-feel-at-literals
    0094-feel-product-function
    0095-feel-day-of-year-function
    0096-feel-day-of-week-function
    0097-feel-month-of-year-function
    0098-feel-week-of-year-function
    0100-feel-constants
    0101-feel-constants
    0102-feel-constants
    0103-feel-is-function
    0105-feel-math
    0106-feel-ternary-logic
    0107-feel-ternary-logic-not
    1100-feel-decimal-function
    1101-feel-floor-function
    1102-feel-ceiling-function
    1103-feel-substring-function
    1104-feel-string-length-function
    1105-feel-upper-case-function
    1106-feel-lower-case-function
    1107-feel-substring-before-function
    1108-feel-substring-after-function
    1109-feel-replace-function
    1110-feel-contains-function
    1111-feel-matches-function
    1115-feel-date-function
    1116-feel-time-function
    1117-feel-date-and-time-function
    1120-feel-duration-function
    1121-feel-years-and-months-duration-function
    1130-feel-interval
    1131-feel-function-invocation
    1140-feel-string-join-function
    1141-feel-round-up-function
    1142-feel-round-down-function
    1143-feel-round-half-up-function
    1144-feel-round-half-down-function
    1145-feel-context-function
    1146-feel-context-put-function
    1147-feel-context-merge-function
    1148-feel-now-function
    1149-feel-today-function
  )

  @feel_additional_groups ~w(0001-filter 0032-conditionals)
  @dmn_implemented_groups ~w(
    0001-input-data-string
    0002-input-data-number
    0002-string-functions
    0003-input-data-string-allowed-values
    0003-iteration
    0004-lending
    0004-simpletable-U
    0005-literal-invocation
    0005-simpletable-A
    0006-join
    0006-simpletable-P1
    0007-date-time
    0007-simpletable-P2
    0008-LX-arithmetic
    0008-listGen
    0009-invocation-arithmetic
    0009-append-flatten
    0010-concatenate
    0010-multi-output-U
    0011-insert-remove
    0012-list-functions
    0013-sort
    0014-loan-comparison
    0015-all-any
    0016-some-every
    0017-tableTests
    0019-flight-rebooking
    0020-vacation-days
    0021-singleton-list
    0030-user-defined-functions
    0031-user-defined-functions
    0033-for-loops
    0034-drg-scopes
    0035-test-structure-output
    0036-dt-variable-input
    0037-dt-on-bkm-implicit-params
    0038-dt-on-bkm-explicit-params
    0039-dt-list-semantics
    0040-singlenestedcontext
    0041-multiple-nestedcontext
    0085-decision-services
    0086-import
    0087-chapter-11-example
    0088-recursion
    0088-no-decision-logic
    0089-nested-inputdata-imports
    0091-local-hrefs
    0099-arithmetic-negation
    0100-arithmetic
    1150-boxed-conditional
    1151-boxed-filter
    1152-boxed-for
    1153-boxed-some
    1154-boxed-every
    1155-list-replace-function
    1156-range-function
    1161-boxed-list-expression
    0108-first-hitpolicy
    0109-ruleOrder-hitpolicy
    0110-outputOrder-hitpolicy
    0111-first-hitpolicy-singleoutputcol
    0112-ruleOrder-hitpolicy-singleinoutcol
    0113-outputOrder-hitpolicy-singleinoutcol
    0114-min-collect-hitpolicy
    0115-sum-collect-hitpolicy
    0116-count-collect-hitpolicy
    0117-multi-any-hitpolicy
    0118-multi-priority-hitpolicy
    0119-multi-collect-hitpolicy
  )

  @spec run(keyword()) :: %{
          cases: list(),
          selected_cases: list(),
          results: list(),
          summary: map()
        }
  def run(opts \\ []) do
    cases = Loader.load_all(opts)

    suite_cases = maybe_filter_suite(cases, opts)

    selected_cases =
      suite_cases
      |> maybe_filter_profile(opts)
      |> maybe_filter_group(opts)
      |> maybe_filter_label(opts)

    results = execute_cases(selected_cases, opts)

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
  def profile_groups("dmn", "implemented"), do: @dmn_implemented_groups
  def profile_groups(_suite, _profile), do: []

  defp execute_cases(cases, opts) do
    max_concurrency =
      Keyword.get_lazy(opts, :max_concurrency, fn ->
        System.schedulers_online()
      end)

    cases
    |> Task.async_stream(&Runner.execute/1,
      ordered: true,
      max_concurrency: max_concurrency,
      timeout: :infinity
    )
    |> Enum.map(fn {:ok, result} -> result end)
  end

  defp maybe_filter_suite(cases, opts) do
    case Keyword.get(opts, :suite) do
      nil -> cases
      "feel" -> Enum.filter(cases, &feel_case?/1)
      "dmn" -> Enum.reject(cases, &feel_case?/1)
      suite -> raise ArgumentError, "unknown TCK suite: #{suite}"
    end
  end

  defp feel_case?(test_case) do
    test_case.group in @feel_additional_groups or
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
