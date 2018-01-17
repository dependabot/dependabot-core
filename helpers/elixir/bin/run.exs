defmodule DependencyUtils do
  def parse_deps(path) do
    {output, 0} = System.cmd(
      "mix",
      ["run", "--no-deps-check", "--no-start", "--no-compile", "--no-elixir-version-check", "parse_deps.exs"],
      [
        cd: path,
        env: %{
          "MIX_EXS" => nil,
          "MIX_LOCK" => nil,
          "MIX_DEPS" => nil
        }
      ]
    )
    :erlang.binary_to_term(output)
  end

  def get_latest_resolvable_version(path, dependency_name) do
    {output, 0} = System.cmd(
      "mix",
      ["run", "--no-deps-check", "--no-start", "--no-compile", "--no-elixir-version-check", "check_update.exs", dependency_name],
      [
        cd: path,
        env: %{
          "MIX_EXS" => nil,
          "MIX_LOCK" => nil,
          "MIX_DEPS" => nil
        }
      ]
    )
    :erlang.binary_to_term(output)
  end

  def get_updated_lockfile(path, dependency_name) do
    {output, 0} = System.cmd(
      "mix",
      ["run", "--no-deps-check", "--no-start", "--no-compile", "--no-elixir-version-check", "do_update.exs", dependency_name],
      [
        cd: path,
        env: %{
          "MIX_EXS" => nil,
          "MIX_LOCK" => nil,
          "MIX_DEPS" => nil
        }
      ]
    )
    :erlang.binary_to_term(output)
  end
end

input = IO.read(:stdio, :all)
%{"function" => function, "args" => args} = Jason.decode!(input)

case function do
  "parse" ->
    [dir] = args

    dependencies = DependencyUtils.parse_deps(dir)

    Jason.encode!(%{"result" => dependencies})
    |> IO.write()
  "get_latest_resolvable_version" ->
    [dir, dependency_name] = args

    {:ok, version} = DependencyUtils.get_latest_resolvable_version(dir, dependency_name)

    Jason.encode!(%{"result" => version})
    |> IO.write()
  "get_updated_lockfile" ->
    [dir, dependency_name] = args

    {:ok, lockfile_content} = DependencyUtils.get_updated_lockfile(dir, dependency_name)

    Jason.encode!(%{"result" => lockfile_content})
    |> IO.write()
end

