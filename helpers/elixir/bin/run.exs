defmodule DependencyLoader do
  def load(path) do
    {output, 0} = System.cmd(
      "mix",
      ["run", "--no-deps-check", "--no-start", "--no-compile", "load_deps.exs"],
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

defmodule DependencyParser do
  def parse_lock_name({_, name, _, _, _, _, _}), do: name
  def parse_lock_version({_, _, version, _, _, _, _}), do: version
  def parse_lock_checksum({_, _, _, checksum, _, _, _}), do: checksum
  def parse_lock_repo({_, _, _, _, _, _, repo}), do: repo

  def parse_requirement(%{requirement: requirement}), do: requirement
end

# %Mix.Dep{
#   app: _app,      # the application name as an atom
#   deps: _deps,    # dependencies of this dependency
#   extra: _extra,  # a slot for adding extra configuration based on the manager; the information on this field is private to the manager and should not be relied on
#   from: _from,      # path to the file where the dependency was defined
#   manager: _manager, # the project management, possible values: `:rebar` | `:rebar3` | `:mix` | `:make` | `nil`
#   opts: [
#     lock: {
#       _,  # :hex
#       name,
#       version,
#       checksum,
#       _managers,
#       _deps2,
#       repo
#     },
#     env: _env,
#     repo: _repo2,
#     hex: _hex,
#     build: _build,
#     dest: _dest,
#     #only: _only,
#   ],
#   requirement: requirement, # a binary or regex with the dependency's requirement
#   scm: _scm, # a module representing the source code management tool (SCM) operations
#   status: _status, # the current status of the dependency
#   top_level: _top_level # true if dependency was defined in the top-level project
# } = dep

input = IO.read(:stdio, :all)
%{"function" => function, "args" => [dir]} = Jason.decode!(input)

case function do
  "parse" ->
    %{deps: deps, lock: _lock} = DependencyLoader.load(dir)

    dependencies =
      deps
      |> Enum.filter(fn dep -> dep.top_level end)
      |> Enum.map(fn dep ->
        lock = dep.opts[:lock]

        %{
          name: DependencyParser.parse_lock_name(lock),
          version: DependencyParser.parse_lock_version(lock),
          checksum: DependencyParser.parse_lock_checksum(lock),
          repo: DependencyParser.parse_lock_repo(lock),
          requirement: DependencyParser.parse_requirement(dep)
        }
      end)

    Jason.encode!(%{"result" => dependencies})
    |> IO.write()
end

