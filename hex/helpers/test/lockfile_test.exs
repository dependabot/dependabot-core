Code.require_file("../lib/lockfile.exs", __DIR__)

defmodule Dependabot.Hex.LockfileTest do
  use ExUnit.Case, async: true

  alias Dependabot.Hex.Lockfile

  setup do
    directory =
      Path.join(System.tmp_dir!(), "dependabot-lockfile-#{System.unique_integer([:positive])}")

    File.mkdir_p!(directory)
    on_exit(fn -> File.rm_rf!(directory) end)

    %{directory: directory}
  end

  test "reads a literal lock map", %{directory: directory} do
    path = Path.join(directory, "mix.lock")

    File.write!(path, ~S(%{"plug": {:hex, :plug, "1.3.6", "checksum", [:mix], [], "hexpm"}}))

    assert %{"plug" => {:hex, :plug, "1.3.6", "checksum", [:mix], [], "hexpm"}} =
             Lockfile.read!(path)
  end

  test "reads the project's configured lockfile", %{directory: directory} do
    File.write!(Path.join(directory, "mix.exs"), """
    defmodule LockfileFixture.MixProject do
      use Mix.Project

      def project do
        [app: :lockfile_fixture, version: "0.1.0", lockfile: "custom.lock"]
      end
    end
    """)

    File.write!(
      Path.join(directory, "custom.lock"),
      ~S(%{"plug": {:hex, :plug, "1.3.6", "checksum", [:mix], [], "hexpm"}})
    )

    lock =
      Mix.Project.in_project(:lockfile_fixture, directory, fn _project ->
        Lockfile.read!()
      end)

    assert Map.has_key?(lock, "plug")
  end

  test "extracts versions from current and legacy Hex locks" do
    current = {:hex, :plug, "1.15.3", "old", [:mix], [], "hexpm", "outer"}
    legacy = {:hex, :plug, "1.3.6", "checksum", [:mix], []}

    assert Lockfile.resolved_version!(current) == "1.15.3"
    assert Lockfile.resolved_version!(legacy) == "1.3.6"
  end

  test "extracts revisions from Git locks" do
    lock =
      {:git, "https://github.com/elixir-plug/plug.git", String.duplicate("a", 40), [tag: "v1.0"]}

    assert Lockfile.resolved_version!(lock) == String.duplicate("a", 40)
  end

  test "rejects executable lockfile expressions without evaluating them", %{directory: directory} do
    path = Path.join(directory, "mix.lock")
    marker = Path.join(directory, "executed")

    File.write!(path, """
    %{"plug" => (File.write!(#{inspect(marker)}, "yes"); {:hex, :plug, "1.0.0"})}
    """)

    assert_raise ArgumentError, ~r/only literal data/, fn -> Lockfile.read!(path) end
    refute File.exists?(marker)
  end

  test "rejects literal data that is not a map", %{directory: directory} do
    path = Path.join(directory, "mix.lock")
    File.write!(path, "[]")

    assert_raise ArgumentError, ~r/must contain a map/, fn -> Lockfile.read!(path) end
  end
end
