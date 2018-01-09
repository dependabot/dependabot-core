[dependency_name] = System.argv()

# dependency atom
dependency = String.to_atom(dependency_name)

# Fetch dependencies that needs updating
{dependency_lock, rest_lock} = Map.split(Mix.Dep.Lock.read, [dependency])
Mix.Dep.Fetcher.by_name([dependency_name], dependency_lock, rest_lock, [])

# Check the dependency version in the new lock
{updated_lock, _updated_rest_lock} = Map.split(Mix.Dep.Lock.read, [dependency])

version =
  updated_lock
  |> Map.get(dependency)
  |> elem(2)

version = :erlang.term_to_binary({:ok, version})

IO.write(:stdio, version)
