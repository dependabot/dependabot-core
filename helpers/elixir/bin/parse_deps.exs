deps = Mix.Dep.loaded([]) |> Enum.filter(&(&1.scm == Hex.SCM))

umbrella? = Mix.Project.umbrella?()

apps_paths =
  if umbrella? do
    Path.expand(Mix.Project.config()[:apps_path], File.cwd!())
  else
    nil
  end

dependencies =
  deps
  |> Enum.map(fn dep ->
    lock = dep.opts[:lock]

    from =
      if dep.top_level ||
           (umbrella? && String.contains?(Path.dirname(Path.dirname(dep.from)), apps_paths)) do
        Path.relative_to_cwd(dep.from)
      else
        nil
      end

    %{
      name: elem(lock, 1),
      from: from,
      version: elem(lock, 2),
      checksum: elem(lock, 3),
      requirement: dep.requirement
    }
  end)

dependencies = :erlang.term_to_binary({:ok, dependencies})

IO.write(:stdio, dependencies)
