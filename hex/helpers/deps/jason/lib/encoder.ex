defprotocol Jason.Encoder do
  @moduledoc """
  Protocol controlling how a value is encoded to JSON.

  ## Deriving

  The protocol allows leveraging the Elixir's `@derive` feature
  to simplify protocol implementation in trivial cases. Accepted
  options are:

    * `:only` - encodes only values of specified keys.
    * `:except` - encodes all struct fields except specified keys.

  By default all keys except the `:__struct__` key are encoded.

  ## Example

  Let's assume a presence of the following struct:

      defmodule Test do
        defstruct [:foo, :bar, :baz]
      end

  If we were to call `@derive Jason.Encoder` just before `defstruct`,
  an implementaion similar to the follwing implementation would be generated:

      defimpl Jason.Encoder, for: Test do
        def encode(value, opts) do
          Jason.Encode.map(Map.take(value, [:foo, :bar, :baz]), opts)
        end
      end

  If we called `@derive {Jason.Encoder, only: [:foo]}`, an implementation
  similar to the following implementation would be genrated:

      defimpl Jason.Encoder, for: Test do
        def encode(value, opts) do
          Jason.Encode.map(Map.take(value, [:foo]), opts)
        end
      end

  If we called `@derive {Jason.Encoder, except: [:foo]}`, an implementation
  similar to the following implementation would be generated:

      defimpl Jason.Encoder, for: Test do
        def encode(value, opts) do
          Jason.Encode.map(Map.take(value, [:bar, :baz]), opts)
        end
      end

  The actually generated implementations are more efficient computing some data
  during compilation similar to the macros from the `Jason.Helpers` module.

  ## Explicit implementation

  If you wish to implement the protocol fully yourself, it is advised to
  use functions from the `Jason.Encode` module to do the actual iodata
  generation - they are highly optimized and verified to always produce
  valid JSON.
  """

  @type t :: term
  @type opts :: Jason.Encode.opts()

  @fallback_to_any true

  @doc """
  Encodes `value` to JSON.

  The argument `opts` is opaque - it can be passed to various functions in
  `Jason.Encode` (or to the protocol function itself) for encoding values to JSON.
  """
  @spec encode(t, opts) :: iodata
  def encode(value, opts)
end

defimpl Jason.Encoder, for: Any do
  defmacro __deriving__(module, struct, opts) do
    fields = fields_to_encode(struct, opts)
    kv = Enum.map(fields, &{&1, generated_var(&1, __MODULE__)})
    escape = quote(do: escape)
    encode_map = quote(do: encode_map)
    encode_args = [escape, encode_map]
    kv_iodata = Jason.Codegen.build_kv_iodata(kv, encode_args)

    quote do
      defimpl Jason.Encoder, for: unquote(module) do
        require Jason.Helpers

        def encode(%{unquote_splicing(kv)}, {unquote(escape), unquote(encode_map)}) do
          unquote(kv_iodata)
        end
      end
    end
  end

  # The same as Macro.var/2 except it sets generated: true
  defp generated_var(name, context) do
    {name, [generated: true], context}
  end

  def encode(%_{} = struct, _opts) do
    raise Protocol.UndefinedError,
      protocol: @protocol,
      value: struct,
      description: """
      Jason.Encoder protocol must always be explicitly implemented.

      If you own the struct, you can derive the implementation specifying \
      which fields should be encoded to JSON:

          @derive {Jason.Encoder, only: [....]}
          defstruct ...

      It is also possible to encode all fields, although this should be \
      used carefully to avoid accidentally leaking private information \
      when new fields are added:

          @derive Jason.Encoder
          defstruct ...

      Finally, if you don't own the struct you want to encode to JSON, \
      you may use Protocol.derive/3 placed outside of any module:

          Protocol.derive(Jason.Encoder, NameOfTheStruct, only: [...])
          Protocol.derive(Jason.Encoder, NameOfTheStruct)
      """
  end

  def encode(value, _opts) do
    raise Protocol.UndefinedError,
      protocol: @protocol,
      value: value,
      description: "Jason.Encoder protocol must always be explicitly implemented"
  end

  defp fields_to_encode(struct, opts) do
    cond do
      only = Keyword.get(opts, :only) ->
        only

      except = Keyword.get(opts, :except) ->
        Map.keys(struct) -- [:__struct__ | except]

      true ->
        Map.keys(struct) -- [:__struct__]
    end
  end
end

# The following implementations are formality - they are already covered
# by the main encoding mechanism in Jason.Encode, but exist mostly for
# documentation purposes and if anybody had the idea to call the protocol directly.

defimpl Jason.Encoder, for: Atom do
  def encode(atom, opts) do
    Jason.Encode.atom(atom, opts)
  end
end

defimpl Jason.Encoder, for: Integer do
  def encode(integer, _opts) do
    Jason.Encode.integer(integer)
  end
end

defimpl Jason.Encoder, for: Float do
  def encode(float, _opts) do
    Jason.Encode.float(float)
  end
end

defimpl Jason.Encoder, for: List do
  def encode(list, opts) do
    Jason.Encode.list(list, opts)
  end
end

defimpl Jason.Encoder, for: Map do
  def encode(map, opts) do
    Jason.Encode.map(map, opts)
  end
end

defimpl Jason.Encoder, for: BitString do
  def encode(binary, opts) when is_binary(binary) do
    Jason.Encode.string(binary, opts)
  end

  def encode(bitstring, _opts) do
    raise Protocol.UndefinedError,
      protocol: @protocol,
      value: bitstring,
      description: "cannot encode a bitstring to JSON"
  end
end

defimpl Jason.Encoder, for: [Date, Time, NaiveDateTime, DateTime] do
  def encode(value, _opts) do
    [?\", @for.to_iso8601(value), ?\"]
  end
end

defimpl Jason.Encoder, for: Decimal do
  def encode(value, _opts) do
    # silence the xref warning
    decimal = Decimal
    [?\", decimal.to_string(value), ?\"]
  end
end

defimpl Jason.Encoder, for: Jason.Fragment do
  def encode(%{encode: encode}, opts) do
    encode.(opts)
  end
end
