defmodule Boxic.BuildHexPackage do
  @moduledoc false

  @publishable_apps ~w(boxic_feel boxic_dmn)
  @umbrella_paths ~r/^\s+(build_path|config_path|deps_path|lockfile): .*,$\n/m
  @umbrella_dependency "{:boxic_feel, @boxic_feel_requirement, in_umbrella: true}"
  @hex_dependency "{:boxic_feel, @boxic_feel_requirement}"

  def run(args) do
    {app, output} = parse_args!(args)
    root = File.cwd!()
    source = Path.join([root, "apps", app])
    output = Path.expand(output, root)
    staging = staging_path(app)

    unless File.dir?(source) do
      Mix.raise("package source does not exist: #{source}")
    end

    try do
      File.cp_r!(source, staging)
      prepare_mix_project!(app, Path.join(staging, "mix.exs"))
      build_package!(staging, output)
    after
      File.rm_rf!(staging)
    end
  end

  defp parse_args!([app, output]) when app in @publishable_apps, do: {app, output}

  defp parse_args!([app]) when app in @publishable_apps,
    do: {app, Path.join(System.tmp_dir!(), "#{app}.tar")}

  defp parse_args!(_args) do
    Mix.raise(
      "usage: mix run scripts/build_hex_package.exs " <>
        "boxic_feel|boxic_dmn [OUTPUT.tar]"
    )
  end

  defp staging_path(app) do
    suffix = System.unique_integer([:positive, :monotonic])
    Path.join(System.tmp_dir!(), "boxic-hex-#{app}-#{suffix}")
  end

  defp prepare_mix_project!(app, mix_path) do
    source = File.read!(mix_path)
    standalone = Regex.replace(@umbrella_paths, source, "")

    standalone =
      if app == "boxic_dmn" do
        replace_once!(standalone, @umbrella_dependency, @hex_dependency)
      else
        standalone
      end

    if standalone == source do
      Mix.raise("staging did not remove any umbrella-only configuration from #{mix_path}")
    end

    File.write!(mix_path, standalone)
  end

  defp replace_once!(source, pattern, replacement) do
    case :binary.matches(source, pattern) do
      [_match] ->
        String.replace(source, pattern, replacement)

      matches ->
        Mix.raise("expected one occurrence of #{inspect(pattern)}, found #{length(matches)}")
    end
  end

  defp build_package!(staging, output) do
    File.mkdir_p!(Path.dirname(output))

    {message, status} =
      System.cmd("mix", ["hex.build", "-o", output],
        cd: staging,
        stderr_to_stdout: true
      )

    IO.write(message)

    if status != 0 do
      Mix.raise("Hex package build failed with exit status #{status}")
    end
  end
end

Boxic.BuildHexPackage.run(System.argv())
