defmodule Coxir.Mixfile do
  use Mix.Project

  def project do
    [
      app: :coxir,
      version: "0.8.0",
      elixir: "~> 1.5",
      build_embedded: Mix.env == :prod,
      start_permanent: Mix.env == :prod,
      deps: deps(),

      name: "coxir",
      docs: docs(),
      package: package(),
      description: "An Elixir wrapper for Discord.",
      source_url: "https://github.com/satom99/coxir"
    ]
  end

  def application do
    [
      mod: {Coxir, []}
    ]
  end

  defp deps do
    [
      {:kcl, "~> 1.1"},
      {:jason, "~> 1.1"},
      {:porcelain, "~> 2.0"},
      {:websockex, "~> 0.4.1"},
      {:httpoison, "~> 0.13.0"},
      {:gen_stage, "~> 0.14.0"},
      {:ex_doc, "~> 0.18.1", only: :dev}
    ]
  end

  defp package do
    [
      licenses: ["Apache-2.0"],
      maintainers: ["Santiago Tortosa"],
      links: %{"GitHub" => "https://github.com/satom99/coxir"}
    ]
  end

  defp docs do
    [
      main: "overview",
      extras: [
        "docs/Overview.md"
      ],
      groups_for_extras: [
        "Introduction": ~r/docs\/.?/
      ]
    ]
  end
end
