# Log to stderr instead of stdout
:logger.remove_handler(:default)
:logger.add_handler(:to_stderr, :logger_std_h, %{config: %{type: :standard_error}})

defmodule UpdateChecker do
  def run(dependency_name) do
    # This is necessary because we can't specify :extra_applications to have :hex in other mixfiles.
    Mix.ensure_application!(:hex)

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
    try do
      Mix.Task.get!("deps.update").run([dependency_name, "--no-archives-check"])

      {:ok, :resolution_successful}
    rescue
      error -> {:error, error}
    end
  end
end

[dependency_name] = Enum.drop_while(System.argv(), &(&1 == "--"))

case UpdateChecker.run(dependency_name) do
  {:ok, version} ->
    File.write!(".dependabot-result", version)

  {:error, %Version.InvalidRequirementError{} = error} ->
    Mix.raise("Invalid requirement: #{error.requirement}")

  {:error, %Mix.Error{} = error} ->
    Mix.raise("Dependency resolution failed: #{error.message}")

  {:error, :dependency_resolution_timed_out} ->
    Mix.raise("Dependency resolution timed out")

  {:error, error} ->
    Mix.raise("Unknown error in check_update: #{inspect(error)}")
end
