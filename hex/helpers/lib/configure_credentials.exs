defmodule DependabotHexCredentials do
  @public_key_path ".dependabot-hex-public-key.pem"

  def run do
    Mix.ensure_application!(:hex)

    credential = System.fetch_env!("DEPENDABOT_HEX_CREDENTIAL_TOKEN")
    public_key = System.get_env("DEPENDABOT_HEX_PUBLIC_KEY", "")
    args = Enum.drop_while(System.argv(), &(&1 == "--"))

    configure(args, credential, public_key)
  end

  defp configure(["organization", organization], credential, _public_key) do
    Mix.Task.get!("hex.organization").run(["auth", organization, "--key", credential])
  end

  defp configure(["repository", repo, url, fingerprint], credential, "") do
    args = ["add", repo, url, "--auth-key", credential]
    args = if fingerprint == "", do: args, else: args ++ ["--fetch-public-key", fingerprint]
    Mix.Task.get!("hex.repo").run(args)
  end

  defp configure(["repository", repo, url, fingerprint], credential, public_key) do
    unless public_key_matches?(public_key, fingerprint) do
      Mix.raise("Public key fingerprint mismatch for repo \"#{repo}\"")
    end

    File.write!(@public_key_path, public_key)

    try do
      Mix.Task.get!("hex.repo").run([
        "add",
        repo,
        url,
        "--auth-key",
        credential,
        "--public-key",
        @public_key_path
      ])
    after
      File.rm(@public_key_path)
    end
  end

  defp public_key_matches?(_public_key, ""), do: true

  defp public_key_matches?(public_key, fingerprint) do
    decoded_public_key =
      public_key
      |> :public_key.pem_decode()
      |> List.first()
      |> :public_key.pem_entry_decode()

    :sha256
    |> :ssh.hostkey_fingerprint(decoded_public_key)
    |> List.to_string()
    |> Kernel.==(fingerprint)
  end
end

DependabotHexCredentials.run()
