Mix.ensure_application!(:hex)

[dependency_name] = Enum.drop_while(System.argv(), &(&1 == "--"))

Mix.Task.get!("deps.update").run([dependency_name, "--no-archives-check"])

version =
  Mix.Dep.Lock.read()
  |> Map.fetch!(String.to_atom(dependency_name))
  |> elem(2)

File.write!(".dependabot-result", version)
