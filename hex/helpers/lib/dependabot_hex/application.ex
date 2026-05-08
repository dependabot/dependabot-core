defmodule DependabotHex.Application do
  @moduledoc false

  use Application

  alias Burrito.Util.Args
  alias DependabotHex.CLI

  @impl Application
  def start(_start_type, _start_args) do
    Application.ensure_all_started(:hex)

    if Burrito.Util.running_standalone?() do
      Mix.shell(Mix.Shell.Quiet)
      exit_code = CLI.main(Args.argv())
      System.stop(exit_code)
    end

    Supervisor.start_link([], strategy: :one_for_one)
  end
end
