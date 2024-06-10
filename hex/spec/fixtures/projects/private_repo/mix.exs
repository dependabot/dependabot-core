defmodule Dependabot.MixProject do
  use Mix.Project

  def project do
    [
      app: :dependabot,
      version: "0.1.0",
      elixir: "~> 1.13",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  def application do
    [
      extra_applications: [:logger],
      mod: {Dependabot.Application, []}
    ]
  end

  defp deps do
    [
      {:plug, "~> 1.13"},
      {:plug_cowboy, "~> 2.5"}
    ]
  end
end
