defmodule Dependabot.Hex.Lockfile do
  def read! do
    Mix.Project.config()
    |> Keyword.get(:lockfile, "mix.lock")
    |> read!()
  end

  def read!(path) do
    quoted =
      path
      |> File.read!()
      |> parse!(path)

    unless Macro.quoted_literal?(quoted) do
      raise ArgumentError, "#{path} must contain only literal data"
    end

    {lock, _binding} = Code.eval_quoted(quoted, [], file: path)

    unless is_map(lock) do
      raise ArgumentError, "#{path} must contain a map"
    end

    Map.new(lock, fn
      {name, entry} when is_atom(name) -> {Atom.to_string(name), entry}
      {name, entry} when is_binary(name) -> {name, entry}
    end)
  end

  def resolved_version!(lock)
      when is_tuple(lock) and tuple_size(lock) >= 3 and elem(lock, 0) in [:hex, :git] and
             is_binary(elem(lock, 2)) do
    elem(lock, 2)
  end

  def resolved_version!(lock) do
    raise ArgumentError, "unsupported mix.lock entry: #{inspect(lock)}"
  end

  defp parse!(contents, path) do
    case Code.string_to_quoted(contents, file: path, emit_warnings: false) do
      {:ok, quoted} -> quoted
      {:error, error} -> raise ArgumentError, "could not parse #{path}: #{inspect(error)}"
    end
  end
end
