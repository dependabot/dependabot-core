# Log to stderr instead of stdout
:logger.remove_handler(:default)
:logger.add_handler(:to_stderr, :logger_std_h, %{config: %{type: :standard_error}})

# This is necessary because we can't specify :extra_applications to have :hex in other mixfiles.
Mix.ensure_application!(:hex)

defmodule DependabotDependencyFetcher do
  @max_attempts 3

  @doc """
  Hex caches downloaded package tarballs and removes the cached copy itself
  if it fails to unpack, but a transient network issue (for example, a
  connection that's cut short) can still cause a single fetch attempt to
  fail with "Unpacking tarball failed: tarball error, Unexpected end of
  file". Since the corrupted cache entry is discarded before the error is
  raised, retrying is usually enough for the package to be re-downloaded and
  unpacked successfully.
  """
  def retryable_error?(message) when is_binary(message) do
    String.contains?(message, "Unpacking tarball failed") or
      String.contains?(message, "Unexpected end of file") or
      String.contains?(message, "tarball error")
  end

  def retryable_error?(_message), do: false

  def with_retries(fun, attempt \\ 1) do
    case run(fun) do
      {:error, message} = error ->
        if attempt < @max_attempts and retryable_error?(message) do
          with_retries(fun, attempt + 1)
        else
          error
        end

      result ->
        result
    end
  end

  defp run(fun) do
    fun.()
  rescue
    error -> {:error, Exception.message(error)}
  end
end

dependency =
  System.argv()
  |> List.first()
  |> String.to_atom()

fetch_result =
  DependabotDependencyFetcher.with_retries(fn ->
    # Fetch dependencies that needs updating
    {dependency_lock, rest_lock} = Map.split(Mix.Dep.Lock.read(), [dependency])
    Mix.Dep.Fetcher.by_name([dependency], dependency_lock, rest_lock, [])
    :ok
  end)

args = [
  "deps.get",
  "--no-compile",
  "--no-elixir-version-check",
]

result =
  case fetch_result do
    {:error, _message} = error ->
      error

    _ok ->
      DependabotDependencyFetcher.with_retries(fn ->
        case System.cmd("mix", args, env: %{"MIX_EXS" => nil}, stderr_to_stdout: true) do
          {_results, 0} ->
            File.read("mix.lock")

          {results, _code} ->
            {:error, results}
        end
      end)
  end

result
|> :erlang.term_to_binary()
|> Base.encode64()
|> IO.write()
