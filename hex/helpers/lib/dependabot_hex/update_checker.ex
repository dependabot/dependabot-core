defmodule DependabotHex.UpdateChecker do
  def run(dir, dependency_name) do
    Mix.ProjectStack.on_clean_slate(fn ->
      Mix.Project.in_project(app_name(dir), dir, fn _module ->
        task = Task.async(fn -> do_resolution(dependency_name) end)

        case Task.yield(task, 30_000) || Task.shutdown(task) do
          {:ok, {:ok, :resolution_successful}} ->
            {updated_lock, _rest} =
              Map.split(Mix.Dep.Lock.read(), [String.to_atom(dependency_name)])

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
      end)
    end)
  end

  defp app_name(dir),
    do:
      dir
      |> :erlang.crc32()
      |> Integer.digits(26)
      |> Enum.map(&(&1 + ?a))
      |> List.to_string()
      |> String.to_atom()

  defp do_resolution(dependency_name) do
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
