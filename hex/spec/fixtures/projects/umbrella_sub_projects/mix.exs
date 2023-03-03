defmodule DependabotUmbrella.MixProject do
  use Mix.Project

  def project do
    [
      app: :dependabot_test,
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  defp deps do
    [
      {:distillery, "~> 1.5", runtime: false},
      {:dependabot_business, path: "apps/dependabot_business", from_umbrella: true},
      {:dependabot_web, path: "apps/dependabot_web", from_umbrella: true}
    ]
  end
end
