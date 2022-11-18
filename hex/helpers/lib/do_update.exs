dependency =
  System.argv()
  |> List.first()
  |> String.to_atom()

# Fetch dependencies that needs updating
{dependency_lock, rest_lock} = Map.split(Mix.Dep.Lock.read(), [dependency])
Mix.Dep.Fetcher.by_name([dependency], dependency_lock, rest_lock, [])

System.cmd(
  "mix",
  [
    "deps.get",
    "--no-compile",
    "--no-elixir-version-check",
  ],
  [
    env: %{
      "MIX_EXS" => nil,
      "MIX_LOCK" => nil,
      "MIX_DEPS" => nil
    }
  ]
)

lockfile_content =
  "mix.lock"
  |> File.read()
  |> :erlang.term_to_binary()

IO.write(:stdio, lockfile_content)
