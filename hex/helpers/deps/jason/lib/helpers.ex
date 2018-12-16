defmodule Jason.Helpers do
  @moduledoc """
  Provides macro facilities for partial compile-time encoding of JSON.
  """

  alias Jason.{Codegen, Fragment}

  @doc ~S"""
  Encodes a JSON map from a compile-time keyword.

  Encodes the keys at compile time and strives to create as flat iodata
  structure as possible to achieve maximum efficiency. Does encoding
  right at the call site, but returns an `%Jason.Fragment{}` struct
  that needs to be passed to one of the "main" encoding functions -
  for example `Jason.encode/2` for final encoding into JSON - this
  makes it completely transparent for most uses.

  Only allows keys that do not require escaping in any of the supported
  encoding modes. This means only ASCII characters from the range
  0x1F..0x7F excluding '\', '/' and '"' are allowed - this also excludes
  all control characters like newlines.

  Preserves the order of the keys.

  ## Example

      iex> fragment = json_map(foo: 1, bar: 2)
      iex> Jason.encode!(fragment)
      "{\"foo\":1,\"bar\":2}"

  """
  defmacro json_map(kv) do
    escape = quote(do: escape)
    encode_map = quote(do: encode_map)
    encode_args = [escape, encode_map]
    kv_iodata = Codegen.build_kv_iodata(Macro.expand(kv, __CALLER__), encode_args)

    quote do
      %Fragment{
        encode: fn {unquote(escape), unquote(encode_map)} ->
          unquote(kv_iodata)
        end
      }
    end
  end

  @doc ~S"""
  Encodes a JSON map from a variable containing a map and a compile-time
  list of keys.

  It is equivalent to calling `Map.take/2` before encoding. Otherwise works
  similar to `json_map/2`.

  ## Example

      iex> map = %{a: 1, b: 2, c: 3}
      iex> fragment = json_map_take(map, [:c, :b])
      iex> Jason.encode!(fragment)
      "{\"c\":3,\"b\":2}"

  """
  defmacro json_map_take(map, take) do
    take = Macro.expand(take, __CALLER__)
    kv = Enum.map(take, &{&1, generated_var(&1, Codegen)})
    escape = quote(do: escape)
    encode_map = quote(do: encode_map)
    encode_args = [escape, encode_map]
    kv_iodata = Codegen.build_kv_iodata(kv, encode_args)

    quote do
      case unquote(map) do
        %{unquote_splicing(kv)} ->
          %Fragment{
            encode: fn {unquote(escape), unquote(encode_map)} ->
              unquote(kv_iodata)
            end
          }

        other ->
          raise ArgumentError,
                "expected a map with keys: #{unquote(inspect(take))}, got: #{inspect(other)}"
      end
    end
  end

  # The same as Macro.var/2 except it sets generated: true
  defp generated_var(name, context) do
    {name, [generated: true], context}
  end
end
