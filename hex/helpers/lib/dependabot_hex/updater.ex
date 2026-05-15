defmodule DependabotHex.Updater do
  def run(dir, dependency_name) do
    Mix.ProjectStack.on_clean_slate(fn ->
      Mix.Project.in_project(app_name(dir), dir, fn _module ->
        {dependency_lock, rest_lock} =
          Map.split(Mix.Dep.Lock.read(), [String.to_atom(dependency_name)])

        Mix.Dep.Fetcher.by_name([dependency_name], dependency_lock, rest_lock, [])

        Mix.Task.rerun("deps.get", ["--no-compile", "--no-elixir-version-check"])

        case File.read(Path.join(dir, "mix.lock")) do
          {:ok, _content} = result -> result
          {:error, reason} -> {:error, "Failed to read mix.lock: #{inspect(reason)}"}
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
end
