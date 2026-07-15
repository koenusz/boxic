defmodule ArbiterDmnTck.MixProject do
  use Mix.Project

  def project do
    [
      app: :arbiter_dmn_tck,
      version: "0.1.0",
      build_path: "../../_build",
      config_path: "../../config/config.exs",
      deps_path: "../../deps",
      lockfile: "../../mix.lock",
      elixir: "~> 1.19",
      start_permanent: Mix.env() == :prod,
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
      {:arbiter_dmn, in_umbrella: true},
      {:jason, "~> 1.4"}
    ]
  end
end
