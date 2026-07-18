defmodule Boxic.DMN.TCK.Regression do
  @moduledoc false

  @spec check(map(), map()) :: [String.t()]
  def check(baseline, current) do
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
    |> require_equal(
      "unsupported entries",
      baseline,
      current,
      ["summary", "unsupported"]
    )
    |> require_same_status_cases("unsupported", baseline, current)
    |> Enum.reverse()
  end

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

  defp require_same_status_cases(errors, status, baseline, current) do
    with {:ok, expected} <- status_case_ids(baseline, status),
         {:ok, actual} <- status_case_ids(current, status) do
      missing = expected -- actual
      unexpected = actual -- expected

      if missing == [] and unexpected == [] do
        errors
      else
        [
          "#{status} case set changed; missing #{inspect(missing)}, " <>
            "unexpected #{inspect(unexpected)}"
          | errors
        ]
      end
    else
      {:error, reason} -> ["cannot compare #{status} cases: #{reason}" | errors]
    end
  end

  defp status_case_ids(%{"results" => results}, status) when is_list(results) do
    ids =
      results
      |> Enum.filter(&(&1["status"] == status))
      |> Enum.map(&{&1["group"], &1["id"]})
      |> Enum.sort()

    {:ok, ids}
  end

  defp status_case_ids(_report, _status), do: {:error, "report has no results list"}
end
