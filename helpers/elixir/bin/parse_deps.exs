defmodule Parser do
  def run do
    Mix.Dep.loaded([])
    |> Enum.flat_map(&parse_dep/1)
    |> Enum.map(&build_dependency(&1.opts[:lock], &1))
  end

  defp build_dependency(nil, dep) do
    req = if Regex.regex?(dep.requirement), do: Regex.source(dep.requirement), else: dep.requirement
    req = if byte_size(req) == 0, do: nil, else: req

    %{
      name: dep.app,
      from: Path.relative_to_cwd(dep.from),
      groups: [],
      requirement: req,
      top_level: dep.top_level || umbrella_top_level_dep?(dep)
    }
  end

  defp build_dependency(lock, dep) do
    {version, checksum, source} = parse_lock(lock)
    groups = parse_groups(dep.opts[:only])
    req = if Regex.regex?(dep.requirement), do: Regex.source(dep.requirement), else: dep.requirement
    req = if byte_size(req) == 0, do: nil, else: req

    %{
      name: dep.app,
      from: Path.relative_to_cwd(dep.from),
      version: version,
      groups: groups,
      checksum: checksum,
      requirement: req,
      source: source,
      top_level: dep.top_level || umbrella_top_level_dep?(dep)
    }
  end

  defp parse_groups(nil), do: []
  defp parse_groups(only) when is_list(only), do: only
  defp parse_groups(only), do: [only]

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
    ref = opts[:ref] || opts[:tag]
    ref = if is_list(ref), do: to_string(ref), else: ref

    %{
      type: "git",
      url: repo_url,
      branch: opts[:branch] || "master",
      ref: ref
    }
  end
end

dependencies = :erlang.term_to_binary({:ok, Parser.run()})

IO.write(:stdio, dependencies)
