defmodule Mix.Tasks.Tck.Writer do
  @moduledoc """
  Audits vendored TCK DMN models against the pinned XML writer profile.

      mix tck.writer --profile implemented
      mix tck.writer --all

  The task reports supported, explicitly rejected, and failed model counts.
  Rejections are expected for documents outside the pinned DMN version or
  containing unsupported preservation content. Failures make the task exit
  non-zero.
  """

  use Mix.Task

  @shortdoc "Audit TCK models against the DMN XML writer"
  @switches [all: :boolean, profile: :string]

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.start")
    {opts, argv, invalid} = OptionParser.parse(args, strict: @switches)
    validate_options!(opts, argv, invalid)

    audit_opts = if opts[:all], do: [], else: [profile: opts[:profile]]
    result = Boxic.DMN.TCK.WriterAudit.run(audit_opts)

    Mix.shell().info("DMN writer TCK audit")
    Mix.shell().info("  models: #{result.summary.total}")
    Mix.shell().info("  supported: #{result.summary.supported}")
    Mix.shell().info("  rejected: #{result.summary.rejected}")
    Mix.shell().info("  failed: #{result.summary.failed}")

    if result.summary.failed > 0 do
      Mix.raise("DMN writer TCK audit includes failed models")
    end

    :ok
  end

  defp validate_options!(opts, argv, invalid) do
    if argv != [] or invalid != [] do
      Mix.raise("invalid TCK writer arguments")
    end

    if opts[:all] == true and not is_nil(opts[:profile]) do
      Mix.raise("select exactly one of --all or --profile implemented")
    end

    if opts[:profile] not in [nil, "implemented"] do
      Mix.raise("unknown writer audit profile: #{opts[:profile]}")
    end

    if opts[:all] != true and is_nil(opts[:profile]) do
      Mix.raise("select --all or --profile implemented")
    end
  end
end
