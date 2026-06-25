defmodule DependabotHex.Application do
  @moduledoc false

  use Application

  alias DependabotHex.CLI

  @impl Application
  def start(_start_type, _start_args) do
    Mix.start()
    Mix.ensure_application!(:hex)
    Mix.shell(Mix.Shell.Quiet)
    exit_code = CLI.main(System.argv())
    System.halt(exit_code)
  end
end
