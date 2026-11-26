Mix.ensure_application!(:hex)

[dependency_name] = Enum.drop_while(System.argv(), &(&1 == "--"))
dependency_name = String.to_atom(dependency_name)

defmodule GitDependencyFetcher do
  def run(dependency_name) do
    lock = Mix.Dep.Lock.read()

    Mix.Project.with_deps_lock(fn ->
      dependencies = Mix.Dep.Converger.converge()
      fetched = fetch_target_candidate(dependencies, dependency_name)
      fetch_reachable_dependencies(dependency_name, lock, fetched)
    end)
  end

  defp fetch_target_candidate(dependencies, dependency_name) do
    case Enum.find(dependencies, &(&1.app == dependency_name and &1.scm == Mix.SCM.Git)) do
      nil ->
        MapSet.new()

      dependency ->
        fetch_candidate_dependency(dependency)
        MapSet.new([dependency.app])
    end
  end

  defp fetch_reachable_dependencies(dependency_name, lock, fetched) do
    dependencies =
      Mix.Dep.Converger.converge()
      |> Enum.filter(fn dependency ->
        dependency.app != dependency_name and
          dependency.scm == Mix.SCM.Git and
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

  defp fetch_candidate_dependency(dependency) do
    opts = Keyword.delete(dependency.opts, :lock)
    fetch_dependency(dependency, opts)
  end

  defp fetch_locked_dependency(dependency, lock) do
    opts = Keyword.put(dependency.opts, :lock, lock)
    fetch_dependency(dependency, opts)
  end

  defp fetch_dependency(dependency, opts) do
    if dependency.scm.checked_out?(opts) do
      dependency.scm.update(opts)
    else
      dependency.scm.checkout(opts)
    end
  end
end

GitDependencyFetcher.run(dependency_name)
