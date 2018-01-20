deps = Mix.Dep.loaded([]) |> Enum.filter(&(&1.scm == Hex.SCM))

dependencies =
  deps
  |> Enum.filter(fn dep -> dep.top_level end)
  |> Enum.map(fn dep ->
    lock = dep.opts[:lock]

    %{
      name: elem(lock, 1),
      version: elem(lock, 2),
      checksum: elem(lock, 3),
      requirement: dep.requirement
    }
  end)

dependencies = :erlang.term_to_binary({:ok, dependencies})

IO.write(:stdio, dependencies)
