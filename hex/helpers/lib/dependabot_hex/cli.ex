defmodule DependabotHex.CLI do
  alias DependabotHex.CredentialHelper
  alias DependabotHex.Parser
  alias DependabotHex.UpdateChecker
  alias DependabotHex.Updater

  def main(["--install" | _]) do
    # Burrito handles installation before this point; this flag just allows
    # pre-warming the Burrito payload extraction during Docker image builds.
    0
  end

  def main(_argv) do
    IO.read(:stdio, :eof)
    |> JSON.decode!()
    |> run()
    |> handle_result()
  end

  defp run(%{"function" => "parse", "args" => [dir]}) do
    Parser.run(dir)
  end

  defp run(%{
         "function" => "get_latest_resolvable_version",
         "args" => [dir, dependency_name, credentials]
       }) do
    with :ok <- CredentialHelper.set_credentials(credentials) do
      UpdateChecker.run(dir, dependency_name)
    end
  end

  defp run(%{"function" => "get_updated_lockfile", "args" => [dir, dependency_name, credentials]}) do
    with :ok <- CredentialHelper.set_credentials(credentials) do
      Updater.run(dir, dependency_name)
    end
  end

  defp run(%{"function" => "hex_info", "args" => []}) do
    {:ok,
     %{
       hex_version: Application.spec(:hex, :vsn) |> to_string(),
       elixir_version: System.version()
     }}
  end

  defp run(%{"function" => "remove_repo", "args" => [repo]}) do
    Hex.Config.read()
    |> Hex.Config.read_repos()
    |> Map.delete(repo)
    |> Hex.Config.update_repos()

    {:ok, nil}
  end

  defp handle_result({:ok, result}) do
    encode_and_write(%{"result" => result})
    0
  end

  defp handle_result({:error, reason}) when is_binary(reason) do
    encode_and_write(%{"error" => reason})
    1
  end

  defp handle_result({:error, reason}) do
    encode_and_write(%{"error" => inspect(reason)})
    1
  end

  defp encode_and_write(content) do
    content
    |> JSON.encode!()
    |> IO.write()
  end
end
