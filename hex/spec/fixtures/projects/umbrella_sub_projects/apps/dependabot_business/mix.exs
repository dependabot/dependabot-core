defmodule DependabotBusiness.MixProject do
  use Mix.Project

  def project do
    [
      app: :dependabot_business,
      version: "0.1.0",
      build_path: "../../_build",
      config_path: "../../config/config.exs",
      deps_path: "../../deps",
      lockfile: "../../mix.lock",
      elixir: "~> 1.6",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      {:plug, "~> 1.3.0"},
      {:jason, "~> 1.0"}
    ]
  end
end
