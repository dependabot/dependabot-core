defmodule Jason.DecodeError do
  @type t :: %__MODULE__{position: integer, data: String.t}

  defexception [:position, :token, :data]

  def message(%{position: position, token: token}) when is_binary(token) do
    "unexpected sequence at position #{position}: #{inspect token}"
  end
  def message(%{position: position, data: data}) when position == byte_size(data) do
    "unexpected end of input at position #{position}"
  end
  def message(%{position: position, data: data}) do
    byte = :binary.at(data, position)
    str = <<byte>>
    if String.printable?(str) do
      "unexpected byte at position #{position}: " <>
        "#{inspect byte, base: :hex} ('#{str}')"
    else
      "unexpected byte at position #{position}: " <>
        "#{inspect byte, base: :hex}"
    end
  end
end

defmodule Jason.Decoder do
  @moduledoc false

  import Bitwise

  alias Jason.{DecodeError, Codegen}

  import Codegen, only: [bytecase: 2, bytecase: 3]

  # @compile :native

  # We use integers instead of atoms to take advantage of the jump table
  # optimization
  @terminate 0
  @array     1
  @key       2
  @object    3

  def parse(data, opts) when is_binary(data) do
    key_decode = key_decode_function(opts)
    string_decode = string_decode_function(opts)
    try do
      value(data, data, 0, [@terminate], key_decode, string_decode)
    catch
      {:position, position} ->
        {:error, %DecodeError{position: position, data: data}}
      {:token, token, position} ->
        {:error, %DecodeError{token: token, position: position, data: data}}
    else
      value ->
        {:ok, value}
    end
  end

  defp key_decode_function(%{keys: :atoms}), do: &String.to_atom/1
  defp key_decode_function(%{keys: :atoms!}), do: &String.to_existing_atom/1
  defp key_decode_function(%{keys: :strings}), do: &(&1)
  defp key_decode_function(%{keys: fun}) when is_function(fun, 1), do: fun

  defp string_decode_function(%{strings: :copy}), do: &:binary.copy/1
  defp string_decode_function(%{strings: :reference}), do: &(&1)

  defp value(data, original, skip, stack, key_decode, string_decode) do
    bytecase data do
      _ in '\s\n\t\r', rest ->
        value(rest, original, skip + 1, stack, key_decode, string_decode)
      _ in '0', rest ->
        number_zero(rest, original, skip, stack, key_decode, string_decode, 1)
      _ in '123456789', rest ->
        number(rest, original, skip, stack, key_decode, string_decode, 1)
      _ in '-', rest ->
        number_minus(rest, original, skip, stack, key_decode, string_decode)
      _ in '"', rest ->
        string(rest, original, skip + 1, stack, key_decode, string_decode, 0)
      _ in '[', rest ->
        array(rest, original, skip + 1, stack, key_decode, string_decode)
      _ in '{', rest ->
        object(rest, original, skip + 1, stack, key_decode, string_decode)
      _ in ']', rest ->
        empty_array(rest, original, skip + 1, stack, key_decode, string_decode)
      _ in 't', rest ->
        case rest do
          <<"rue", rest::bits>> ->
            continue(rest, original, skip + 4, stack, key_decode, string_decode, true)
          <<_::bits>> ->
            error(original, skip)
        end
      _ in 'f', rest ->
        case rest do
          <<"alse", rest::bits>> ->
            continue(rest, original, skip + 5, stack, key_decode, string_decode, false)
          <<_::bits>> ->
            error(original, skip)
        end
      _ in 'n', rest ->
        case rest do
          <<"ull", rest::bits>> ->
            continue(rest, original, skip + 4, stack, key_decode, string_decode, nil)
          <<_::bits>> ->
            error(original, skip)
        end
      _, rest ->
        error(rest, original, skip + 1, stack, key_decode, string_decode)
      <<_::bits>> ->
        error(original, skip)
    end
  end

  defp number_minus(<<?0, rest::bits>>, original, skip, stack, key_decode, string_decode) do
    number_zero(rest, original, skip, stack, key_decode, string_decode, 2)
  end
  defp number_minus(<<byte, rest::bits>>, original, skip, stack, key_decode, string_decode)
       when byte in '123456789' do
    number(rest, original, skip, stack, key_decode, string_decode, 2)
  end
  defp number_minus(<<_rest::bits>>, original, skip, _stack, _key_decode, _string_decode) do
    error(original, skip + 1)
  end

  defp number(<<byte, rest::bits>>, original, skip, stack, key_decode, string_decode, len)
       when byte in '0123456789' do
    number(rest, original, skip, stack, key_decode, string_decode, len + 1)
  end
  defp number(<<?., rest::bits>>, original, skip, stack, key_decode, string_decode, len) do
    number_frac(rest, original, skip, stack, key_decode, string_decode, len + 1)
  end
  defp number(<<e, rest::bits>>, original, skip, stack, key_decode, string_decode, len) when e in 'eE' do
    prefix = binary_part(original, skip, len)
    number_exp_copy(rest, original, skip + len + 1, stack, key_decode, string_decode, prefix)
  end
  defp number(<<rest::bits>>, original, skip, stack, key_decode, string_decode, len) do
    int = String.to_integer(binary_part(original, skip, len))
    continue(rest, original, skip + len, stack, key_decode, string_decode, int)
  end

  defp number_frac(<<byte, rest::bits>>, original, skip, stack, key_decode, string_decode, len)
       when byte in '0123456789' do
    number_frac_cont(rest, original, skip, stack, key_decode, string_decode, len + 1)
  end
  defp number_frac(<<_rest::bits>>, original, skip, _stack, _key_decode, _string_decode, len) do
    error(original, skip + len)
  end

  defp number_frac_cont(<<byte, rest::bits>>, original, skip, stack, key_decode, string_decode, len)
       when byte in '0123456789' do
    number_frac_cont(rest, original, skip, stack, key_decode, string_decode, len + 1)
  end
  defp number_frac_cont(<<e, rest::bits>>, original, skip, stack, key_decode, string_decode, len)
       when e in 'eE' do
    number_exp(rest, original, skip, stack, key_decode, string_decode, len + 1)
  end
  defp number_frac_cont(<<rest::bits>>, original, skip, stack, key_decode, string_decode, len) do
    token = binary_part(original, skip, len)
    float = try_parse_float(token, token, skip)
    continue(rest, original, skip + len, stack, key_decode, string_decode, float)
  end

  defp number_exp(<<byte, rest::bits>>, original, skip, stack, key_decode, string_decode, len)
       when byte in '0123456789' do
    number_exp_cont(rest, original, skip, stack, key_decode, string_decode, len + 1)
  end
  defp number_exp(<<byte, rest::bits>>, original, skip, stack, key_decode, string_decode, len)
       when byte in '+-' do
    number_exp_sign(rest, original, skip, stack, key_decode, string_decode, len + 1)
  end
  defp number_exp(<<_rest::bits>>, original, skip, _stack, _key_decode, _string_decode, len) do
    error(original, skip + len)
  end

  defp number_exp_sign(<<byte, rest::bits>>, original, skip, stack, key_decode, string_decode, len)
       when byte in '0123456789' do
    number_exp_cont(rest, original, skip, stack, key_decode, string_decode, len + 1)
  end
  defp number_exp_sign(<<_rest::bits>>, original, skip, _stack, _key_decode, _string_decode, len) do
    error(original, skip + len)
  end

  defp number_exp_cont(<<byte, rest::bits>>, original, skip, stack, key_decode, string_decode, len)
       when byte in '0123456789' do
    number_exp_cont(rest, original, skip, stack, key_decode, string_decode, len + 1)
  end
  defp number_exp_cont(<<rest::bits>>, original, skip, stack, key_decode, string_decode, len) do
    token = binary_part(original, skip, len)
    float = try_parse_float(token, token, skip)
    continue(rest, original, skip + len, stack, key_decode, string_decode, float)
  end

  defp number_exp_copy(<<byte, rest::bits>>, original, skip, stack, key_decode, string_decode, prefix)
       when byte in '0123456789' do
    number_exp_cont(rest, original, skip, stack, key_decode, string_decode, prefix, 1)
  end
  defp number_exp_copy(<<byte, rest::bits>>, original, skip, stack, key_decode, string_decode, prefix)
       when byte in '+-' do
    number_exp_sign(rest, original, skip, stack, key_decode, string_decode, prefix, 1)
  end
  defp number_exp_copy(<<_rest::bits>>, original, skip, _stack, _key_decode, _string_decode, _prefix) do
    error(original, skip)
  end

  defp number_exp_sign(<<byte, rest::bits>>, original, skip, stack, key_decode, string_decode, prefix, len)
       when byte in '0123456789' do
    number_exp_cont(rest, original, skip, stack, key_decode, string_decode, prefix, len + 1)
  end
  defp number_exp_sign(<<_rest::bits>>, original, skip, _stack, _key_decode, _string_decode, _prefix, len) do
    error(original, skip + len)
  end

  defp number_exp_cont(<<byte, rest::bits>>, original, skip, stack, key_decode, string_decode, prefix, len)
       when byte in '0123456789' do
    number_exp_cont(rest, original, skip, stack, key_decode, string_decode, prefix, len + 1)
  end
  defp number_exp_cont(<<rest::bits>>, original, skip, stack, key_decode, string_decode, prefix, len) do
    suffix = binary_part(original, skip, len)
    string = prefix <> ".0e" <> suffix
    prefix_size = byte_size(prefix)
    initial_skip = skip - prefix_size - 1
    final_skip = skip + len
    token = binary_part(original, initial_skip, prefix_size + len + 1)
    float = try_parse_float(string, token, initial_skip)
    continue(rest, original, final_skip, stack, key_decode, string_decode, float)
  end

  defp number_zero(<<?., rest::bits>>, original, skip, stack, key_decode, string_decode, len) do
    number_frac(rest, original, skip, stack, key_decode, string_decode, len + 1)
  end
  defp number_zero(<<e, rest::bits>>, original, skip, stack, key_decode, string_decode, len) when e in 'eE' do
    number_exp_copy(rest, original, skip + len + 1, stack, key_decode, string_decode, "0")
  end
  defp number_zero(<<rest::bits>>, original, skip, stack, key_decode, string_decode, len) do
    continue(rest, original, skip + len, stack, key_decode, string_decode, 0)
  end

  @compile {:inline, array: 6}

  defp array(rest, original, skip, stack, key_decode, string_decode) do
    value(rest, original, skip, [@array, [] | stack], key_decode, string_decode)
  end

  defp empty_array(<<rest::bits>>, original, skip, stack, key_decode, string_decode) do
    case stack do
      [@array, [] | stack] ->
        continue(rest, original, skip, stack, key_decode, string_decode, [])
      _ ->
        error(original, skip - 1)
    end
  end

  defp array(data, original, skip, stack, key_decode, string_decode, value) do
    bytecase data do
      _ in '\s\n\t\r', rest ->
        array(rest, original, skip + 1, stack, key_decode, string_decode, value)
      _ in ']', rest ->
        [acc | stack] = stack
        value = :lists.reverse(acc, [value])
        continue(rest, original, skip + 1, stack, key_decode, string_decode, value)
      _ in ',', rest ->
        [acc | stack] = stack
        value(rest, original, skip + 1, [@array, [value | acc] | stack], key_decode, string_decode)
      _, _rest ->
        error(original, skip)
      <<_::bits>> ->
        empty_error(original, skip)
    end
  end

  @compile {:inline, object: 6}

  defp object(rest, original, skip, stack, key_decode, string_decode) do
    key(rest, original, skip, [[] | stack], key_decode, string_decode)
  end

  defp object(data, original, skip, stack, key_decode, string_decode, value) do
    bytecase data do
      _ in '\s\n\t\r', rest ->
        object(rest, original, skip + 1, stack, key_decode, string_decode, value)
      _ in '}', rest ->
        skip = skip + 1
        [key, acc | stack] = stack
        final = [{key_decode.(key), value} | acc]
        continue(rest, original, skip, stack, key_decode, string_decode, :maps.from_list(final))
      _ in ',', rest ->
        skip = skip + 1
        [key, acc | stack] = stack
        acc = [{key_decode.(key), value} | acc]
        key(rest, original, skip, [acc | stack], key_decode, string_decode)
      _, _rest ->
        error(original, skip)
      <<_::bits>> ->
        empty_error(original, skip)
    end
  end

  defp key(data, original, skip, stack, key_decode, string_decode) do
    bytecase data do
      _ in '\s\n\t\r', rest ->
        key(rest, original, skip + 1, stack, key_decode, string_decode)
      _ in '}', rest ->
        case stack do
          [[] | stack] ->
            continue(rest, original, skip + 1, stack, key_decode, string_decode, %{})
          _ ->
            error(original, skip)
        end
      _ in '"', rest ->
        string(rest, original, skip + 1, [@key | stack], key_decode, string_decode, 0)
      _, _rest ->
        error(original, skip)
      <<_::bits>> ->
        empty_error(original, skip)
    end
  end

  defp key(data, original, skip, stack, key_decode, string_decode, value) do
    bytecase data do
      _ in '\s\n\t\r', rest ->
        key(rest, original, skip + 1, stack, key_decode, string_decode, value)
      _ in ':', rest ->
        value(rest, original, skip + 1, [@object, value | stack], key_decode, string_decode)
      _, _rest ->
        error(original, skip)
      <<_::bits>> ->
        empty_error(original, skip)
    end
  end

  # TODO: check if this approach would be faster:
  # https://git.ninenines.eu/cowlib.git/tree/src/cow_ws.erl#n469
  # http://bjoern.hoehrmann.de/utf-8/decoder/dfa/
  defp string(data, original, skip, stack, key_decode, string_decode, len) do
    bytecase data, 128 do
      _ in '"', rest ->
        string = string_decode.(binary_part(original, skip, len))
        continue(rest, original, skip + len + 1, stack, key_decode, string_decode, string)
      _ in '\\', rest ->
        part = binary_part(original, skip, len)
        escape(rest, original, skip + len, stack, key_decode, string_decode, part)
      _ in unquote(0x00..0x1F), _rest ->
        error(original, skip)
      _, rest ->
        string(rest, original, skip, stack, key_decode, string_decode, len + 1)
      <<char::utf8, rest::bits>> when char <= 0x7FF ->
        string(rest, original, skip, stack, key_decode, string_decode, len + 2)
      <<char::utf8, rest::bits>> when char <= 0xFFFF ->
        string(rest, original, skip, stack, key_decode, string_decode, len + 3)
      <<_char::utf8, rest::bits>> ->
        string(rest, original, skip, stack, key_decode, string_decode, len + 4)
      <<_::bits>> ->
        empty_error(original, skip + len)
    end
  end

  defp string(data, original, skip, stack, key_decode, string_decode, acc, len) do
    bytecase data, 128 do
      _ in '"', rest ->
        last = binary_part(original, skip, len)
        string = IO.iodata_to_binary([acc | last])
        continue(rest, original, skip + len + 1, stack, key_decode, string_decode, string)
      _ in '\\', rest ->
        part = binary_part(original, skip, len)
        escape(rest, original, skip + len, stack, key_decode, string_decode, [acc | part])
      _ in unquote(0x00..0x1F), _rest ->
        error(original, skip)
      _, rest ->
        string(rest, original, skip, stack, key_decode, string_decode, acc, len + 1)
      <<char::utf8, rest::bits>> when char <= 0x7FF ->
        string(rest, original, skip, stack, key_decode, string_decode, acc, len + 2)
      <<char::utf8, rest::bits>> when char <= 0xFFFF ->
        string(rest, original, skip, stack, key_decode, string_decode, acc, len + 3)
      <<_char::utf8, rest::bits>> ->
        string(rest, original, skip, stack, key_decode, string_decode, acc, len + 4)
      <<_::bits>> ->
        empty_error(original, skip + len)
    end
  end

  defp escape(data, original, skip, stack, key_decode, string_decode, acc) do
    bytecase data do
      _ in 'b', rest ->
        string(rest, original, skip + 2, stack, key_decode, string_decode, [acc | '\b'], 0)
      _ in 't', rest ->
        string(rest, original, skip + 2, stack, key_decode, string_decode, [acc | '\t'], 0)
      _ in 'n', rest ->
        string(rest, original, skip + 2, stack, key_decode, string_decode, [acc | '\n'], 0)
      _ in 'f', rest ->
        string(rest, original, skip + 2, stack, key_decode, string_decode, [acc | '\f'], 0)
      _ in 'r', rest ->
        string(rest, original, skip + 2, stack, key_decode, string_decode, [acc | '\r'], 0)
      _ in '"', rest ->
        string(rest, original, skip + 2, stack, key_decode, string_decode, [acc | '\"'], 0)
      _ in '/', rest ->
        string(rest, original, skip + 2, stack, key_decode, string_decode, [acc | '/'], 0)
      _ in '\\', rest ->
        string(rest, original, skip + 2, stack, key_decode, string_decode, [acc | '\\'], 0)
      _ in 'u', rest ->
        escapeu(rest, original, skip, stack, key_decode, string_decode, acc)
      _, _rest ->
        error(original, skip + 1)
      <<_::bits>> ->
        empty_error(original, skip)
    end
  end

  defmodule Unescape do
    @moduledoc false

    import Bitwise

    @digits Enum.concat([?0..?9, ?A..?F, ?a..?f])

    def unicode_escapes(chars1 \\ @digits, chars2 \\ @digits) do
      for char1 <- chars1, char2 <- chars2 do
        {(char1 <<< 8) + char2, integer8(char1, char2)}
      end
    end

    defp integer8(char1, char2) do
      (integer4(char1) <<< 4) + integer4(char2)
    end

    defp integer4(char) when char in ?0..?9, do: char - ?0
    defp integer4(char) when char in ?A..?F, do: char - ?A + 10
    defp integer4(char) when char in ?a..?f, do: char - ?a + 10

    defp token_error_clause(original, skip, len) do
      quote do
        _ ->
          token_error(unquote_splicing([original, skip, len]))
      end
    end

    defmacro escapeu_first(int, last, rest, original, skip, stack, key_decode, string_decode, acc) do
      clauses = escapeu_first_clauses(last, rest, original, skip, stack, key_decode, string_decode, acc)
      quote location: :keep do
        case unquote(int) do
          unquote(clauses ++ token_error_clause(original, skip, 6))
        end
      end
    end

    defp escapeu_first_clauses(last, rest, original, skip, stack, key_decode, string_decode, acc) do
      for {int, first} <- unicode_escapes(),
          not (first in 0xDC..0xDF) do
        escapeu_first_clause(int, first, last, rest, original, skip, stack, key_decode, string_decode, acc)
      end
    end

    defp escapeu_first_clause(int, first, last, rest, original, skip, stack, key_decode, string_decode, acc)
         when first in 0xD8..0xDB do
      hi =
        quote bind_quoted: [first: first, last: last] do
          0x10000 + ((((first &&& 0x03) <<< 8) + last) <<< 10)
        end
      args = [rest, original, skip, stack, key_decode, string_decode, acc, hi]
      [clause] =
        quote location: :keep do
          unquote(int) -> escape_surrogate(unquote_splicing(args))
        end
      clause
    end

    defp escapeu_first_clause(int, first, last, rest, original, skip, stack, key_decode, string_decode, acc)
         when first <= 0x00 do
      skip = quote do: (unquote(skip) + 6)
      acc =
        quote bind_quoted: [acc: acc, first: first, last: last] do
          if last <= 0x7F do
            # 0?????
            [acc, last]
          else
            # 110xxxx??  10?????
            byte1 = ((0b110 <<< 5) + (first <<< 2)) + (last >>> 6)
            byte2 = (0b10 <<< 6) + (last &&& 0b111111)
            [acc, byte1, byte2]
          end
        end
      args = [rest, original, skip, stack, key_decode, string_decode, acc, 0]
      [clause] =
        quote location: :keep do
          unquote(int) -> string(unquote_splicing(args))
        end
      clause
    end

    defp escapeu_first_clause(int, first, last, rest, original, skip, stack, key_decode, string_decode, acc)
         when first <= 0x07 do
      skip = quote do: (unquote(skip) + 6)
      acc =
        quote bind_quoted: [acc: acc, first: first, last: last] do
          # 110xxx??  10??????
          byte1 = ((0b110 <<< 5) + (first <<< 2)) + (last >>> 6)
          byte2 = (0b10 <<< 6) + (last &&& 0b111111)
          [acc, byte1, byte2]
        end
      args = [rest, original, skip, stack, key_decode, string_decode, acc, 0]
      [clause] =
        quote location: :keep do
          unquote(int) -> string(unquote_splicing(args))
        end
      clause
    end

    defp escapeu_first_clause(int, first, last, rest, original, skip, stack, key_decode, string_decode, acc)
         when first <= 0xFF do
      skip = quote do: (unquote(skip) + 6)
      acc =
        quote bind_quoted: [acc: acc, first: first, last: last] do
          # 1110xxxx  10xxxx??  10??????
          byte1 = (0b1110 <<< 4) + (first >>> 4)
          byte2 = ((0b10 <<< 6) + ((first &&& 0b1111) <<< 2)) + (last >>> 6)
          byte3 = (0b10 <<< 6) + (last &&& 0b111111)
          [acc, byte1, byte2, byte3]
        end
      args = [rest, original, skip, stack, key_decode, string_decode, acc, 0]
      [clause] =
        quote location: :keep do
          unquote(int) -> string(unquote_splicing(args))
        end
      clause
    end

    defmacro escapeu_last(int, original, skip) do
      clauses = escapeu_last_clauses()
      quote location: :keep do
        case unquote(int) do
          unquote(clauses ++ token_error_clause(original, skip, 6))
        end
      end
    end

    defp escapeu_last_clauses() do
      for {int, last} <- unicode_escapes() do
        [clause] =
          quote do
            unquote(int) -> unquote(last)
          end
        clause
      end
    end

    defmacro escapeu_surrogate(int, last, rest, original, skip, stack, key_decode, string_decode, acc,
             hi) do
      clauses = escapeu_surrogate_clauses(last, rest, original, skip, stack, key_decode, string_decode, acc, hi)
      quote location: :keep do
        case unquote(int) do
          unquote(clauses ++ token_error_clause(original, skip, 12))
        end
      end
    end

    defp escapeu_surrogate_clauses(last, rest, original, skip, stack, key_decode, string_decode, acc, hi) do
      digits1 = 'Dd'
      digits2 = Stream.concat([?C..?F, ?c..?f])
      for {int, first} <- unicode_escapes(digits1, digits2) do
        escapeu_surrogate_clause(int, first, last, rest, original, skip, stack, key_decode, string_decode, acc, hi)
      end
    end

    defp escapeu_surrogate_clause(int, first, last, rest, original, skip, stack, key_decode, string_decode, acc, hi) do
      skip = quote do: unquote(skip) + 12
      acc =
        quote bind_quoted: [acc: acc, first: first, last: last, hi: hi] do
          lo = ((first &&& 0x03) <<< 8) + last
          [acc | <<(hi + lo)::utf8>>]
        end
      args = [rest, original, skip, stack, key_decode, string_decode, acc, 0]
      [clause] =
        quote do
          unquote(int) ->
            string(unquote_splicing(args))
        end
      clause
    end
  end

  defp escapeu(<<int1::16, int2::16, rest::bits>>, original, skip, stack, key_decode, string_decode, acc) do
    require Unescape
    last = escapeu_last(int2, original, skip)
    Unescape.escapeu_first(int1, last, rest, original, skip, stack, key_decode, string_decode, acc)
  end
  defp escapeu(<<_rest::bits>>, original, skip, _stack, _key_decode, _string_decode, _acc) do
    empty_error(original, skip)
  end

  # @compile {:inline, escapeu_last: 3}

  defp escapeu_last(int, original, skip) do
    require Unescape
    Unescape.escapeu_last(int, original, skip)
  end

  defp escape_surrogate(<<?\\, ?u, int1::16, int2::16, rest::bits>>, original,
       skip, stack, key_decode, string_decode, acc, hi) do
    require Unescape
    last = escapeu_last(int2, original, skip + 6)
    Unescape.escapeu_surrogate(int1, last, rest, original, skip, stack, key_decode, string_decode, acc, hi)
  end
  defp escape_surrogate(<<_rest::bits>>, original, skip, _stack, _key_decode, _string_decode, _acc, _hi) do
    error(original, skip + 6)
  end

  defp try_parse_float(string, token, skip) do
    :erlang.binary_to_float(string)
  catch
    :error, :badarg ->
      token_error(token, skip)
  end

  defp error(<<_rest::bits>>, _original, skip, _stack, _key_decode, _string_decode) do
    throw {:position, skip - 1}
  end

  defp empty_error(_original, skip) do
    throw {:position, skip}
  end

  @compile {:inline, error: 2, token_error: 2, token_error: 3}
  defp error(_original, skip) do
    throw {:position, skip}
  end

  defp token_error(token, position) do
    throw {:token, token, position}
  end

  defp token_error(token, position, len) do
    throw {:token, binary_part(token, position, len), position}
  end

  @compile {:inline, continue: 7}
  defp continue(rest, original, skip, stack, key_decode, string_decode, value) do
    case stack do
      [@terminate | stack] ->
        terminate(rest, original, skip, stack, key_decode, string_decode, value)
      [@array | stack] ->
        array(rest, original, skip, stack, key_decode, string_decode, value)
      [@key | stack] ->
        key(rest, original, skip, stack, key_decode, string_decode, value)
      [@object | stack] ->
        object(rest, original, skip, stack, key_decode, string_decode, value)
    end
  end

  defp terminate(<<byte, rest::bits>>, original, skip, stack, key_decode, string_decode, value)
       when byte in '\s\n\r\t' do
    terminate(rest, original, skip + 1, stack, key_decode, string_decode, value)
  end
  defp terminate(<<>>, _original, _skip, _stack, _key_decode, _string_decode, value) do
    value
  end
  defp terminate(<<_rest::bits>>, original, skip, _stack, _key_decode, _string_decode, _value) do
    error(original, skip)
  end
end
