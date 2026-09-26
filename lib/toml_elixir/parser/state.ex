defmodule TomlElixir.Parser.State do
  @moduledoc false

  # The parser threads the byte position as a separate integer instead of storing it
  # here: rebuilding a struct for every consumed token was a large share of decode
  # allocations, and garbage collection dominates decode time on large documents.
  defstruct input: "", spec: :"1.1.0"

  @type t :: %__MODULE__{input: binary, spec: atom}
  @type pos :: non_neg_integer

  @spec new(binary, atom) :: t
  def new(input, spec \\ :"1.1.0") when is_binary(input) do
    %__MODULE__{input: input, spec: spec}
  end

  @spec eof?(t, pos) :: boolean
  def eof?(%__MODULE__{input: input}, pos) do
    pos >= byte_size(input)
  end

  @spec peek_byte(t, pos) :: integer | nil
  def peek_byte(%__MODULE__{input: input}, pos) do
    if pos >= byte_size(input) do
      nil
    else
      :binary.at(input, pos)
    end
  end

  @spec peek_prefix?(t, pos, binary) :: boolean
  def peek_prefix?(%__MODULE__{input: input}, pos, prefix) do
    byte_size(input) - pos >= byte_size(prefix) and prefix_at?(input, pos, prefix, 0)
  end

  # Compares byte by byte because slicing the input for `==` allocates a sub-binary on
  # every delimiter check.
  defp prefix_at?(_input, _pos, prefix, offset) when offset == byte_size(prefix), do: true

  defp prefix_at?(input, pos, prefix, offset) do
    :binary.at(input, pos + offset) == :binary.at(prefix, offset) and prefix_at?(input, pos, prefix, offset + 1)
  end
end
