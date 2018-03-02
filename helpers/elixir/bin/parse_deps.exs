defmodule Parser do
  def run do
    Mix.Dep.loaded([])
    |> Enum.flat_map(&parse_dep/1)
    |> Enum.group_by(&group_deps/1)
    |> Enum.map(fn {app, deps} ->
      dep = find_dep_with_lock(deps)
      lock = dep.opts[:lock]

      from = parse_from(deps)
      {version, checksum, source} = parse_lock(lock)

      %{
        name: app,
        from: from,
        version: version,
        checksum: checksum,
        requirement: dep.requirement,
        source: source,
        top_level: dep.top_level || umbrella_top_level_dep?(dep)
      }
    end)
  end

  # path dependency
  defp parse_dep(%{scm: Mix.SCM.Path, opts: opts} = dep) do
    cond do
      # umbrella dependency - ignore
      opts[:in_umbrella] ->
        []

      # umbrella application
      opts[:from_umbrella] ->
        Enum.reject(dep.deps, fn dep -> dep.opts[:in_umbrella] end)

      true ->
        []
    end
  end

  # hex, git dependency
  defp parse_dep(%{scm: scm} = dep) when scm in [Hex.SCM, Mix.SCM.Git], do: [dep]

  # unsupported
  defp parse_dep(_dep), do: []

  defp group_deps(dep), do: dep.app

  defp find_dep_with_lock([]), do: nil

  defp find_dep_with_lock([head | rest]) do
    if head.opts[:lock] do
      head
    else
      find_dep_with_lock(rest)
    end
  end

  defp umbrella_top_level_dep?(dep) do
    if Mix.Project.umbrella?() do
      apps_paths = Path.expand(Mix.Project.config()[:apps_path], File.cwd!())
      String.contains?(Path.dirname(Path.dirname(dep.from)), apps_paths)
    else
      false
    end
  end

  defp parse_from(deps) do
    deps
    |> Enum.map(&Path.relative_to_cwd(&1.from))
    |> Enum.uniq()
  end

  defp parse_lock({:git, repo_url, checksum, opts}),
    do: {nil, checksum, git_source(repo_url, opts)}

  defp parse_lock({:hex, _app, version, checksum, _managers, _dependencies, _source}),
    do: {version, checksum, nil}

  def git_source(repo_url, opts) do
    %{
      url: repo_url,
      branch: opts[:branch],
      tag: opts[:tag],
      ref: opts[:ref]
    }
  end
end

dependencies = :erlang.term_to_binary({:ok, Parser.run()})

IO.write(:stdio, dependencies)
