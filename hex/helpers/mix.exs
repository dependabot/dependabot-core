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
        :hex,
        :nerves_bootstrap
      ]
    ]
  end

  defp releases do
    [
      dependabot_hex_linux_x86_64: [
        steps: [:assemble, &Burrito.wrap/1],
        burrito: [targets: [target: [os: :linux, cpu: :x86_64, erts_source: {:runtime, []}]]]
      ],
      dependabot_hex_linux_aarch64: [
        steps: [:assemble, &Burrito.wrap/1],
        burrito: [targets: [target: [os: :linux, cpu: :aarch64, erts_source: {:runtime, []}]]]
      ],
      dependabot_hex_darwin_x86_64: [
        steps: [:assemble, &Burrito.wrap/1],
        burrito: [targets: [target: [os: :darwin, cpu: :x86_64]]]
      ],
      dependabot_hex_darwin_aarch64: [
        steps: [:assemble, &Burrito.wrap/1],
        burrito: [targets: [target: [os: :darwin, cpu: :aarch64]]]
      ]
    ]
  end

  defp deps do
    [
      {:burrito, "~> 1.0"}
    ]
  end

  defp archives do
    [
      {:hex, "~> 2.3"},
      {:nerves_bootstrap, "~> 1.0"}
    ]
  end
end
