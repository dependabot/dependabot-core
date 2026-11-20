# Log to stderr instead of stdout
:logger.remove_handler(:default)
:logger.add_handler(:to_stderr, :logger_std_h, %{config: %{type: :standard_error}})

defmodule UpdateChecker do
  def run(dependency_name) do
    # This is necessary because we can't specify :extra_applications to have :hex in other mixfiles.
    Mix.ensure_application!(:hex)

    # Mix only knows about transitive dependencies once their parents are
    # fetched, so only name declared ones. Removing a dependency from the
    # lock is enough for Hex to unlock it.
    names = if declared?(dependency_name), do: [dependency_name], else: []

    # Update the lockfile in a session that we can time out
    task = Task.async(fn -> do_resolution(dependency_name, names) end)

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

  defp do_resolution(dependency_name, names) do
    # Fetch dependencies that needs updating
    {dependency_lock, rest_lock} =
      Map.split(Mix.Dep.Lock.read(), [String.to_atom(dependency_name)])

    try do
      Mix.Dep.Fetcher.by_name(names, dependency_lock, rest_lock, [])

      {:ok, :resolution_successful}
    rescue
      error -> {:error, error}
    end
  end

  defp declared?(dependency_name) do
    Enum.any?(Mix.Dep.Converger.converge(), &(Atom.to_string(&1.app) == dependency_name))
  rescue
    # Leave it to the resolution to report the error
    _error -> true
  end
end

[dependency_name] = System.argv()

result =
  case UpdateChecker.run(dependency_name) do
    {:ok, version} ->
      {:ok, version}

    {:error, %Version.InvalidRequirementError{} = error}  ->
      {:error, "Invalid requirement: #{error.requirement}"}

    {:error, %Mix.Error{} = error} ->
      {:error, "Dependency resolution failed: #{error.message}"}

    {:error, :dependency_resolution_timed_out} ->
      # We do nothing here because Hex is already printing out a message in stdout
      nil

    {:error, error} ->
      {:error, "Unknown error in check_update: #{inspect(error)}"}
  end

if not is_nil(result) do
  result
  |> :erlang.term_to_binary()
  |> Base.encode64()
  |> IO.write()
end
