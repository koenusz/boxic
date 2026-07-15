defmodule Mix.Tasks.Tck do
  @moduledoc """
  Runs the vendored official DMN TCK corpus through Arbiter.

  By default, failed or errored cases make the task exit non-zero. Use
  `--soft-fail` for diagnostic runs where the complete result should be shown
  without failing the command. Soft-fail does not change, hide, or skip any
  result; it only changes the task's exit behavior.

  ## Targeted implemented profiles

      mix tck --suite feel --profile implemented
      mix tck --suite dmn --profile implemented

  The FEEL implemented profile is the strict baseline used by `mix test`.
  Cases in the selected suite but outside the profile are counted as disabled.
  The DMN implemented profile remains empty until an official DMN-focused
  group passes.

  ## Complete diagnostic runs

      mix tck --suite feel --all --soft-fail
      mix tck --suite dmn --all --soft-fail
      mix tck --all --soft-fail

  Omit `--soft-fail` when failures and errors should fail the command, such as
  for a strict CI compatibility gate.

  ## Filters and reports

      mix tck --group 0100-feel-constants
      mix tck --label "Compliance Level 2"
      mix tck --suite feel --all --soft-fail --report artifacts/tck-feel --format both

  `--format csv` or `--format json` writes exactly the supplied report path.
  `--format both` writes `.csv` and `.json` siblings; it is the default when a
  report path is supplied.

  ## Options

    * `--suite feel|dmn` - select FEEL-focused or DMN-focused cases;
    * `--profile implemented` - run the explicitly enabled baseline for a
      suite; requires `--suite`;
    * `--all` - run every case in the selected suite, or the entire corpus when
      no suite is supplied;
    * `--soft-fail` - report failures and errors without a non-zero task exit;
    * `--group GROUP` - select an exact upstream test group;
    * `--label LABEL` - select cases containing an exact upstream label;
    * `--report PATH` - output path or base path for machine-readable reports;
    * `--format csv|json|both` - select report output; requires `--report`.

  `--all` cannot be combined with `--profile`, `--group`, or `--label`. A run
  must explicitly select `--all`, `--profile`, `--group`, or `--label`; this
  prevents an accidental complete-corpus run.
  """

  use Mix.Task

  @shortdoc "Run vendored DMN TCK cases through Arbiter"

  @switches [
    all: :boolean,
    group: :string,
    label: :string,
    report: :string,
    format: :string,
    profile: :string,
    suite: :string,
    soft_fail: :boolean
  ]

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.start")

    {opts, argv, invalid} = OptionParser.parse(args, strict: @switches)
    validate_options!(opts, argv, invalid)

    run_opts =
      []
      |> put_opt(:group, opts[:group])
      |> put_opt(:label, opts[:label])
      |> put_opt(:format, opts[:format])
      |> put_opt(:profile, selected_profile(opts))
      |> put_opt(:suite, opts[:suite])
      |> put_opt(:report, opts[:report])

    result = Arbiter.DMN.TCK.run(run_opts)

    Mix.shell().info("TCK summary")
    Mix.shell().info("  corpus total: #{result.summary.corpus_total}")
    Mix.shell().info("  suite: #{opts[:suite] || "all"}")
    Mix.shell().info("  suite total: #{result.summary.suite_total}")
    Mix.shell().info("  excluded by suite: #{result.summary.excluded_by_suite}")
    Mix.shell().info("  selected: #{result.summary.total}")
    Mix.shell().info("  disabled by profile: #{result.summary.disabled}")
    Mix.shell().info("  passed: #{result.summary.passed}")
    Mix.shell().info("  failed: #{result.summary.failed}")
    Mix.shell().info("  unsupported: #{result.summary.unsupported}")
    Mix.shell().info("  missing: #{result.summary.missing}")
    Mix.shell().info("  error: #{result.summary.error}")
    Mix.shell().info("  supported: #{result.summary.supported}")

    Mix.shell().info(
      "  compatibility on supported scope: #{format_percent(result.summary.compatibility_percent)}"
    )

    Mix.shell().info(
      "  coverage of selected suite: #{format_percent(result.summary.suite_coverage_percent)}"
    )

    Mix.shell().info(
      "  coverage of total corpus: #{format_percent(result.summary.coverage_percent)}"
    )

    if opts[:soft_fail] != true and
         (result.summary.failed > 0 or result.summary.error > 0) do
      Mix.raise("TCK run includes failed/error cases")
    end

    :ok
  end

  defp selected_profile(opts) do
    if opts[:all], do: nil, else: opts[:profile]
  end

  defp validate_options!(opts, argv, invalid) do
    if argv != [] or invalid != [] do
      Mix.raise("invalid TCK arguments: #{Enum.join(argv ++ format_invalid(invalid), " ")}")
    end

    if opts[:all] && Enum.any?([opts[:profile], opts[:group], opts[:label]]) do
      Mix.raise("--all cannot be combined with --profile, --group, or --label")
    end

    if opts[:profile] && opts[:profile] != "implemented" do
      Mix.raise("unknown TCK profile: #{opts[:profile]}")
    end

    if opts[:suite] not in [nil, "feel", "dmn"] do
      Mix.raise("unknown TCK suite: #{opts[:suite]}")
    end

    if opts[:profile] && is_nil(opts[:suite]) do
      Mix.raise("--profile requires --suite feel or --suite dmn")
    end

    if opts[:format] && opts[:format] not in ["csv", "json", "both"] do
      Mix.raise("unknown report format: #{opts[:format]}")
    end

    if opts[:format] && is_nil(opts[:report]) do
      Mix.raise("--format requires --report")
    end

    if not Enum.any?([opts[:all], opts[:profile], opts[:group], opts[:label]]) do
      Mix.raise("select --all, --profile, --group, or --label")
    end
  end

  defp format_invalid(invalid), do: Enum.map(invalid, fn {option, _value} -> option end)

  defp put_opt(opts, _key, nil), do: opts
  defp put_opt(opts, key, value), do: Keyword.put(opts, key, value)

  defp format_percent(value), do: :erlang.float_to_binary(value, decimals: 2) <> "%"
end
