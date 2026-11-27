defmodule DependencyHelper do
  def main() do
    IO.read(:stdio, :eof)
    |> JSON.decode!()
    |> run()
    |> case do
      {output, 0} ->
        output = try_decode(output)
        {:ok, :erlang.binary_to_term(output)}

      {error, 1} ->
        {:error, try_decode(error)}
    end
    |> handle_result()
  end

  defp try_decode(result) do
    case Base.decode64(result) do
      {:ok, result} ->
        result

      :error ->
        result
    end
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
    |> JSON.encode!()
    |> IO.write()
  end

  defp run(%{"function" => "parse", "args" => [dir]}) do
    run_script("parse_deps.exs", dir)
  end

  defp run_script(script, dir) do
    args = [
      "run",
      "--no-deps-check",
      "--no-start",
      "--no-compile",
      "--no-elixir-version-check",
      script
    ]

    System.cmd("mix", args, cd: dir, env: %{"MIX_EXS" => nil})
  end
end

DependencyHelper.main()
