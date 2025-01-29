defmodule DependabotCore.Mixfile do
  use Mix.Project

  def project do
    [
      app: :dependabot_core,
      version: "0.1.0",
      elixir: "~> 1.18",
      start_permanent: Mix.env == :prod,
      deps: []
    ]
  end

  def application do
    [extra_applications: [:hex, :logger, :ssh]]
  end
end
