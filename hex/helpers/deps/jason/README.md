# Jason

A blazing fast JSON parser and generator in pure Elixir.

The parser and generator are at least twice as fast as other Elixir/Erlang libraries
(most notably `Poison`).
The performance is comparable to `jiffy`, which is implemented in C as a NIF.
Jason is usually only twice as slow.

Both parser and generator fully conform to
[RFC 8259](https://tools.ietf.org/html/rfc8259) and
[ECMA 404](http://www.ecma-international.org/publications/standards/Ecma-404.htm)
standards. The parser is tested using [JSONTestSuite](https://github.com/nst/JSONTestSuite).

## Installation

The package can be installed by adding `jason` to your list of dependencies
in `mix.exs`:

```elixir
def deps do
  [{:jason, "~> 1.1"}]
end
```

## Basic Usage

``` elixir
iex(1)> Jason.encode!(%{"age" => 44, "name" => "Steve Irwin", "nationality" => "Australian"})
"{\"age\":44,\"name\":\"Steve Irwin\",\"nationality\":\"Australian\"}"

iex(2)> Jason.decode!(~s({"age":44,"name":"Steve Irwin","nationality":"Australian"}))
%{"age" => 44, "name" => "Steve Irwin", "nationality" => "Australian"}
```

Full documentation can be found at [https://hexdocs.pm/jason](https://hexdocs.pm/jason).

## Use with other libraries

### Postgrex

You need to define a custom "types" module in an `.ex` file, somewhere in `lib`:

```elixir
Postgrex.Types.define(MyApp.PostgresTypes, [], json: Jason)

## If using with ecto, you also need to pass ecto default extensions:

Postgrex.Types.define(MyApp.PostgresTypes, [] ++ Ecto.Adapters.Postgres.extensions(), json: Jason)
```

Then you can use the module, by passing it to `Postgrex.start_link`.
### Ecto

To replicate fully the current behaviour of `Poison` when used in Ecto applications,
you need to configure `Jason` to be the default encoder in `config/config.exs`:

```elixir
config :ecto, json_library: Jason
```

Additionally, when using PostgreSQL, you need to define a custom types module as described
above, and configure your repo to use it (in either `config/config.exs` or `config/<env>.exs`):

```elixir
config :my_app, MyApp.Repo, types: MyApp.PostgresTypes
```

### Plug (and Phoenix)

First, you need to configure `Plug.Parsers` to use `Jason` for parsing JSON. You need to find,
where you're plugging the `Plug.Parsers` plug (in case of Phoenix, it will be in the
Endpoint module) and configure it in your endpoint module (`lib/app_web/endpoint.ex`),
for example:

```elixir
plug Plug.Parsers,
  parsers: [:urlencoded, :multipart, :json],
  pass: ["*/*"],
  json_decoder: Jason
```

Additionally, for Phoenix, you need to configure the "encoder" in `config/config.exs`:

```elixir
config :phoenix, :format_encoders,
  json: Jason
```

A custom JSON encoder for Phoenix channels is unfortunately a bit more involved,
you can find code for a custom serializer and how to use it [in here](https://gist.github.com/michalmuskala/d5fabcd26be2befdfb72b72e0b0f2797).

### Absinthe

You need to pass the `:json_codec` option to `Absinthe.Plug`

```elixir
# When called directly:
plug Absinthe.Plug,
  schema: MyApp.Schema,
  json_codec: Jason

# When used in phoenix router:
forward "/api",
  to: Absinthe.Plug,
  init_opts: [schema: MyApp.Schema, json_codec: Jason]
```

## Benchmarks

Detailed benchmarks (including memory measurements):
https://gist.github.com/michalmuskala/4d64a5a7696ca84ac7c169a0206640d5

HTML reports for the benchmark (only performance measurements):
http://michal.muskala.eu/jason/decode.html and http://michal.muskala.eu/jason/encode.html

### Running

Benchmarks against most popular Elixir & Erlang json libraries can be executed
with `mix bench.encode` and `mix bench.decode`.
A HTML report of the benchmarks (after their execution) can be found in
`bench/output/encode.html` and `bench/output/decode.html` respectively.

## Differences to Poison

Jason has a couple feature differences compared to Poison.

  * Jason follows the JSON spec more strictly, for example it does not allow
    unescaped newline characters in JSON strings - e.g. `"\"\n\""` will
    produce a decoding error.
  * no support for decoding into data structures (the `as:` option).
  * no built-in encoders for `MapSet`, `Range` and `Stream`.
  * no support for encoding arbitrary structs - explicit implementation
    of the `Jason.Encoder` protocol is always required.
  * different pretty-printing customisation options (default `pretty: true` works the same)

If you require encoders for any of the unsupported collection types, I suggest
adding the needed implementations directly to your project:

```elixir
defimpl Jason.Encoder, for: [MapSet, Range, Stream] do
  def encode(struct, opts) do
    Jason.Encode.list(Enum.to_list(struct), opts)
  end
end
```

If you need to encode some struct that does not implement the protocol,
if you own the struct, you can derive the implementation specifying
which fields should be encoded to JSON:

```elixir
@derive {Jason.Encoder, only: [....]}
defstruct # ...
```

It is also possible to encode all fields, although this should be
used carefully to avoid accidentally leaking private information
when new fields are added:

```elixir
@derive Jason.Encoder
defstruct # ...
```

Finally, if you don't own the struct you want to encode to JSON,
you may use `Protocol.derive/3` placed outside of any module:

```elixir
Protocol.derive(Jason.Encoder, NameOfTheStruct, only: [...])
Protocol.derive(Jason.Encoder, NameOfTheStruct)
```

## License

Jason is released under the Apache 2.0 License - see the [LICENSE](LICENSE) file.

Some elements of tests and benchmarks have their origins in the
[Poison library](https://github.com/devinus/poison) and were initially licensed under [CC0-1.0](https://creativecommons.org/publicdomain/zero/1.0/).
