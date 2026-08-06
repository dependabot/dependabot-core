Mix.ensure_application!(:hex)

[dependency_name] = Enum.drop_while(System.argv(), &(&1 == "--"))
dependency_name = String.to_atom(dependency_name)

defmodule GitDependencyFetcher do
  def run(dependency_name) do
    lock = Mix.Dep.Lock.read()

    Mix.Project.with_deps_lock(fn ->
      fetch_reachable_dependencies(dependency_name, lock, MapSet.new())
    end)
  end

  defp fetch_reachable_dependencies(dependency_name, lock, fetched) do
    dependencies =
      Mix.Dep.Converger.converge()
      |> Enum.filter(fn dependency ->
        dependency.app != dependency_name and
          match?({:git, _, _, _}, lock[dependency.app]) and
          not MapSet.member?(fetched, dependency.app)
      end)

    case dependencies do
      [] ->
        :ok

      dependencies ->
        fetched =
          Enum.reduce(dependencies, fetched, fn dependency, fetched ->
            fetch_locked_dependency(dependency, lock[dependency.app])
            MapSet.put(fetched, dependency.app)
          end)

        fetch_reachable_dependencies(dependency_name, lock, fetched)
    end
  end

  defp fetch_locked_dependency(dependency, {:git, _, locked_revision, _} = lock) do
    opts = Keyword.put(dependency.opts, :lock, lock)

    fetched_lock =
      if dependency.scm.checked_out?(opts) do
        dependency.scm.update(opts)
      else
        dependency.scm.checkout(opts)
      end

    case fetched_lock do
      {:git, _, ^locked_revision, _} -> :ok
      _ -> Mix.raise("Git dependency #{dependency.app} did not resolve to its locked revision")
    end
  end
end

GitDependencyFetcher.run(dependency_name)
