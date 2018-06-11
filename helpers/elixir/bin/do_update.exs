defmodule Updater do
  def run(dependency_name, credentials) do
    set_credentials(credentials)

    # dependency atom
    dependency = String.to_atom(dependency_name)

    # Fetch dependencies that needs updating
    {dependency_lock, rest_lock} = Map.split(Mix.Dep.Lock.read(), [dependency])
    Mix.Dep.Fetcher.by_name([dependency_name], dependency_lock, rest_lock, [])

    # Remove any unused sub-dependencies. Currently do so by fetching all
    # dependencies, loading them, and then pruning the lockfile
    # (like deps.unlock --unused does)
    Mix.Dep.Fetcher.all(%{}, Mix.Dep.Lock.read(), [])
    apps = Mix.Dep.loaded([]) |> Enum.map(& &1.app)
    Mix.Dep.Lock.read() |> Map.take(apps) |> Mix.Dep.Lock.write()

    File.read("mix.lock")
  end

  defp set_credentials(credentials) do
    credentials
    |> Enum.reduce([], fn cred, acc ->
      if List.last(acc) == nil || List.last(acc)[:token] do
        acc = List.insert_at(acc, -1, %{organization: cred})
      else
        {item, acc} = List.pop_at(acc, -1)
        item = Map.put(item, :token, cred)
        acc = List.insert_at(acc, -1, item)
      end
    end)
    |> Enum.each(fn cred ->
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
    end)
  end
end

[dependency_name | credentials] = System.argv()
lockfile_content = :erlang.term_to_binary(Updater.run(dependency_name, credentials))
IO.write(:stdio, lockfile_content)
