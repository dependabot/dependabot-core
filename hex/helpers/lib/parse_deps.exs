defmodule Parser do
  @allowed_scms [Hex.SCM, Mix.SCM.Git, Mix.SCM.Path]

  def run do
    # This is necessary because we can't specify :extra_applications to have :hex in other mixfiles.
    Mix.ensure_application!(:hex)

    with {:ok, deps} <- converge_deps() do
      result =
        for %Mix.Dep{scm: scm} = dep <- deps,
            scm in @allowed_scms,
            expanded_dep <- expand_deps(dep) do
          build_dependency(expanded_dep.opts[:lock], expanded_dep)
        end

      {:ok, result}
    end
  end

  defp converge_deps do
    {:ok, Mix.Dep.Converger.converge()}
  rescue
    e ->
      {:error, Exception.format_banner(:error, e, __STACKTRACE__)}
  end

  defp build_dependency(nil, dep) do
    %{
      name: dep.app,
      package_name: dep.opts[:hex] || dep.app,
      from: Path.relative_to_cwd(dep.from),
      groups: [],
      requirement: normalise_requirement(dep.requirement)
    }
  end

  defp build_dependency(lock, dep) do
    {version, source} = parse_lock(lock)
    groups = parse_groups(dep.opts[:only])

    %{
      name: dep.app,
      package_name: dep.opts[:hex] || dep.app,
      from: Path.relative_to_cwd(dep.from),
      version: version,
      groups: groups,
      requirement: normalise_requirement(dep.requirement),
      source: source
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

  defp parse_lock({:git, repo_url, checksum, opts}),
    do: {checksum, git_source(repo_url, opts)}

  defp parse_lock(tuple) when elem(tuple, 0) == :hex do
    destructure [:hex, _app, version, _old_checksum, _managers, _deps, _repo, checksum],
                Tuple.to_list(tuple)

    {version, nil}
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

case Parser.run() do
  {:ok, dependencies} ->
    dependencies
    |> JSON.encode!()
    |> then(&File.write!(".dependabot-result.json", &1))

  {:error, error} ->
    Mix.raise(error)
end
