defmodule TomlElixir.Parser.State do
  @moduledoc false

  defstruct input: "", index: 0, spec: :"1.1.0"

  @type t :: %__MODULE__{input: binary, index: non_neg_integer, spec: atom}

  @spec new(binary, atom) :: t
  def new(input, spec \\ :"1.1.0") when is_binary(input) do
    %__MODULE__{input: input, index: 0, spec: spec}
  end

  @spec eof?(t) :: boolean
  def eof?(%__MODULE__{input: input, index: index}) do
    index >= byte_size(input)
  end

  @spec peek_byte(t) :: integer | nil
  def peek_byte(%__MODULE__{} = state) do
    if eof?(state) do
      nil
    else
      :binary.at(state.input, state.index)
    end
  end

  @spec peek_prefix?(t, binary) :: boolean
  def peek_prefix?(%__MODULE__{} = state, prefix) do
    prefix_size = byte_size(prefix)
    remaining = byte_size(state.input) - state.index

    if remaining < prefix_size do
      false
    else
      :binary.part(state.input, state.index, prefix_size) == prefix
    end
  end

  @spec consume_prefix(t, binary) :: t
  def consume_prefix(%__MODULE__{} = state, prefix) do
    %{state | index: state.index + byte_size(prefix)}
  end

  @spec next_codepoint(t) :: {integer | nil, t}
  def next_codepoint(%__MODULE__{} = state) do
    if eof?(state) do
      {nil, state}
    else
      <<_::binary-size(state.index), rest::binary>> = state.input
      <<codepoint::utf8, _::binary>> = rest
      size = byte_size(<<codepoint::utf8>>)
      {codepoint, %{state | index: state.index + size}}
    end
  end

  @spec peek_codepoint(t) :: integer | nil
  def peek_codepoint(%__MODULE__{} = state) do
    if eof?(state) do
      nil
    else
      <<_::binary-size(state.index), rest::binary>> = state.input
      <<codepoint::utf8, _::binary>> = rest
      codepoint
    end
  end
end
