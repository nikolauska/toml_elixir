defmodule TomlElixir.Parser.Error do
  @moduledoc """
  Exception raised during TOML parsing.

  Errors returned by `TomlElixir.decode/2` describe where the parser detected the problem:

    * `:offset` - 0-based byte offset into the binary passed to `TomlElixir.decode/2`,
      including a document-leading byte order mark.
    * `:line` - 1-based line number. Lines end at `\\n`, so `\\r\\n` counts as one line break.
    * `:column` - 1-based column counted in Unicode codepoints from the start of the line.
      A document-leading byte order mark does not count as a column.

  The location fields are `nil` when no position is known.
  """

  import Bitwise
  import Kernel, except: [raise: 2]

  defexception [:reason, :line, :column, :offset]

  @type t :: %__MODULE__{
          reason: String.t(),
          line: pos_integer | nil,
          column: pos_integer | nil,
          offset: non_neg_integer | nil
        }

  @spec exception(String.t() | keyword) :: t
  def exception(reason) when is_binary(reason) do
    %__MODULE__{reason: reason}
  end

  def exception(opts) when is_list(opts) do
    %__MODULE__{
      reason: Keyword.get(opts, :reason, "Unknown error"),
      line: Keyword.get(opts, :line),
      column: Keyword.get(opts, :column),
      offset: Keyword.get(opts, :offset)
    }
  end

  @spec message(t) :: String.t()
  def message(%__MODULE__{reason: reason, line: nil}), do: reason
  def message(%__MODULE__{reason: reason, line: line, column: column}), do: "#{reason} at line #{line}, column #{column}"

  @spec raise(String.t()) :: no_return()
  def raise(reason) do
    Kernel.raise(__MODULE__, reason: reason)
  end

  # While parsing, `offset` is relative to the normalized input; `locate/3` converts it
  # once a failure reaches the parser entry point.
  @spec raise(String.t(), non_neg_integer) :: no_return()
  def raise(reason, offset) do
    Kernel.raise(__MODULE__, reason: reason, offset: offset)
  end

  # Value and builder failures do not know their input position. The document parser
  # fills in the token or statement start, keeping positions off the success path.
  @spec reraise_at(t, non_neg_integer, Exception.stacktrace()) :: no_return()
  def reraise_at(%__MODULE__{offset: nil} = error, offset, stacktrace) do
    reraise(%{error | offset: offset}, stacktrace)
  end

  def reraise_at(%__MODULE__{} = error, _offset, stacktrace), do: reraise(error, stacktrace)

  # Line and column are derived only after a failure so successful parses do no
  # line bookkeeping.
  @doc false
  @spec locate(t, binary, non_neg_integer) :: t
  def locate(%__MODULE__{offset: nil} = error, _input, _prefix_size), do: error

  def locate(%__MODULE__{offset: offset} = error, input, prefix_size) do
    before = binary_part(input, 0, min(offset, byte_size(input)))
    newlines = :binary.matches(before, "\n")

    line_start =
      case List.last(newlines) do
        nil -> 0
        {index, 1} -> index + 1
      end

    line_bytes = binary_part(before, line_start, byte_size(before) - line_start)

    %{
      error
      | offset: offset + prefix_size,
        line: length(newlines) + 1,
        column: codepoint_count(line_bytes, 0) + 1
    }
  end

  # Counting non-continuation bytes stays correct even if an offset ever lands inside a
  # multi-byte character, where a UTF-8 decoder would fail.
  defp codepoint_count(<<byte, rest::binary>>, count) when (byte &&& 0xC0) == 0x80, do: codepoint_count(rest, count)
  defp codepoint_count(<<_byte, rest::binary>>, count), do: codepoint_count(rest, count + 1)
  defp codepoint_count(<<>>, count), do: count
end
