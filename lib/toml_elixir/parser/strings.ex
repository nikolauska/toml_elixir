defmodule TomlElixir.Parser.Strings do
  @moduledoc false

  alias TomlElixir.Parser.Error
  alias TomlElixir.Parser.State

  @spec parse_basic(State.t(), keyword) :: {binary, State.t()}
  def parse_basic(%State{} = state, opts) do
    multiline? = Keyword.get(opts, :multiline?, false)

    state =
      if multiline? do
        ensure_prefix!(state, "\"\"\"")
        State.consume_prefix(state, "\"\"\"")
      else
        ensure_prefix!(state, "\"")
        State.consume_prefix(state, "\"")
      end

    state =
      if multiline? do
        trim_initial_newline(state)
      else
        state
      end

    {content, state} = parse_basic_content(state, multiline?, [])
    {content, state}
  end

  @spec parse_literal(State.t(), keyword) :: {binary, State.t()}
  def parse_literal(%State{} = state, opts) do
    multiline? = Keyword.get(opts, :multiline?, false)

    state =
      if multiline? do
        ensure_prefix!(state, "'''")
        State.consume_prefix(state, "'''")
      else
        ensure_prefix!(state, "'")
        State.consume_prefix(state, "'")
      end

    state =
      if multiline? do
        trim_initial_newline(state)
      else
        state
      end

    {content, state} = parse_literal_content(state, multiline?, [])
    {content, state}
  end

  defp parse_basic_content(%State{} = state, multiline?, acc) do
    cond do
      State.eof?(state) ->
        Error.raise("Unterminated string")

      multiline? and State.peek_codepoint(state) == ?\" ->
        count = quote_run_length(state, ?\")

        if count >= 3 do
          to_consume = if count >= 6, do: 3, else: count
          state = State.consume_prefix(state, String.duplicate("\"", to_consume))
          extra = to_consume - 3
          acc = if extra > 0, do: [String.duplicate("\"", extra) | acc], else: acc
          {IO.iodata_to_binary(Enum.reverse(acc)), state}
        else
          {codepoint, state} = State.next_codepoint(state)
          parse_basic_content(state, multiline?, [<<codepoint::utf8>> | acc])
        end

      not multiline? and State.peek_prefix?(state, "\"") ->
        {IO.iodata_to_binary(Enum.reverse(acc)), State.consume_prefix(state, "\"")}

      true ->
        {codepoint, state} = State.next_codepoint(state)

        cond do
          codepoint == ?\n ->
            if multiline? do
              parse_basic_content(state, multiline?, ["\n" | acc])
            else
              Error.raise("Newline in basic string")
            end

          codepoint == ?\r ->
            if multiline? do
              state =
                if State.peek_prefix?(state, "\n") do
                  State.consume_prefix(state, "\n")
                else
                  Error.raise("Bare carriage return")
                end

              parse_basic_content(state, multiline?, ["\n" | acc])
            else
              Error.raise("Newline in basic string")
            end

          codepoint == ?\\ ->
            {segment, state} = parse_basic_escape(state, multiline?)
            parse_basic_content(state, multiline?, [segment | acc])

          basic_control_char?(codepoint) ->
            Error.raise("Control character in string")

          true ->
            parse_basic_content(state, multiline?, [<<codepoint::utf8>> | acc])
        end
    end
  end

  defp parse_literal_content(%State{} = state, multiline?, acc) do
    cond do
      State.eof?(state) ->
        Error.raise("Unterminated literal string")

      multiline? and State.peek_codepoint(state) == ?' ->
        count = quote_run_length(state, ?')

        if count >= 3 do
          to_consume = if count >= 6, do: 3, else: count
          state = State.consume_prefix(state, String.duplicate("'", to_consume))
          extra = to_consume - 3
          acc = if extra > 0, do: [String.duplicate("'", extra) | acc], else: acc
          {IO.iodata_to_binary(Enum.reverse(acc)), state}
        else
          {codepoint, state} = State.next_codepoint(state)
          parse_literal_content(state, multiline?, [<<codepoint::utf8>> | acc])
        end

      not multiline? and State.peek_prefix?(state, "'") ->
        {IO.iodata_to_binary(Enum.reverse(acc)), State.consume_prefix(state, "'")}

      true ->
        {codepoint, state} = State.next_codepoint(state)

        cond do
          codepoint == ?\n ->
            if multiline? do
              parse_literal_content(state, multiline?, ["\n" | acc])
            else
              Error.raise("Newline in literal string")
            end

          codepoint == ?\r ->
            if multiline? do
              state =
                if State.peek_prefix?(state, "\n") do
                  State.consume_prefix(state, "\n")
                else
                  Error.raise("Bare carriage return")
                end

              parse_literal_content(state, multiline?, ["\n" | acc])
            else
              Error.raise("Newline in literal string")
            end

          literal_control_char?(codepoint) ->
            Error.raise("Control character in literal string")

          true ->
            parse_literal_content(state, multiline?, [<<codepoint::utf8>> | acc])
        end
    end
  end

  defp parse_basic_escape(%State{} = state, multiline?) do
    case State.peek_codepoint(state) do
      ?b ->
        {<<0x08>>, State.consume_prefix(state, "b")}

      ?t ->
        {"\t", State.consume_prefix(state, "t")}

      ?n ->
        {"\n", State.consume_prefix(state, "n")}

      ?e ->
        {<<0x1B>>, State.consume_prefix(state, "e")}

      ?f ->
        {<<0x0C>>, State.consume_prefix(state, "f")}

      ?r ->
        {"\r", State.consume_prefix(state, "r")}

      ?\" ->
        {"\"", State.consume_prefix(state, "\"")}

      ?\\ ->
        {"\\", State.consume_prefix(state, "\\")}

      ?u ->
        parse_unicode_escape(state, 4)

      ?U ->
        parse_unicode_escape(state, 8)

      ?x ->
        if state.spec == :"1.1.0" do
          parse_unicode_escape(state, 2)
        else
          Error.raise("Invalid escape sequence")
        end

      nil ->
        Error.raise("Unterminated escape")

      _ when multiline? ->
        parse_line_continuation(state)

      _ ->
        Error.raise("Invalid escape sequence")
    end
  end

  defp parse_unicode_escape(%State{} = state, digits) do
    state = State.consume_prefix(state, <<State.peek_byte(state)>>)
    {hex, state} = take_exact_hex(state, digits, [])
    codepoint = String.to_integer(hex, 16)

    if invalid_codepoint?(codepoint) do
      Error.raise("Invalid Unicode codepoint")
    else
      {<<codepoint::utf8>>, state}
    end
  end

  defp take_exact_hex(%State{} = state, 0, acc) do
    {IO.iodata_to_binary(Enum.reverse(acc)), state}
  end

  defp take_exact_hex(%State{} = state, remaining, acc) do
    case State.peek_codepoint(state) do
      nil ->
        Error.raise("Unexpected end of unicode escape")

      codepoint ->
        if is_hex?(codepoint) do
          {cp, state} = State.next_codepoint(state)
          take_exact_hex(state, remaining - 1, [<<cp::utf8>> | acc])
        else
          Error.raise("Invalid unicode escape")
        end
    end
  end

  defp parse_line_continuation(%State{} = state) do
    {state, saw_space} = consume_spaces_tabs(state)

    case State.peek_codepoint(state) do
      ?\n ->
        state = consume_newline(state, ?\n)
        state = consume_all_whitespace(state)
        {"", state}

      ?\r ->
        state = consume_newline(state, ?\r)
        state = consume_all_whitespace(state)
        {"", state}

      _ ->
        if saw_space do
          Error.raise("Invalid line continuation")
        else
          Error.raise("Invalid escape sequence")
        end
    end
  end

  defp consume_spaces_tabs(%State{} = state) do
    case State.peek_codepoint(state) do
      ?\s -> state |> State.consume_prefix(" ") |> consume_spaces_tabs() |> mark_space(true)
      ?\t -> state |> State.consume_prefix("\t") |> consume_spaces_tabs() |> mark_space(true)
      _ -> {state, false}
    end
  end

  defp mark_space({state, saw?}, _), do: {state, saw? || true}
  defp mark_space(state, true), do: {state, true}

  defp consume_all_whitespace(%State{} = state) do
    case State.peek_codepoint(state) do
      ?\s ->
        consume_all_whitespace(State.consume_prefix(state, " "))

      ?\t ->
        consume_all_whitespace(State.consume_prefix(state, "\t"))

      ?\n ->
        consume_all_whitespace(State.consume_prefix(state, "\n"))

      ?\r ->
        state = consume_newline(state, ?\r)
        consume_all_whitespace(state)

      _ ->
        state
    end
  end

  defp trim_initial_newline(%State{} = state) do
    case State.peek_codepoint(state) do
      ?\n -> State.consume_prefix(state, "\n")
      ?\r -> consume_newline(state, ?\r)
      _ -> state
    end
  end

  defp consume_newline(%State{} = state, ?\n), do: State.consume_prefix(state, "\n")

  defp consume_newline(%State{} = state, ?\r) do
    if State.peek_prefix?(state, "\r\n") do
      State.consume_prefix(state, "\r\n")
    else
      Error.raise("Bare carriage return")
    end
  end

  defp ensure_prefix!(%State{} = state, prefix) do
    if State.peek_prefix?(state, prefix) do
      :ok
    else
      Error.raise("Unexpected string delimiter")
    end
  end

  defp control_char?(codepoint) do
    (codepoint >= 0x00 and codepoint <= 0x08) or
      codepoint == 0x0B or
      codepoint == 0x0C or
      (codepoint >= 0x0E and codepoint <= 0x1F) or
      codepoint == 0x7F
  end

  defp basic_control_char?(codepoint) do
    control_char?(codepoint)
  end

  defp literal_control_char?(codepoint) do
    control_char?(codepoint)
  end

  defp is_hex?(codepoint) do
    (codepoint >= ?0 and codepoint <= ?9) or
      (codepoint >= ?A and codepoint <= ?F) or
      (codepoint >= ?a and codepoint <= ?f)
  end

  defp invalid_codepoint?(codepoint) do
    codepoint > 0x10FFFF or (codepoint >= 0xD800 and codepoint <= 0xDFFF)
  end

  defp quote_run_length(%State{} = state, quote_char) do
    count_quote_run(state, quote_char, 0)
  end

  defp count_quote_run(%State{} = state, quote_char, count) do
    case State.peek_codepoint(state) do
      ^quote_char ->
        state = State.consume_prefix(state, <<quote_char::utf8>>)
        count_quote_run(state, quote_char, count + 1)

      _ ->
        count
    end
  end
end
