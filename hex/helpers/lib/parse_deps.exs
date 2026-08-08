Code.require_file("lockfile.exs", __DIR__)

# Log to stderr instead of stdout
:logger.remove_handler(:default)
:logger.add_handler(:to_stderr, :logger_std_h, %{config: %{type: :standard_error}})

defmodule Parser do
  def run do
    # This is necessary because we can't specify :extra_applications to have :hex in other mixfiles.
    Mix.ensure_application!(:hex)

    root = File.cwd!()
    lock = read_lockfile()

    dependencies =
      project_dependencies(lock, root) ++ umbrella_dependencies(lock, root)

    {:ok, dependencies}
  rescue
    error ->
      {:error, Exception.format_banner(:error, error, __STACKTRACE__)}
  end

  defp read_lockfile do
    path = Keyword.get(Mix.Project.config(), :lockfile, "mix.lock")

    if File.exists?(path), do: Dependabot.Hex.Lockfile.read!(path), else: %{}
  end

  defp umbrella_dependencies(lock, root) do
    Mix.Project.apps_paths()
    |> Kernel.||(%{})
    |> Enum.flat_map(fn {app, path} ->
      Mix.Project.in_project(app, path, fn _project ->
        project_dependencies(lock, root)
      end)
    end)
  end

  defp project_dependencies(lock, root) do
    from =
      Mix.Project.project_file()
      |> Path.expand()
      |> Path.relative_to(root)

    Mix.Project.config()
    |> Keyword.get(:deps, [])
    |> Enum.flat_map(&build_dependency(&1, lock, from))
  end

  defp build_dependency(declaration, lock, from) do
    {name, requirement, opts} = parse_declaration(declaration)

    if local_dependency?(opts) do
      []
    else
      source = git_source(opts)
      locked_version = locked_version(lock, name)

      [
        %{
          name: name,
          package_name: opts[:hex] || name,
          from: from,
          version: if(source, do: nil, else: locked_version),
          groups: parse_groups(opts[:only]),
          checksum: if(source, do: locked_version),
          requirement: normalise_requirement(requirement),
          source: source,
          top_level: true
        }
      ]
    end
  end

  defp parse_declaration({name, opts}) when is_atom(name) and is_list(opts),
    do: {name, nil, opts}

  defp parse_declaration({name, requirement}) when is_atom(name),
    do: {name, requirement, []}

  defp parse_declaration({name, requirement, opts}) when is_atom(name) and is_list(opts),
    do: {name, requirement, opts}

  defp local_dependency?(opts), do: opts[:path] || opts[:in_umbrella]

  defp locked_version(lock, name) do
    case Map.fetch(lock, Atom.to_string(name)) do
      {:ok, entry} -> Dependabot.Hex.Lockfile.resolved_version!(entry)
      :error -> nil
    end
  end

  defp parse_groups(nil), do: []
  defp parse_groups(only) when is_list(only), do: only
  defp parse_groups(only), do: [only]

  defp normalise_requirement(requirement) do
    requirement
    |> maybe_regex_to_str()
    |> empty_str_to_nil()
  end

  defp maybe_regex_to_str(%Regex{} = requirement), do: Regex.source(requirement)
  defp maybe_regex_to_str(requirement), do: requirement

  defp empty_str_to_nil(""), do: nil
  defp empty_str_to_nil(requirement), do: requirement

  defp git_source(opts) do
    url = opts[:git] || github_url(opts[:github])

    if url do
      ref = opts[:ref] || opts[:tag]

      %{
        type: "git",
        url: url,
        branch: opts[:branch],
        ref: if(is_list(ref), do: to_string(ref), else: ref)
      }
    end
  end

  defp github_url(nil), do: nil
  defp github_url(repository), do: "https://github.com/#{repository}.git"
end

case Parser.run() do
  {:ok, dependencies} ->
    dependencies
    |> JSON.encode!()
    |> then(&File.write!(".dependabot-result.json", &1))

  {:error, error} ->
    Mix.raise(error)
end
