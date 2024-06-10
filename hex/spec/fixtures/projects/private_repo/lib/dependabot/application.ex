defmodule Dependabot.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    port = Application.fetch_env!(:dependabot, :port)

    children = [
      {Plug.Cowboy, scheme: :http, plug: Dependabot.Plug, options: [port: port]}
    ]

    Supervisor.start_link(children, strategy: :one_for_one, name: Dependabot.Supervisor)
  end
end
