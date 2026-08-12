Mix.ensure_application!(:hex)

credential = System.fetch_env!("DEPENDABOT_HEX_CREDENTIAL_TOKEN")

args = Enum.drop_while(System.argv(), &(&1 == "--"))

case args do
  ["organization", organization] ->
    Mix.Task.get!("hex.organization").run(["auth", organization, "--key", credential])

  ["repository", repo, url, fingerprint] ->
    args = ["add", repo, url, "--auth-key", credential]
    args = if fingerprint == "", do: args, else: args ++ ["--fetch-public-key", fingerprint]
    Mix.Task.get!("hex.repo").run(args)
end
