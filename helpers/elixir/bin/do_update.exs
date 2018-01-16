[dependency_name] = System.argv()

# dependency atom
dependency = String.to_atom(dependency_name)

# Fetch dependencies that needs updating
{dependency_lock, rest_lock} = Map.split(Mix.Dep.Lock.read, [dependency])
Mix.Dep.Fetcher.by_name([dependency_name], dependency_lock, rest_lock, [])

lockfile_content = :file.read_file("mix.lock")
lockfile_content = :erlang.term_to_binary(lockfile_content)

IO.write(:stdio, lockfile_content)
