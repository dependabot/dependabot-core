defmodule DependabotHexCredentials do
  def run do
    Mix.ensure_application!(:hex)
    {:ok, _applications} = Application.ensure_all_started(:hex)

    credential = System.get_env("DEPENDABOT_HEX_CREDENTIAL_TOKEN", "")
    public_key = System.get_env("DEPENDABOT_HEX_PUBLIC_KEY", "")
    repository_url = System.get_env("DEPENDABOT_HEX_REPOSITORY_URL_TOKEN", "")
    args = Enum.drop_while(System.argv(), &(&1 == "--"))

    configure(args, credential, public_key, repository_url)
  end

  defp configure(["organization", organization], credential, _public_key, _repository_url) do
    case Mix.Task.get!("hex.organization").run(["auth", organization, "--key=#{credential}"]) do
      :error ->
        :error

      _ ->
        Mix.Task.get!("hex.repo").run([
          "set",
          "hexpm:#{organization}",
          "--no-oauth-exchange"
        ])
    end
  end

  defp configure(["repository", repo, fingerprint], credential, public_key, repository_url) do
    args =
      ["add", repo, repository_url, "--no-oauth-exchange"]
      |> append_auth_key(credential)

    case {fingerprint, public_key} do
      {"", ""} ->
        Mix.raise("Missing public key or public key fingerprint for repo \"#{repo}\"")

      {fingerprint, ""} ->
        Mix.Task.get!("hex.repo").run(args ++ ["--fetch-public-key", fingerprint])

      {"", public_key} ->
        run_repo_task(args, repo, public_key)

      {fingerprint, public_key} ->
        verify_public_key!(repo, public_key, fingerprint)
        run_repo_task(args, repo, public_key)
    end
  end

  defp run_repo_task(args, repo, public_key) do
    directory = Path.join(System.fetch_env!("HEX_HOME"), "dependabot-tmp")
    File.mkdir_p!(directory)
    path = Path.join(directory, "public-key-#{random_suffix()}.pem")

    case File.open(path, [:write, :exclusive]) do
      {:ok, file} ->
        try do
          IO.binwrite(file, public_key)
          :ok = :file.sync(file)
          run_repo_task_with_public_key(args, repo, path, public_key)
        after
          File.close(file)
          File.rm(path)
        end

      {:error, :eexist} ->
        run_repo_task(args, repo, public_key)

      {:error, reason} ->
        raise File.Error, reason: reason, action: "open", path: path
    end
  end

  defp run_repo_task_with_public_key(args, repo, path, public_key) do
    Mix.Task.get!("hex.repo").run(args ++ ["--public-key", path])
  rescue
    error in Mix.Error ->
      if malformed_public_key_error?(error.message, public_key) do
        Mix.raise("Could not decode public key for repo \"#{repo}\"")
      else
        reraise error, __STACKTRACE__
      end
  end

  defp malformed_public_key_error?(message, public_key) do
    expected =
      "Could not decode public key. The public key contents are shown below.\n\n" <>
        public_key <>
        "\n\nPublic keys must be valid and be in the PEM format."

    String.trim(message) == String.trim(expected)
  end

  defp verify_public_key!(repo, public_key, fingerprint) do
    Hex.Stdlib.ensure_application!(:ssh)

    unless public_key_matches_fingerprint?(repo, public_key, fingerprint) do
      Mix.raise("Public key fingerprint mismatch for repo \"#{repo}\"")
    end
  end

  defp public_key_matches_fingerprint?(repo, public_key, fingerprint) do
    :mix_hex_repo.fingerprint_equal(public_key, fingerprint)
  rescue
    _error in [MatchError, FunctionClauseError] ->
      Mix.raise("Could not decode public key for repo \"#{repo}\"")

    error in ErlangError ->
      case error.original do
        :missing_padding ->
          Mix.raise("Could not decode public key for repo \"#{repo}\"")

        _reason ->
          reraise error, __STACKTRACE__
      end
  end

  defp random_suffix do
    24
    |> :crypto.strong_rand_bytes()
    |> Base.url_encode64(padding: false)
  end

  defp append_auth_key(args, ""), do: args
  defp append_auth_key(args, value), do: args ++ ["--auth-key=#{value}"]
end

DependabotHexCredentials.run()
