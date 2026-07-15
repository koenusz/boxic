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
    soft_fail: :boolean
  ]

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.start")

    {opts, _argv, _invalid} = OptionParser.parse(args, strict: @switches)

    run_opts =
      []
      |> put_opt(:group, opts[:group])
      |> put_opt(:label, profile_label(opts[:profile], opts[:label]))
      |> put_opt(:report, opts[:report])

    result = Arbiter.DMN.TCK.run(run_opts)

    Mix.shell().info("TCK summary")
    Mix.shell().info("  total: #{result.summary.total}")
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
      "  coverage of total corpus: #{format_percent(result.summary.coverage_percent)}"
    )

    if not opts[:soft_fail] and (result.summary.failed > 0 or result.summary.error > 0) do
      Mix.raise("TCK run includes failed/error cases")
    end
  end

  defp profile_label("core", nil), do: "core"
  defp profile_label(_profile, explicit_label), do: explicit_label

  defp put_opt(opts, _key, nil), do: opts
  defp put_opt(opts, key, value), do: Keyword.put(opts, key, value)

  defp format_percent(value), do: :erlang.float_to_binary(value, decimals: 2) <> "%"
end
