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
    Mix.Task.get!("hex.organization").run(["auth", organization, "--key", credential])
  end

  defp configure(["repository", repo, fingerprint], credential, public_key, repository_url) do
    args =
      ["add", repo, repository_url]
      |> append_option("--auth-key", credential)
      |> append_option("--fetch-public-key", fingerprint)

    run_repo_task(args, public_key)
  end

  defp run_repo_task(args, ""), do: Mix.Task.get!("hex.repo").run(args)

  defp run_repo_task(args, public_key) do
    directory = Path.join(System.fetch_env!("HEX_HOME"), "dependabot-tmp")
    File.mkdir_p!(directory)
    path = Path.join(directory, "public-key-#{random_suffix()}.pem")

    case File.open(path, [:write, :exclusive]) do
      {:ok, file} ->
        try do
          IO.binwrite(file, public_key)
          :ok = :file.sync(file)
          Mix.Task.get!("hex.repo").run(args ++ ["--public-key", path])
        after
          File.close(file)
          File.rm(path)
        end

      {:error, :eexist} ->
        run_repo_task(args, public_key)

      {:error, reason} ->
        raise File.Error, reason: reason, action: "open", path: path
    end
  end

  defp random_suffix do
    24
    |> :crypto.strong_rand_bytes()
    |> Base.url_encode64(padding: false)
  end

  defp append_option(args, _option, ""), do: args
  defp append_option(args, option, value), do: args ++ [option, value]
end

DependabotHexCredentials.run()
