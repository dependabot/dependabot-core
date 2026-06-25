defmodule DependabotHex.MixProject do
  use Mix.Project

  def project do
    [
      app: :dependabot_hex,
      version: "0.1.0",
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      releases: releases(),
      archives: archives()
    ]
  end

  def application do
    [
      mod: {DependabotHex.Application, []},
      extra_applications: [
        :logger,
        :mix,
        :ssh,
        :crypto,
        :public_key
      ],
      included_applications: [
        # Hex is already included in sbom, duplicates are not allowed
        # :hex,
        :nerves_bootstrap
      ]
    ]
  end

  defp releases do
    [
      dependabot_hex: [
        include_executables_for: [:unix]
      ]
    ]
  end

  defp deps do
    [
      {:sbom, "~> 0.10"}
    ]
  end

  defp archives do
    [
      {:hex, "~> 2.3"},
      {:nerves_bootstrap, "~> 1.0"}
    ]
  end
end
