defmodule BoxicFeel.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/koenusz/boxic"

  def project do
    [
      app: :boxic_feel,
      version: @version,
      build_path: "../../_build",
      config_path: "../../config/config.exs",
      deps_path: "../../deps",
      lockfile: "../../mix.lock",
      elixir: "~> 1.19",
      start_permanent: Mix.env() == :prod,
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
      extra_applications: [:logger]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:decimal, "~> 2.1"},
      {:tzdata, "~> 1.1.4"},
      {:ex_doc, "~> 0.38", only: :dev, runtime: false}
    ]
  end

  defp description do
    "A native Elixir parser and evaluator for the Friendly Enough Expression Language defined by DMN."
  end

  defp package do
    [
      files: ~w(lib mix.exs README.md LICENSE CHANGELOG.md),
      licenses: ["Apache-2.0"],
      links: %{
        "Changelog" => "#{@source_url}/blob/main/apps/boxic_feel/CHANGELOG.md",
        "GitHub" => @source_url,
        "HexDocs" => "https://hexdocs.pm/boxic_feel"
      }
    ]
  end

  defp docs do
    [
      main: "readme",
      extras: ["README.md", "CHANGELOG.md"],
      source_ref: "v#{@version}",
      groups_for_modules: [
        "Public API": [Boxic.FEEL, Boxic.FEEL.ExternalFunctions],
        "FEEL values": [
          Boxic.FEEL.DateTime,
          Boxic.FEEL.Duration,
          Boxic.FEEL.Function,
          Boxic.FEEL.Range,
          Boxic.FEEL.Time
        ]
      ]
    ]
  end
end
