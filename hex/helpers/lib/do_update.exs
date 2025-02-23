# This is necessary because we can't specify :extra_applications to have :hex in other mixfiles.
Mix.ensure_application!(:hex)

dependency =
  System.argv()
  |> List.first()
  |> String.to_atom()

# Fetch dependencies that needs updating
{dependency_lock, rest_lock} = Map.split(Mix.Dep.Lock.read(), [dependency])
Mix.Dep.Fetcher.by_name([dependency], dependency_lock, rest_lock, [])

args = [
  "deps.get",
  "--no-compile",
  "--no-elixir-version-check",
]

result =
  case System.cmd("mix", args, env: %{"MIX_EXS" => nil}, stderr_to_stdout: true) do
    {_results, 0} ->
      File.read("mix.lock")

    {results, _code} ->
      {:error, results}
  end

result
|> :erlang.term_to_binary()
|> Base.encode64()
|> IO.write()
