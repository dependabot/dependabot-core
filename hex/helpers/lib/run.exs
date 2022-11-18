defmodule DependencyHelper do
  def main() do
    IO.read(:stdio, :all)
    |> Jason.decode!()
    |> run()
    |> case do
      {output, 0} ->
        if output =~ "No authenticated organization found" do
          {:error, output}
        else
          {:ok, :erlang.binary_to_term(output)}
        end

      {error, 1} ->
        {:error, error}
    end
    |> handle_result()
  end

  defp handle_result({:ok, {:ok, result}}) do
    encode_and_write(%{"result" => result})
  end

  defp handle_result({:ok, {:error, reason}}) do
    encode_and_write(%{"error" => reason})
    System.halt(1)
  end

  defp handle_result({:error, reason}) do
    encode_and_write(%{"error" => reason})
    System.halt(1)
  end

  defp encode_and_write(content) do
    content
    |> Jason.encode!()
    |> IO.write()
  end

  defp run(%{"function" => "parse", "args" => [dir]}) do
    run_script("parse_deps.exs", dir)
  end

  defp run(%{
         "function" => "get_latest_resolvable_version",
         "args" => [dir, dependency_name, credentials]
       }) do
    set_credentials(credentials)

    run_script("check_update.exs", dir, [dependency_name])
  end

  defp run(%{"function" => "get_updated_lockfile", "args" => [dir, dependency_name, credentials]}) do
    set_credentials(credentials)

    run_script("do_update.exs", dir, [dependency_name])
  end

  defp run_script(script, dir, args \\ []) do
    args =
      [
        "run",
        "--no-deps-check",
        "--no-start",
        "--no-compile",
        "--no-elixir-version-check",
        script
      ] ++ args

    System.cmd(
      "mix",
      args,
      cd: dir,
      env: %{
        "MIX_EXS" => nil,
        "MIX_LOCK" => nil,
        "MIX_DEPS" => nil
      }
    )
  end

  defp set_credentials([]), do: :ok

  defp set_credentials(["hex_organization", organization, token | tail]) do
    url =
      "hexpm"
      |> Hex.Repo.get_repo()
      |> Map.fetch!(:url)
      |> URI.merge("/repos/#{organization}")
      |> to_string()

    update_repos("hexpm:#{organization}", %{url: url, public_key: nil, auth_key: token})

    set_credentials(tail)
  end

  defp set_credentials(["hex_repository", repo, url, auth_key, fingerprint | tail]) do
    case fetch_public_key(repo, url, auth_key, fingerprint) do
      {:ok, public_key} ->
        update_repos(repo, %{auth_key: auth_key, public_key: public_key, url: url})

        set_credentials(tail)

      error ->
        handle_result(error)
    end
  end

  defp set_credentials([_mode, org_or_url | _]) do
    handle_result({:error, "Missing credentials for \"#{org_or_url}\""})
  end

  defp update_repos(name, opts) do
    Hex.Config.read()
    |> Hex.Config.read_repos()
    |> Map.put(name, opts)
    |> Hex.Config.update_repos()
  end

  defp fetch_public_key(repo, repo_url, auth_key, fingerprint) do
    case Hex.Repo.get_public_key(repo_url, auth_key) do
      {:ok, {200, key, _}} ->
        if public_key_matches?(key, fingerprint) do
          {:ok, key}
        else
          {:error, "Public key fingerprint mismatch for repo \"#{repo}\""}
        end

      {:ok, {code, _, _}} ->
        {:error, "Downloading public key for repo \"#{repo}\" failed with code: #{inspect(code)}"}

      other ->
        {:error, "Downloading public key for repo \"#{repo}\" failed: #{inspect(other)}"}
    end
  end

  defp public_key_matches?(_public_key, _fingerprint = ""), do: true

  defp public_key_matches?(public_key, fingerprint) do
    public_key =
      public_key
      |> :public_key.pem_decode()
      |> List.first()
      |> :public_key.pem_entry_decode()

    decoded_fingerprint =
      :sha256
      |> :ssh.hostkey_fingerprint(public_key)
      |> List.to_string()

    decoded_fingerprint == fingerprint
  end
end

DependencyHelper.main()
