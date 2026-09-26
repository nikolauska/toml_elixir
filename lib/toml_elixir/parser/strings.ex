defmodule TomlElixir.Parser.Strings do
  @moduledoc false

  alias TomlElixir.Parser.Error
  alias TomlElixir.Parser.State

  @spec parse_basic(State.t(), State.pos(), boolean) :: {binary, State.pos()}
  def parse_basic(%State{} = state, pos, multiline?) do
    pos =
      if multiline? do
        ensure_prefix!(state, pos, "\"\"\"")
        trim_initial_newline(state, pos + 3)
      else
        ensure_prefix!(state, pos, "\"")
        pos + 1
      end

    parse_basic_content(state, pos, multiline?, [])
  end

  @spec parse_literal(State.t(), State.pos(), boolean) :: {binary, State.pos()}
  def parse_literal(%State{} = state, pos, multiline?) do
    pos =
      if multiline? do
        ensure_prefix!(state, pos, "'''")
        trim_initial_newline(state, pos + 3)
      else
        ensure_prefix!(state, pos, "'")
        pos + 1
      end

    parse_literal_content(state, pos, multiline?, [])
  end

  defp parse_basic_content(%State{} = state, pos, multiline?, acc) do
    cond do
      State.eof?(state, pos) ->
        Error.raise("Unterminated string")

      multiline? and State.peek_byte(state, pos) == ?\" ->
        case count_quote_run(state, pos, ?\", 0) do
          count when count >= 3 -> close_multiline(pos, count, "\"", acc)
          _count -> parse_basic_content(state, pos + 1, multiline?, ["\"" | acc])
        end

      not multiline? and State.peek_byte(state, pos) == ?\" ->
        {finish(acc), pos + 1}

      segment = take_basic_segment(state, pos) ->
        parse_basic_content(state, pos + byte_size(segment), multiline?, [segment | acc])

      true ->
        # Segments stop only at ASCII delimiters and control bytes, so one byte is the
        # whole character here.
        case State.peek_byte(state, pos) do
          ?\n when multiline? ->
            parse_basic_content(state, pos + 1, multiline?, ["\n" | acc])

          ?\r when multiline? ->
            parse_basic_content(state, crlf_end(state, pos), multiline?, ["\n" | acc])

          newline when newline in [?\n, ?\r] ->
            Error.raise("Newline in basic string")

          ?\\ ->
            {segment, pos} = parse_basic_escape(state, pos + 1, multiline?)
            parse_basic_content(state, pos, multiline?, [segment | acc])

          _control ->
            Error.raise("Control character in string")
        end
    end
  end

  defp parse_literal_content(%State{} = state, pos, multiline?, acc) do
    cond do
      State.eof?(state, pos) ->
        Error.raise("Unterminated literal string")

      multiline? and State.peek_byte(state, pos) == ?' ->
        case count_quote_run(state, pos, ?', 0) do
          count when count >= 3 -> close_multiline(pos, count, "'", acc)
          _count -> parse_literal_content(state, pos + 1, multiline?, ["'" | acc])
        end

      not multiline? and State.peek_byte(state, pos) == ?' ->
        {finish(acc), pos + 1}

      segment = take_literal_segment(state, pos) ->
        parse_literal_content(state, pos + byte_size(segment), multiline?, [segment | acc])

      true ->
        # Segments stop only at ASCII delimiters and control bytes, so one byte is the
        # whole character here.
        case State.peek_byte(state, pos) do
          ?\n when multiline? ->
            parse_literal_content(state, pos + 1, multiline?, ["\n" | acc])

          ?\r when multiline? ->
            parse_literal_content(state, crlf_end(state, pos), multiline?, ["\n" | acc])

          newline when newline in [?\n, ?\r] ->
            Error.raise("Newline in literal string")

          _control ->
            Error.raise("Control character in literal string")
        end
    end
  end

  # Up to two quotes directly before the closing delimiter belong to the content.
  defp close_multiline(pos, count, quote, acc) do
    to_consume = if count >= 6, do: 3, else: count
    extra = to_consume - 3
    acc = if extra > 0, do: [String.duplicate(quote, extra) | acc], else: acc
    {finish(acc), pos + to_consume}
  end

  # Segments are sub-binaries of the whole document; copying keeps decoded values from
  # holding the input binary alive.
  defp finish([]), do: ""
  defp finish([segment]), do: :binary.copy(segment)
  defp finish(acc), do: acc |> Enum.reverse() |> IO.iodata_to_binary()

  defp parse_basic_escape(%State{} = state, pos, multiline?) do
    case State.peek_byte(state, pos) do
      ?b ->
        {<<0x08>>, pos + 1}

      ?t ->
        {"\t", pos + 1}

      ?n ->
        {"\n", pos + 1}

      ?e ->
        {<<0x1B>>, pos + 1}

      ?f ->
        {<<0x0C>>, pos + 1}

      ?r ->
        {"\r", pos + 1}

      ?\" ->
        {"\"", pos + 1}

      ?\\ ->
        {"\\", pos + 1}

      ?u ->
        parse_unicode_escape(state, pos + 1, 4)

      ?U ->
        parse_unicode_escape(state, pos + 1, 8)

      ?x ->
        if state.spec == :"1.1.0" do
          parse_unicode_escape(state, pos + 1, 2)
        else
          Error.raise("Invalid escape sequence")
        end

      nil ->
        Error.raise("Unterminated escape")

      _ when multiline? ->
        parse_line_continuation(state, pos)

      _ ->
        Error.raise("Invalid escape sequence")
    end
  end

  defp parse_unicode_escape(%State{} = state, pos, digits) do
    codepoint = hex_value(state, pos, digits, 0)

    if invalid_codepoint?(codepoint) do
      Error.raise("Invalid Unicode codepoint")
    else
      {<<codepoint::utf8>>, pos + digits}
    end
  end

  defp hex_value(%State{}, _pos, 0, acc), do: acc

  defp hex_value(%State{} = state, pos, remaining, acc) do
    case State.peek_byte(state, pos) do
      nil -> Error.raise("Unexpected end of unicode escape")
      digit when digit in ?0..?9 -> hex_value(state, pos + 1, remaining - 1, acc * 16 + digit - ?0)
      digit when digit in ?A..?F -> hex_value(state, pos + 1, remaining - 1, acc * 16 + digit - ?A + 10)
      digit when digit in ?a..?f -> hex_value(state, pos + 1, remaining - 1, acc * 16 + digit - ?a + 10)
      _ -> Error.raise("Invalid unicode escape")
    end
  end

  defp parse_line_continuation(%State{} = state, start) do
    pos = skip_spaces_tabs(state, start)

    case State.peek_byte(state, pos) do
      ?\n ->
        {"", skip_all_whitespace(state, pos + 1)}

      ?\r ->
        {"", skip_all_whitespace(state, crlf_end(state, pos))}

      _ ->
        if pos > start do
          Error.raise("Invalid line continuation")
        else
          Error.raise("Invalid escape sequence")
        end
    end
  end

  defp skip_spaces_tabs(%State{} = state, pos) do
    case State.peek_byte(state, pos) do
      char when char in [?\s, ?\t] -> skip_spaces_tabs(state, pos + 1)
      _ -> pos
    end
  end

  defp skip_all_whitespace(%State{} = state, pos) do
    case State.peek_byte(state, pos) do
      char when char in [?\s, ?\t, ?\n] -> skip_all_whitespace(state, pos + 1)
      ?\r -> skip_all_whitespace(state, crlf_end(state, pos))
      _ -> pos
    end
  end

  defp trim_initial_newline(%State{} = state, pos) do
    case State.peek_byte(state, pos) do
      ?\n -> pos + 1
      ?\r -> crlf_end(state, pos)
      _ -> pos
    end
  end

  defp crlf_end(%State{} = state, pos) do
    if State.peek_prefix?(state, pos, "\r\n") do
      pos + 2
    else
      Error.raise("Bare carriage return")
    end
  end

  defp ensure_prefix!(%State{} = state, pos, prefix) do
    if State.peek_prefix?(state, pos, prefix) do
      :ok
    else
      Error.raise("Unexpected string delimiter")
    end
  end

  defp take_basic_segment(%State{input: input}, pos) do
    rest = :binary.part(input, pos, byte_size(input) - pos)
    take_segment(input, pos, basic_segment_length(rest, 0))
  end

  defp basic_segment_length(<<char, _::binary>>, length)
       when char <= 0x08 or char in 0x0A..0x1F or char in [?\", ?\\, 0x7F] do
    length
  end

  defp basic_segment_length(<<_, rest::binary>>, length), do: basic_segment_length(rest, length + 1)
  defp basic_segment_length("", length), do: length

  defp take_literal_segment(%State{input: input}, pos) do
    rest = :binary.part(input, pos, byte_size(input) - pos)
    take_segment(input, pos, literal_segment_length(rest, 0))
  end

  defp literal_segment_length(<<char, _::binary>>, length) when char <= 0x08 or char in 0x0A..0x1F or char in [?', 0x7F],
    do: length

  defp literal_segment_length(<<_, rest::binary>>, length), do: literal_segment_length(rest, length + 1)
  defp literal_segment_length("", length), do: length

  defp take_segment(_input, _pos, 0), do: nil
  defp take_segment(input, pos, length), do: :binary.part(input, pos, length)

  defp invalid_codepoint?(codepoint) do
    codepoint > 0x10FFFF or (codepoint >= 0xD800 and codepoint <= 0xDFFF)
  end

  defp count_quote_run(%State{} = state, pos, quote_char, count) do
    if State.peek_byte(state, pos) == quote_char do
      count_quote_run(state, pos + 1, quote_char, count + 1)
    else
      count
    end
  end
end
