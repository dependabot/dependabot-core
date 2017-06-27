lock = Mix.Dep.Lock.read()
deps = Mix.Dep.loaded([]) |> Enum.filter(& &1.scm == Hex.SCM)

deps_and_lock = :erlang.term_to_binary(%{deps: deps, lock: lock})

IO.write(:stdio, deps_and_lock)
