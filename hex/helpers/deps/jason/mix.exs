defmodule Jason.Mixfile do
  use Mix.Project

  @version "1.1.2"

  def project() do
    [
      app: :jason,
      version: @version,
      elixir: "~> 1.4",
      start_permanent: Mix.env() == :prod,
      consolidate_protocols: Mix.env() != :test,
      deps: deps(),
      aliases: aliases(),
      preferred_cli_env: ["bench.encode": :bench, "bench.decode": :bench, docs: :docs],
      dialyzer: dialyzer(),
      description: description(),
      package: package(),
      docs: docs()
    ]
  end

  def application() do
    [
      extra_applications: []
    ]
  end

  defp deps() do
    [
      {:decimal, "~> 1.0", optional: true},
      {:benchee, "~> 0.8", only: :bench},
      {:benchee_html, "~> 0.1", only: :bench, github: "michalmuskala/benchee_html"},
      {:poison, "~> 3.0", only: :bench},
      {:exjsx, "~> 4.0", only: :bench},
      {:tiny, "~> 1.0", only: :bench},
      {:jsone, "~> 1.4", only: :bench},
      {:jiffy, "~> 0.14", only: :bench},
      {:json, "~> 1.0", only: :bench},
      {:dialyxir, "~> 0.5", only: [:dev, :test], runtime: false},
      {:ex_doc, "~> 0.18", only: :docs},
    ] ++ maybe_stream_data()
  end

  defp maybe_stream_data() do
    if Version.match?(System.version(), "~> 1.5") do
      [{:stream_data, "~> 0.4", only: :test}]
    else
      []
    end
  end

  defp aliases() do
    [
      "bench.encode": ["run bench/encode.exs"],
      "bench.decode": ["run bench/decode.exs"]
    ]
  end

  defp dialyzer() do
    [
      ignore_warnings: "dialyzer.ignore"
    ]
  end

  defp description() do
    """
    A blazing fast JSON parser and generator in pure Elixir.
    """
  end

  defp package() do
    [
      maintainers: ["Michał Muskała"],
      licenses: ["Apache 2.0"],
      links: %{"GitHub" => "https://github.com/michalmuskala/jason"}
    ]
  end

  defp docs() do
    [
      main: "readme",
      name: "Jason",
      source_ref: "v#{@version}",
      canonical: "http://hexdocs.pm/jason",
      source_url: "https://github.com/michalmuskala/jason",
      extras: [
        "README.md"
      ]
    ]
  end
end
