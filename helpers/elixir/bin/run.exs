defmodule DependencyHelper do
  def main() do
    IO.read(:stdio, :all)
    |> Jason.decode!()
    |> run()
    |> case do
      {output, 0} -> {:ok, :erlang.binary_to_term(output)}
      {error, 1} -> {:error, error}
    end
    |> handle_result()
  end

  defp handle_result({:ok, {:ok, result}}) do
    encode_and_write(%{"result" => result})
  end

  defp handle_result({:ok, {:error, reason}}) do
    encode_and_write(%{"error" => reason})
    System.halt(1)
  end

  defp handle_result({:error, reason}) do
    encode_and_write(%{"error" => reason})
    System.halt(1)
  end

  defp encode_and_write(content) do
    content
    |> Jason.encode!()
    |> IO.write()
  end

  defp run(%{"function" => "parse", "args" => [dir]}) do
    run_script("parse_deps.exs", dir)
  end

  defp run(%{"function" => "get_latest_resolvable_version", "args" => [dir, dependency_name]}) do
    run_script("check_update.exs", dir, [dependency_name])
  end

  defp run(%{"function" => "get_updated_lockfile", "args" => [dir, dependency_name]}) do
    run_script("do_update.exs", dir, [dependency_name])
  end

  defp run_script(script, dir, args \\ []) do
    args = [
      "run",
      "--no-deps-check",
      "--no-start",
      "--no-compile",
      "--no-elixir-version-check",
      script
    ] ++ args

    System.cmd(
      "mix",
      args,
      [
        cd: dir,
        env: %{
          "MIX_EXS" => nil,
          "MIX_LOCK" => nil,
          "MIX_DEPS" => nil
        }
      ]
    )
  end
end

DependencyHelper.main()
