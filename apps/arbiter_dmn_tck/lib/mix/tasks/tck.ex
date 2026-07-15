defmodule Mix.Tasks.Tck do
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

    {opts, _argv, _invalid} = OptionParser.parse(args, strict: @switches)
    validate_options!(opts)

    run_opts =
      []
      |> put_opt(:group, opts[:group])
      |> put_opt(:label, opts[:label])
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
  end

  defp selected_profile(opts) do
    if opts[:all], do: nil, else: opts[:profile]
  end

  defp validate_options!(opts) do
    if opts[:all] && opts[:profile] do
      Mix.raise("--all and --profile cannot be used together")
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
  end

  defp put_opt(opts, _key, nil), do: opts
  defp put_opt(opts, key, value), do: Keyword.put(opts, key, value)

  defp format_percent(value), do: :erlang.float_to_binary(value, decimals: 2) <> "%"
end
