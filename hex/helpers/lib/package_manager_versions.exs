case Application.load(:hex) do
  :ok -> :ok
  {:error, {:already_loaded, :hex}} -> :ok
  {:error, reason} -> raise "could not load Hex: #{inspect(reason)}"
end

%{
  hex: Application.spec(:hex, :vsn) |> to_string(),
  elixir: System.version()
}
|> JSON.encode!()
|> IO.write()
