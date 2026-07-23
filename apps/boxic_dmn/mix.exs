defmodule BoxicDmn.MixProject do
  use Mix.Project

  @version "0.2.0"
  @boxic_feel_requirement "~> 0.1.0"
  @source_url "https://github.com/koenusz/boxic"

  def project do
    [
      app: :boxic_dmn,
      version: @version,
      build_path: "../../_build",
      config_path: "../../config/config.exs",
      deps_path: "../../deps",
      lockfile: "../../mix.lock",
      elixir: "~> 1.20.0",
      start_permanent: Mix.env() == :prod,
      test_coverage: [summary: [threshold: 50]],
      description: description(),
      package: package(),
      source_url: @source_url,
      homepage_url: @source_url,
      docs: docs(),
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger, :xmerl]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      boxic_feel_dependency(),
      {:ex_doc, "~> 0.38", only: :dev, runtime: false}
    ]
  end

  # Hex packages can depend only on other Hex packages, while local umbrella
  # development should compile the sibling source. The packaged mix.exs also
  # selects Hex automatically because the sibling directory is absent.
  defp boxic_feel_dependency do
    sibling? = File.dir?(Path.expand("../boxic_feel", __DIR__))
    hex_build? = System.get_env("BOXIC_DMN_HEX_BUILD") in ["1", "true"]

    if sibling? and not hex_build? do
      {:boxic_feel, @boxic_feel_requirement, in_umbrella: true}
    else
      {:boxic_feel, @boxic_feel_requirement}
    end
  end

  defp description do
    "A native Elixir loader, validator, and evaluator for Decision Model and Notation 1.5 models."
  end

  defp package do
    [
      files:
        ~w(lib priv mix.exs README.md LICENSE CHANGELOG.md CONFORMANCE.md CONSTRUCT_CAPABILITY_LEDGER.md),
      licenses: ["Apache-2.0"],
      links: %{
        "Changelog" => "#{@source_url}/blob/main/apps/boxic_dmn/CHANGELOG.md",
        "GitHub" => @source_url,
        "HexDocs" => "https://hexdocs.pm/boxic_dmn"
      }
    ]
  end

  defp docs do
    [
      main: "readme",
      extras: [
        "README.md",
        "CONFORMANCE.md",
        "CONSTRUCT_CAPABILITY_LEDGER.md",
        "CHANGELOG.md"
      ],
      source_ref: "v#{@version}",
      groups_for_modules: [
        "Public API": [
          Boxic.DMN,
          Boxic.DMN.Authoring.DecisionTable,
          Boxic.DMN.AuthoringError,
          Boxic.DMN.Diagnostic,
          Boxic.DMN.SerializationError
        ],
        "Normalized model": ~r/^Boxic\.DMN\.Model/
      ]
    ]
  end
end
