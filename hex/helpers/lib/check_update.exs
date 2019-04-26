defmodule UpdateChecker do
  def run(dependency_name, credentials) do
    set_credentials(credentials)

    # Update the lockfile in a session that we can time out
    task = Task.async(fn -> do_resolution(dependency_name) end)
    case Task.yield(task, 30000) || Task.shutdown(task) do
      {:ok, {:ok, :resolution_successful}} ->
        # Read the new lock
        {updated_lock, _updated_rest_lock} =
          Map.split(Mix.Dep.Lock.read(), [String.to_atom(dependency_name)])

        # Get the new dependency version
        version =
          updated_lock
          |> Map.get(String.to_atom(dependency_name))
          |> elem(2)
        {:ok, version}

      {:ok, {:error, error}} -> {:error, error}

      nil -> {:error, :dependency_resolution_timed_out}

      {:exit, reason} -> {:error, reason}
    end
  end

  defp set_credentials(credentials) do
    credentials
    |> Enum.reduce([], fn cred, acc ->
      if List.last(acc) == nil || List.last(acc)[:token] do
        List.insert_at(acc, -1, %{organization: cred})
      else
        {item, acc} = List.pop_at(acc, -1)
        item = Map.put(item, :token, cred)
        List.insert_at(acc, -1, item)
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

  defp do_resolution(dependency_name) do
    # Fetch dependencies that needs updating
    {dependency_lock, rest_lock} =
      Map.split(Mix.Dep.Lock.read(), [String.to_atom(dependency_name)])

    try do
      Mix.Dep.Fetcher.by_name([dependency_name], dependency_lock, rest_lock, [])
      {:ok, :resolution_successful}
    rescue
      error -> {:error, error}
    end
  end
end

[dependency_name | credentials] = System.argv()


case UpdateChecker.run(dependency_name, credentials) do
  {:ok, version} ->
    version = :erlang.term_to_binary({:ok, version})
    IO.write(:stdio, version)

  {:error, %Hex.Version.InvalidRequirementError{} = error}  ->
    result = :erlang.term_to_binary({:error, "Invalid requirement: #{error.requirement}"})
    IO.write(:stdio, result)

  {:error, %Mix.Error{} = error} ->
    result = :erlang.term_to_binary({:error, "Dependency resolution failed: #{error.message}"})
    IO.write(:stdio, result)

  {:error, :dependency_resolution_timed_out} ->
    # We do nothing here because Hex is already printing out a message in stdout
    nil

  {:error, error} ->
    result = :erlang.term_to_binary({:error, "Unknown error in check_update: #{inspect(error)}"})
    IO.write(:stdio, result)
end
