# Log to stderr instead of stdout
:logger.remove_handler(:default)
:logger.add_handler(:to_stderr, :logger_std_h, %{config: %{type: :standard_error}})

defmodule Parser do
  @allowed_scms [Hex.SCM, Mix.SCM.Git, Mix.SCM.Path]

  def run do
    # This is necessary because we can't specify :extra_applications to have :hex in other mixfiles.
    Mix.ensure_application!(:hex)

    with {:ok, deps} <- converge_deps() do
      result =
        for %Mix.Dep{scm: scm} = dep <- deps, scm in @allowed_scms,
            expanded_dep <- expand_deps(dep) do
          build_dependency(expanded_dep.opts[:lock], expanded_dep)
        end

      {:ok, result ++ transitive_dependencies(result)}
    end
  end

  # Dependencies that are only present in the lockfile, found by walking the
  # lockfile from the declared dependencies. Entries that are no longer
  # reachable (e.g. left behind after removing a dependency) are skipped.
  defp transitive_dependencies(declared) do
    lock = Mix.Dep.Lock.read()
    declared_apps = MapSet.new(declared, & &1.name)

    declared_apps
    |> MapSet.to_list()
    |> reachable_apps(lock, declared_apps)
    |> MapSet.difference(declared_apps)
    |> Enum.sort()
    |> Enum.flat_map(&build_transitive_dependency(&1, lock[&1]))
  end

  defp reachable_apps([], _lock, seen), do: seen

  defp reachable_apps([app | rest], lock, seen) do
    children =
      for {child, _requirement, _opts} <- locked_children(lock[app]),
          not MapSet.member?(seen, child),
          do: child

    reachable_apps(children ++ rest, lock, MapSet.union(seen, MapSet.new(children)))
  end

  defp locked_children(lock) when elem(lock, 0) == :hex and tuple_size(lock) >= 6,
    do: elem(lock, 5)

  defp locked_children(_lock), do: []

  defp build_transitive_dependency(app, lock) when elem(lock, 0) == :hex do
    {version, checksum, source} = parse_lock(lock)

    [
      %{
        name: app,
        package_name: elem(lock, 1),
        version: version,
        groups: [],
        checksum: checksum,
        requirement: nil,
        source: source,
        top_level: false
      }
    ]
  end

  defp build_transitive_dependency(_app, _lock), do: []

  defp converge_deps do
    {:ok, Mix.Dep.Converger.converge()}
  rescue e ->
    {:error, Exception.format_banner(:error, e, __STACKTRACE__)}
  end

  defp build_dependency(nil, dep) do
    %{
      name: dep.app,
      package_name: dep.opts[:hex] || dep.app,
      from: Path.relative_to_cwd(dep.from),
      groups: [],
      requirement: normalise_requirement(dep.requirement),
      top_level: dep.top_level || umbrella_top_level_dep?(dep)
    }
  end

  defp build_dependency(lock, dep) do
    {version, checksum, source} = parse_lock(lock)
    groups = parse_groups(dep.opts[:only])

    %{
      name: dep.app,
      package_name: dep.opts[:hex] || dep.app,
      from: Path.relative_to_cwd(dep.from),
      version: version,
      groups: groups,
      checksum: checksum,
      requirement: normalise_requirement(dep.requirement),
      source: source,
      top_level: dep.top_level || umbrella_top_level_dep?(dep)
    }
  end

  defp parse_groups(nil), do: []
  defp parse_groups(only) when is_list(only), do: only
  defp parse_groups(only), do: [only]

  # path dependency
  defp expand_deps(%{scm: Mix.SCM.Path, opts: opts} = dep) do
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
  defp expand_deps(%{scm: scm} = dep) when scm in [Hex.SCM, Mix.SCM.Git], do: [dep]

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

  defp parse_lock(tuple) when elem(tuple, 0) == :hex do
    destructure [:hex, _app, version, _old_checksum, _managers, _deps, _repo, checksum],
                Tuple.to_list(tuple)

    {version, checksum, nil}
  end

  defp normalise_requirement(req) do
    req
    |> maybe_regex_to_str()
    |> empty_str_to_nil()
  end

  defp maybe_regex_to_str(%Regex{} = s), do: Regex.source(s)
  defp maybe_regex_to_str(s), do: s

  defp empty_str_to_nil(""), do: nil
  defp empty_str_to_nil(s), do: s

  def git_source(repo_url, opts) do
    ref = opts[:ref] || opts[:tag]
    ref = if is_list(ref), do: to_string(ref), else: ref

    %{
      type: "git",
      url: repo_url,
      branch: opts[:branch],
      ref: ref
    }
  end
end

Parser.run()
|> :erlang.term_to_binary()
|> Base.encode64()
|> IO.write()
