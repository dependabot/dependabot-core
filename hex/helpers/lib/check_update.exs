Code.require_file("lockfile.exs", __DIR__)

Mix.ensure_application!(:hex)

[dependency_name] = Enum.drop_while(System.argv(), &(&1 == "--"))

Mix.Task.get!("deps.update").run([dependency_name, "--no-archives-check"])

version =
  Dependabot.Hex.Lockfile.read!()
  |> Map.fetch!(dependency_name)
  |> Dependabot.Hex.Lockfile.resolved_version!()

File.write!(".dependabot-result", version)
