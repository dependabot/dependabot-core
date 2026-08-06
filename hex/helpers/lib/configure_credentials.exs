defmodule DependabotHexCredentials do
  def run do
    Mix.ensure_application!(:hex)
    {:ok, _applications} = Application.ensure_all_started(:hex)

    credential = System.get_env("DEPENDABOT_HEX_CREDENTIAL_TOKEN", "")
    public_key = System.get_env("DEPENDABOT_HEX_PUBLIC_KEY", "")
    args = Enum.drop_while(System.argv(), &(&1 == "--"))

    configure(args, credential, public_key)
  end

  defp configure(["organization", organization], credential, _public_key) do
    Mix.Task.get!("hex.organization").run(["auth", organization, "--key", credential])
  end

  defp configure(["repository", repo, url, fingerprint], credential, public_key) do
    args =
      ["add", repo, url]
      |> append_option("--auth-key", credential)
      |> append_option("--fetch-public-key", fingerprint)

    run_repo_task(args, public_key)
  end

  defp run_repo_task(args, ""), do: Mix.Task.get!("hex.repo").run(args)

  defp run_repo_task(args, public_key) do
    path =
      Path.join(
        System.tmp_dir!(),
        "dependabot-hex-public-key-#{System.unique_integer([:positive])}.pem"
      )

    File.write!(path, public_key)

    try do
      Mix.Task.get!("hex.repo").run(args ++ ["--public-key", path])
    after
      File.rm(path)
    end
  end

  defp append_option(args, _option, ""), do: args
  defp append_option(args, option, value), do: args ++ [option, value]
end

DependabotHexCredentials.run()
