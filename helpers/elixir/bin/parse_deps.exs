defmodule Parser do
  def run do
    Mix.Dep.loaded([])
    |> Enum.flat_map(&parse_dep/1)
    |> Enum.map(&build_dependency(&1.opts[:lock], &1))
  end

  defp build_dependency(nil, dep) do
    %{
      name: dep.app,
      from: Path.relative_to_cwd(dep.from),
      requirement: dep.requirement,
      top_level: dep.top_level || umbrella_top_level_dep?(dep)
    }
  end

  defp build_dependency(lock, dep) do
    {version, checksum, source} = parse_lock(lock)

    %{
      name: dep.app,
      from: Path.relative_to_cwd(dep.from),
      version: version,
      checksum: checksum,
      requirement: dep.requirement,
      source: source,
      top_level: dep.top_level || umbrella_top_level_dep?(dep)
    }
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

  defp umbrella_top_level_dep?(dep) do
    if Mix.Project.umbrella?() do
      apps_paths = Path.expand(Mix.Project.config()[:apps_path], File.cwd!())
      String.contains?(Path.dirname(Path.dirname(dep.from)), apps_paths)
    else
      false
    end
  end

  defp parse_lock({:git, repo_url, checksum, opts}),
    do: {nil, checksum, git_source(repo_url, opts)}

  defp parse_lock({:hex, _app, version, checksum, _managers, _dependencies, _source}),
    do: {version, checksum, nil}

  defp parse_lock({:hex, _app, version, checksum, _managers, _dependencies}),
    do: {version, checksum, nil}

  def git_source(repo_url, opts) do
    %{
      type: "git",
      url: repo_url,
      branch: opts[:branch] || "master",
      ref: opts[:ref] || opts[:tag]
    }
  end
end

dependencies = :erlang.term_to_binary({:ok, Parser.run()})

IO.write(:stdio, dependencies)
