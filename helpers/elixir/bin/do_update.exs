[dependency_name | credentials] = System.argv()

grouped_creds = Enum.reduce credentials, [], fn cred, acc ->
  if List.last(acc) == nil || List.last(acc)[:token] do
    List.insert_at(acc, -1, %{ organization: cred })
  else
    { item, acc } = List.pop_at(acc, -1)
    item = Map.put(item, :token, cred)
    List.insert_at(acc, -1, item)
  end
end

Enum.each grouped_creds, fn cred ->
  hexpm = Hex.Repo.get_repo("hexpm")
  repo = %{
    url: hexpm.url <> "/repos/#{cred.organization}",
    public_key: nil,
    auth_key: cred.token
  }

  Hex.Config.read()
  |> Hex.Config.read_repos()
  |> Map.put("hexpm:#{cred.organization}", repo)
  |> Hex.Config.update_repos()
end

# dependency atom
dependency = String.to_atom(dependency_name)

# Fetch dependencies that needs updating
{dependency_lock, rest_lock} = Map.split(Mix.Dep.Lock.read(), [dependency])
Mix.Dep.Fetcher.by_name([dependency_name], dependency_lock, rest_lock, [])

lockfile_content =
  "mix.lock"
  |> File.read()
  |> :erlang.term_to_binary()

IO.write(:stdio, lockfile_content)
