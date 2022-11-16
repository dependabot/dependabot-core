defmodule UpdateChecker do
  def run(dependency_name) do
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

      {:ok, {:error, error}} ->
        {:error, error}

      nil ->
        {:error, :dependency_resolution_timed_out}

      {:exit, reason} ->
        {:error, reason}
    end
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

[dependency_name] = System.argv()

case UpdateChecker.run(dependency_name) do
  {:ok, version} ->
    version = :erlang.term_to_binary({:ok, version})
    IO.write(:stdio, version)

  {:error, %Version.InvalidRequirementError{} = error}  ->
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
