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

      {:ok, result}
    end
  end

  defp converge_deps do
    {:ok, Mix.Dep.Converger.converge()}
  rescue e ->
    {:error, Exception.format_banner(:error, e, __STACKTRACE__)}
  end

  defp build_dependency(nil, dep) do
    %{
      name: dep.app,
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
      branch: opts[:branch] || "master",
      ref: ref
    }
  end
end

Parser.run()
|> :erlang.term_to_binary()
|> Base.encode64()
|> IO.write()
