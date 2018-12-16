defmodule Jason.Formatter do
  @moduledoc ~S"""
  Pretty-printing and minimizing functions for JSON-encoded data.

  Input is required to be in an 8-bit-wide encoding such as UTF-8 or Latin-1
  in `t:iodata/0` format. Input must ve valid JSON, invalid JSON may produce
  unexpected results or errors.
  """

  @type opts :: [
          {:indent, iodata}
          | {:line_separator, iodata}
          | {:record_separator, iodata}
          | {:after_colon, iodata}
        ]

  import Record
  defrecordp :opts, [:indent, :line, :record, :colon]

  @doc ~S"""
  Pretty-prints JSON-encoded `input`.

  `input` may contain multiple JSON objects or arrays, optionally separated
  by whitespace (e.g., one object per line). Objects in output will be
  separated by newlines. No trailing newline is emitted.

  ## Options

    * `:indent` - used for nested objects and arrays (default: two spaces - `"  "`);
    * `:line_separator` - used in nested objects (default: `"\n"`);
    * `:record_separator` - separates root-level objects and arrays
      (default is the value for `:line_separator` option);
    * `:after_colon` - printed after a colon inside objects (default: one space - `" "`).

  ## Examples

      iex> Jason.Formatter.pretty_print(~s|{"a":{"b": [1, 2]}}|)
      ~s|{
        "a": {
          "b": [
            1,
            2
          ]
        }
      }|

  """
  @spec pretty_print(iodata, opts) :: binary
  def pretty_print(input, opts \\ []) do
    input
    |> pretty_print_to_iodata(opts)
    |> IO.iodata_to_binary()
  end

  @doc ~S"""
  Pretty-prints JSON-encoded `input` and returns iodata.

  This function should be preferred to `pretty_print/2`, if the pretty-printed
  JSON will be handed over to one of the IO functions or sent
  over the socket. The Erlang runtime is able to leverage vectorised
  writes and avoid allocating a continuous buffer for the whole
  resulting string, lowering memory use and increasing performance.
  """
  @spec pretty_print_to_iodata(iodata, opts) :: iodata
  def pretty_print_to_iodata(input, opts \\ []) do
    opts = parse_opts(opts, "  ", "\n", nil, " ")

    depth = :first
    empty = false

    {output, _state} = pp_iodata(input, [], depth, empty, opts)

    output
  end

  @doc ~S"""
  Minimizes JSON-encoded `input`.

  `input` may contain multiple JSON objects or arrays, optionally
  separated by whitespace (e.g., one object per line). Minimized
  output will contain one object per line. No trailing newline is emitted.

  ## Options

    * `:record_separator` - controls the string used as newline (default: `"\n"`).

  ## Examples

      iex> Jason.Formatter.minimize(~s|{ "a" : "b" , "c": \n\n 2}|)
      ~s|{"a":"b","c":2}|

  """
  @spec minimize(iodata, opts) :: binary
  def minimize(input, opts \\ []) do
    input
    |> minimize_to_iodata(opts)
    |> IO.iodata_to_binary()
  end

  @doc ~S"""
  Minimizes JSON-encoded `input` and returns iodata.

  This function should be preferred to `minimize/2`, if the minimized
  JSON will be handed over to one of the IO functions or sent
  over the socket. The Erlang runtime is able to leverage vectorised
  writes and avoid allocating a continuous buffer for the whole
  resulting string, lowering memory use and increasing performance.
  """
  @spec minimize_to_iodata(iodata, opts) :: iodata
  def minimize_to_iodata(input, opts) do
    record = Keyword.get(opts, :record_separator, "\n")
    opts = opts(indent: "", line: "", record: record, colon: "")

    depth = :first
    empty = false

    {output, _state} = pp_iodata(input, [], depth, empty, opts)

    output
  end

  defp parse_opts([{option, value} | opts], indent, line, record, colon) do
    value = IO.iodata_to_binary(value)
    case option do
      :indent -> parse_opts(opts, value, line, record, colon)
      :record_separator -> parse_opts(opts, indent, line, value, colon)
      :after_colon -> parse_opts(opts, indent, line, record, value)
      :line_separator -> parse_opts(opts, indent, value, record || value, colon)
    end
  end

  defp parse_opts([], indent, line, record, colon) do
    opts(indent: indent, line: line, record: record || line, colon: colon)
  end

  for depth <- 1..16 do
    defp tab("  ", unquote(depth)), do: unquote(String.duplicate("  ", depth))
  end

  defp tab("", _), do: ""
  defp tab(indent, depth), do: List.duplicate(indent, depth)

  defp pp_iodata(<<>>, output_acc, depth, empty, opts) do
    {output_acc, &pp_iodata(&1, &2, depth, empty, opts)}
  end

  defp pp_iodata(<<byte, rest::binary>>, output_acc, depth, empty, opts) do
    pp_byte(byte, rest, output_acc, depth, empty, opts)
  end

  defp pp_iodata([], output_acc, depth, empty, opts) do
    {output_acc, &pp_iodata(&1, &2, depth, empty, opts)}
  end

  defp pp_iodata([byte | rest], output_acc, depth, empty, opts) when is_integer(byte) do
    pp_byte(byte, rest, output_acc, depth, empty, opts)
  end

  defp pp_iodata([head | tail], output_acc, depth, empty, opts) do
    {output_acc, cont} = pp_iodata(head, output_acc, depth, empty, opts)
    cont.(tail, output_acc)
  end

  defp pp_byte(byte, rest, output, depth, empty, opts) when byte in ' \n\r\t' do
    pp_iodata(rest, output, depth, empty, opts)
  end

  defp pp_byte(byte, rest, output, depth, empty, opts) when byte in '{[' do
    {out, depth} =
      cond do
        depth == :first -> {byte, 1}
        depth == 0 -> {[opts(opts, :record), byte], 1}
        empty -> {[opts(opts, :line), tab(opts(opts, :indent), depth), byte], depth + 1}
        true -> {byte, depth + 1}
      end

    empty = true
    pp_iodata(rest, [output, out], depth, empty, opts)
  end

  defp pp_byte(byte, rest, output, depth, true = _empty, opts) when byte in '}]' do
    empty = false
    depth = depth - 1
    pp_iodata(rest, [output, byte], depth, empty, opts)
  end

  defp pp_byte(byte, rest, output, depth, false = empty, opts) when byte in '}]' do
    depth = depth - 1
    out = [opts(opts, :line), tab(opts(opts, :indent), depth), byte]
    pp_iodata(rest, [output, out], depth, empty, opts)
  end

  defp pp_byte(byte, rest, output, depth, _empty, opts) when byte in ',' do
    empty = false
    out = [byte, opts(opts, :line), tab(opts(opts, :indent), depth)]
    pp_iodata(rest, [output, out], depth, empty, opts)
  end

  defp pp_byte(byte, rest, output, depth, empty, opts) when byte in ':' do
    out = [byte, opts(opts, :colon)]
    pp_iodata(rest, [output, out], depth, empty, opts)
  end

  defp pp_byte(byte, rest, output, depth, empty, opts) do
    out = if empty, do: [opts(opts, :line), tab(opts(opts, :indent), depth), byte], else: byte
    empty = false

    if byte == ?" do
      pp_string(rest, [output, out], _in_bs = false, &pp_iodata(&1, &2, depth, empty, opts))
    else
      pp_iodata(rest, [output, out], depth, empty, opts)
    end
  end

  defp pp_string(<<>>, output_acc, in_bs, cont) do
    {output_acc, &pp_string(&1, &2, in_bs, cont)}
  end

  defp pp_string(binary, output_acc, true = _in_bs, cont) when is_binary(binary) do
    <<byte, rest::binary>> = binary
    pp_string(rest, [output_acc, byte], false, cont)
  end

  defp pp_string(binary, output_acc, false = _in_bs, cont) when is_binary(binary) do
    case :binary.match(binary, ["\"", "\\"]) do
      :nomatch ->
        {[output_acc | binary], &pp_string(&1, &2, false, cont)}
      {pos, 1} ->
        {head, tail} = :erlang.split_binary(binary, pos + 1)
        case :binary.at(binary, pos) do
          ?\\ -> pp_string(tail, [output_acc | head], true, cont)
          ?" -> cont.(tail, [output_acc | head])
        end
    end
  end

  defp pp_string([], output_acc, in_bs, cont) do
    {output_acc, &pp_string(&1, &2, in_bs, cont)}
  end

  defp pp_string([byte | rest], output_acc, in_bs, cont) when is_integer(byte) do
    cond do
      in_bs -> pp_string(rest, [output_acc, byte], false, cont)
      byte == ?" -> cont.(rest, [output_acc, byte])
      true -> pp_string(rest, [output_acc, byte], byte == ?\\, cont)
    end
  end

  defp pp_string([head | tail], output_acc, in_bs, cont) do
    {output_acc, cont} = pp_string(head, output_acc, in_bs, cont)
    cont.(tail, output_acc)
  end
end
