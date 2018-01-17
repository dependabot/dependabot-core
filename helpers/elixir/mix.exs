defmodule DependabotCore.Mixfile do
  use Mix.Project

  def project do
    [app: :dependabot_core,
     version: "0.1.0",
     elixir: "~> 1.5",
     start_permanent: Mix.env == :prod,
     lockfile: System.get_env("MIX_LOCK") || "mix.lock",
     deps_path: System.get_env("MIX_DEPS") || "deps",
     deps: deps()]
  end

  def application do
    [extra_applications: [:logger]]
  end

  defp deps() do
    [{:jason, "~> 1.0-rc"}]
  end
end
