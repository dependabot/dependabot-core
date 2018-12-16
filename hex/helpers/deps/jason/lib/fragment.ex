defmodule Jason.Fragment do
  defstruct [:encode]

  def new(iodata) when is_list(iodata) or is_binary(iodata) do
    %__MODULE__{encode: fn _ -> iodata end}
  end

  def new(encode) when is_function(encode, 1) do
    %__MODULE__{encode: encode}
  end
end
