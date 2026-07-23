defmodule Boxic.SmokeTestHexPackages do
  @moduledoc false

  @repo_name "hexpm"
  @forbidden_directories ~w(test tck vendor compatibility artifacts scripts)

  def run([feel_archive, dmn_archive]) do
    root = File.cwd!()
    feel_archive = Path.expand(feel_archive, root)
    dmn_archive = Path.expand(dmn_archive, root)
    workspace = workspace_path()

    assert_file!(feel_archive)
    assert_file!(dmn_archive)

    try do
      File.mkdir_p!(workspace)
      repository = build_repository!(root, workspace, feel_archive, dmn_archive)
      {server, url} = start_repository!(repository)

      try do
        env = consumer_env(root, workspace)
        configure_repository!(workspace, url, Path.join(repository, "public_key"), env)
        smoke_test_feel!(workspace, env)
        smoke_test_dmn!(workspace, env)
      after
        :inets.stop(:httpd, server)
      end
    after
      File.rm_rf!(workspace)
    end

    IO.puts("Clean-consumer smoke tests passed for boxic_feel and boxic_dmn")
  end

  def run(_args) do
    Mix.raise(
      "usage: mix run scripts/smoke_test_hex_packages.exs " <>
        "FEEL_ARCHIVE.tar DMN_ARCHIVE.tar"
    )
  end

  defp build_repository!(root, workspace, feel_archive, dmn_archive) do
    repository = Path.join(workspace, "repository")
    tarballs = Path.join(repository, "tarballs")
    private_key = Path.join(workspace, "private_key.pem")

    File.mkdir_p!(tarballs)
    File.cp!(feel_archive, Path.join(tarballs, "boxic_feel-0.1.0.tar"))
    File.cp!(dmn_archive, Path.join(tarballs, "boxic_dmn-0.2.0.tar"))
    copy_locked_packages!(root, tarballs)
    write_private_key!(private_key)

    run!(
      "mix",
      [
        "hex.registry",
        "build",
        repository,
        "--name=#{@repo_name}",
        "--private-key=#{private_key}"
      ],
      cd: root
    )

    repository
  end

  defp copy_locked_packages!(root, tarballs) do
    lock = Mix.Dep.Lock.read(Path.join(root, "mix.lock"))
    hex_home = System.get_env("HEX_HOME") || Path.join(System.user_home!(), ".hex")
    cache = Path.join([hex_home, "packages", "hexpm"])

    Enum.each(lock, fn
      {_app, {:hex, package, version, _checksum, _build_tools, _deps, "hexpm", _outer_checksum}} ->
        filename = "#{package}-#{version}.tar"
        source = Path.join(cache, filename)
        assert_file!(source)
        File.cp!(source, Path.join(tarballs, filename))

      _entry ->
        :ok
    end)
  end

  defp write_private_key!(path) do
    run!("openssl", ["genrsa", "-out", path, "2048"], cd: Path.dirname(path))
  end

  defp start_repository!(repository) do
    {:ok, _applications} = Application.ensure_all_started(:inets)
    port = available_port()

    {:ok, server} =
      :inets.start(:httpd,
        port: port,
        bind_address: {127, 0, 0, 1},
        server_name: ~c"localhost",
        server_root: String.to_charlist(repository),
        document_root: String.to_charlist(repository)
      )

    {server, "http://127.0.0.1:#{port}"}
  end

  defp available_port do
    {:ok, socket} = :gen_tcp.listen(0, [:binary, active: false])
    {:ok, {_address, port}} = :inet.sockname(socket)
    :ok = :gen_tcp.close(socket)
    port
  end

  defp configure_repository!(workspace, url, public_key, env) do
    run!(
      "mix",
      ["hex.repo", "set", @repo_name, "--url", url, "--public-key", public_key],
      cd: workspace,
      env: env
    )
  end

  defp smoke_test_feel!(workspace, env) do
    project = Path.join(workspace, "feel_consumer")
    create_project!(project, "feel_consumer", "FeelConsumer", env)
    write_mix_file!(project, "FeelConsumer", [{:boxic_feel, "~> 0.1.0"}])
    fetch_and_compile!(project, env)

    File.write!(Path.join(project, "smoke.exs"), """
    {:ok, value} = Boxic.FEEL.evaluate("1 + 2")

    unless Decimal.equal?(value, Decimal.new(3)) do
      raise "expected FEEL evaluation to return 3, got: \#{inspect(value)}"
    end
    """)

    run!("mix", ["run", "smoke.exs"], cd: project, env: env)
    verify_installed_package!(project, "boxic_feel")
  end

  defp smoke_test_dmn!(workspace, env) do
    project = Path.join(workspace, "dmn_consumer")
    create_project!(project, "dmn_consumer", "DmnConsumer", env)
    write_mix_file!(project, "DmnConsumer", [{:boxic_dmn, "~> 0.2.0"}])
    fetch_and_compile!(project, env)

    unless File.dir?(Path.join([project, "deps", "boxic_feel"])) do
      Mix.raise("boxic_dmn did not resolve boxic_feel transitively")
    end

    File.write!(Path.join(project, "smoke.exs"), """
    xml = \"""
    <definitions xmlns="https://www.omg.org/spec/DMN/20230324/MODEL/"
      id="example" name="Example" namespace="https://example.com/boxic">
      <decision id="greeting" name="Greeting">
        <literalExpression>
          <text>"Hello " + name</text>
        </literalExpression>
      </decision>
    </definitions>
    \"""

    {:ok, model} = Boxic.DMN.load_xml(xml)
    :ok = Boxic.DMN.validate(model, for: :evaluation)
    :ok = Boxic.DMN.validate(model, for: :serialization)
    {:ok, "Hello Ada"} = Boxic.DMN.evaluate(model, "Greeting", %{"name" => "Ada"})
    """)

    run!("mix", ["run", "smoke.exs"], cd: project, env: env)
    verify_installed_package!(project, "boxic_feel")
    verify_installed_package!(project, "boxic_dmn")
    verify_standalone_mix_file!(project)
  end

  defp create_project!(project, app, module, env) do
    run!(
      "mix",
      ["new", project, "--app", app, "--module", module],
      cd: Path.dirname(project),
      env: env
    )
  end

  defp write_mix_file!(project, module, dependencies) do
    deps =
      Enum.map_join(dependencies, ",\n      ", fn {name, requirement} ->
        "{:#{name}, #{inspect(requirement)}}"
      end)

    File.write!(Path.join(project, "mix.exs"), """
    defmodule #{module}.MixProject do
      use Mix.Project

      def project do
        [
          app: :#{Macro.underscore(module)},
          version: "0.1.0",
          elixir: "~> 1.20",
          start_permanent: Mix.env() == :prod,
          deps: deps()
        ]
      end

      def application, do: [extra_applications: [:logger]]

      defp deps do
        [
          #{deps}
        ]
      end
    end
    """)
  end

  defp fetch_and_compile!(project, env) do
    run!("mix", ["deps.get"], cd: project, env: env)
    run!("mix", ["compile", "--warnings-as-errors"], cd: project, env: env)
  end

  defp verify_installed_package!(project, app) do
    package = Path.join([project, "deps", app])

    assert_directory!(package)

    Enum.each(@forbidden_directories, fn directory ->
      if File.exists?(Path.join(package, directory)) do
        Mix.raise("#{app} installed forbidden directory #{directory}")
      end
    end)
  end

  defp verify_standalone_mix_file!(project) do
    mix_file = File.read!(Path.join([project, "deps", "boxic_dmn", "mix.exs"]))

    case Enum.find(["in_umbrella", "../../", "path:"], &String.contains?(mix_file, &1)) do
      nil -> :ok
      marker -> Mix.raise("boxic_dmn package contains umbrella-relative marker #{marker}")
    end
  end

  defp consumer_env(root, workspace) do
    versions =
      root
      |> Path.join(".tool-versions")
      |> File.read!()
      |> String.split()
      |> Enum.chunk_every(2)
      |> Map.new(fn [tool, version] -> {tool, version} end)

    [
      {"HEX_HOME", Path.join(workspace, "hex")},
      {"HEX_NO_UPDATE_CHECK", "1"},
      {"ASDF_ELIXIR_VERSION", Map.fetch!(versions, "elixir")},
      {"ASDF_ERLANG_VERSION", Map.fetch!(versions, "erlang")}
    ]
  end

  defp run!(command, args, options) do
    {output, status} =
      System.cmd(command, args, Keyword.merge([stderr_to_stdout: true], options))

    if status != 0 do
      IO.write(output)
      Mix.raise("#{command} #{Enum.join(args, " ")} failed with exit status #{status}")
    end
  end

  defp assert_file!(path) do
    unless File.regular?(path), do: Mix.raise("required file does not exist: #{path}")
  end

  defp assert_directory!(path) do
    unless File.dir?(path), do: Mix.raise("required directory does not exist: #{path}")
  end

  defp workspace_path do
    suffix = System.unique_integer([:positive, :monotonic])
    Path.join(System.tmp_dir!(), "boxic-consumer-smoke-#{suffix}")
  end
end

Boxic.SmokeTestHexPackages.run(System.argv())
