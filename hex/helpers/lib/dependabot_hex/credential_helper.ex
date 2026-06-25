defmodule DependabotHex.CredentialHelper do
  def set_credentials([]), do: :ok

  def set_credentials(["hex_organization", organization, token | tail]) do
    url =
      "hexpm"
      |> Hex.Repo.get_repo()
      |> Map.fetch!(:url)
      |> URI.merge("/repos/#{organization}")
      |> to_string()

    update_repos("hexpm:#{organization}", %{url: url, public_key: nil, auth_key: token})

    set_credentials(tail)
  end

  def set_credentials(["hex_repository", repo, url, auth_key, fingerprint | tail]) do
    case fetch_public_key(repo, url, auth_key, fingerprint) do
      {:ok, public_key} ->
        update_repos(repo, %{auth_key: auth_key, public_key: public_key, url: url})
        set_credentials(tail)

      {:error, _} = error ->
        error
    end
  end

  def set_credentials([_mode, org_or_url | _]) do
    {:error, "Missing credentials for \"#{org_or_url}\""}
  end

  defp update_repos(name, opts) do
    Hex.Config.read()
    |> Hex.Config.read_repos()
    |> Map.put(name, opts)
    |> Hex.Config.update_repos()
  end

  defp fetch_public_key(repo, repo_url, auth_key, fingerprint) do
    case Hex.Repo.get_public_key(%{trusted: true, url: repo_url, auth_key: auth_key}) do
      {:ok, {200, _headers, key}} ->
        try do
          if public_key_matches?(key, fingerprint) do
            {:ok, key}
          else
            {:error, "Public key fingerprint mismatch for repo \"#{repo}\""}
          end
        rescue
          e in FunctionClauseError ->
            {:error,
             "Failed to decode public key for repo \"#{repo}\": " <>
               "#{Exception.message(e)} (#{inspect(e.__struct__)})"}
        end

      {:ok, {code, _headers, _body}} ->
        {:error, "Downloading public key for repo \"#{repo}\" failed with code: #{inspect(code)}"}

      other ->
        {:error, "Downloading public key for repo \"#{repo}\" failed: #{inspect(other)}"}
    end
  end

  defp public_key_matches?(_public_key, ""), do: true

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
