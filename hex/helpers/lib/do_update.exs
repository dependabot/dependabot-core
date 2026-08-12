Mix.ensure_application!(:hex)

dependency =
  System.argv()
  |> Enum.drop_while(&(&1 == "--"))
  |> List.first()

Mix.Task.get!("deps.update").run([dependency, "--no-archives-check"])
