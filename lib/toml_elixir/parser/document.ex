defmodule TomlElixir.Parser.Document do
  @moduledoc false

  alias TomlElixir.Parser.Builder
  alias TomlElixir.Parser.Error
  alias TomlElixir.Parser.State
  alias TomlElixir.Parser.Strings
  alias TomlElixir.Parser.Table
  alias TomlElixir.Parser.Value

  @spec decode(binary, atom) :: map
  def decode(input, spec \\ :"1.1.0") do
    state = State.new(input, spec)

    state
    |> parse_document(0, Builder.new())
    |> Builder.to_map()
  end

  defp parse_document(%State{} = state, pos, %Builder{} = builder) do
    pos = skip_blank(state, pos)

    if State.eof?(state, pos) do
      builder
    else
      parse_statement(state, pos, builder)
    end
  end

  defp parse_statement(%State{} = state, pos, %Builder{} = builder) do
    if State.peek_byte(state, pos) == ?[ do
      {pos, type, path} = parse_table_header(state, pos)

      builder =
        case type do
          :table -> Builder.define_table(builder, path)
          :array_table -> Builder.define_array_table(builder, path)
        end

      parse_document(state, consume_line_end(state, pos), builder)
    else
      {pos, key} = parse_key(state, pos)
      pos = skip_spaces(state, pos)
      pos = expect_char(state, pos, ?=)
      pos = skip_spaces(state, pos)
      {pos, value} = parse_value(state, pos)
      builder = Builder.put_value(builder, key, value)
      parse_document(state, consume_line_end(state, pos), builder)
    end
  end

  defp parse_table_header(%State{} = state, pos) do
    cond do
      State.peek_prefix?(state, pos, "[[") ->
        pos = skip_spaces(state, pos + 2)
        {pos, path} = parse_key(state, pos)
        pos = skip_spaces(state, pos)
        pos = expect_prefix(state, pos, "]]")
        {pos, :array_table, path}

      State.peek_prefix?(state, pos, "[") ->
        pos = skip_spaces(state, pos + 1)
        {pos, path} = parse_key(state, pos)
        pos = skip_spaces(state, pos)
        pos = expect_prefix(state, pos, "]")
        {pos, :table, path}

      true ->
        Error.raise("Invalid table header")
    end
  end

  defp parse_key(%State{} = state, pos) do
    {pos, first} = parse_key_part(state, pos)
    parse_key_tail(state, pos, [first])
  end

  defp parse_key_tail(%State{} = state, pos, parts) do
    pos = skip_spaces(state, pos)

    case State.peek_byte(state, pos) do
      ?. ->
        pos = skip_spaces(state, pos + 1)
        {pos, part} = parse_key_part(state, pos)
        parse_key_tail(state, pos, [part | parts])

      _ when tl(parts) == [] ->
        # Most keys have one part, which needs no reversed copy.
        {pos, parts}

      _ ->
        {pos, Enum.reverse(parts)}
    end
  end

  defp parse_key_part(%State{} = state, pos) do
    pos = skip_spaces(state, pos)

    case State.peek_byte(state, pos) do
      ?" ->
        if State.peek_prefix?(state, pos, "\"\"\"") do
          Error.raise("Multiline strings are not allowed in keys")
        end

        {value, pos} = Strings.parse_basic(state, pos, false)
        {pos, value}

      ?' ->
        if State.peek_prefix?(state, pos, "'''") do
          Error.raise("Multiline strings are not allowed in keys")
        end

        {value, pos} = Strings.parse_literal(state, pos, false)
        {pos, value}

      _ ->
        {token, pos} = take_bare_key(state, pos)

        if token == "" do
          Error.raise("Invalid key")
        end

        {pos, token}
    end
  end

  defp parse_value(%State{} = state, pos) do
    case State.peek_byte(state, pos) do
      ?" ->
        {value, pos} = Strings.parse_basic(state, pos, State.peek_prefix?(state, pos, "\"\"\""))
        {pos, value}

      ?' ->
        {value, pos} = Strings.parse_literal(state, pos, State.peek_prefix?(state, pos, "'''"))
        {pos, value}

      ?[ ->
        parse_array(state, pos)

      ?{ ->
        parse_inline_table(state, pos)

      _ ->
        parse_scalar(state, pos)
    end
  end

  defp parse_scalar(%State{} = state, pos) do
    {token, pos} = take_value_token(state, pos)

    {token, pos} =
      if match?(<<_::binary-size(4), ?-, _::binary-size(2), ?-, _::binary-size(2)>>, token) and
           State.peek_byte(state, pos) == ?\s do
        # A space may separate the date and time of a datetime.
        case State.peek_byte(state, pos + 1) do
          digit when digit in ?0..?9 ->
            {time_part, time_end} = take_value_token(state, pos + 1)

            if match?(<<_::binary-size(2), ?:, _::binary-size(2), _::binary>>, time_part) do
              {token <> " " <> time_part, time_end}
            else
              {token, pos}
            end

          _ ->
            {token, pos}
        end
      else
        {token, pos}
      end

    if token == "" do
      Error.raise("Invalid value")
    end

    {pos, Value.parse_scalar(token, state.spec)}
  end

  defp parse_array(%State{} = state, pos) do
    pos = expect_prefix(state, pos, "[")
    pos = skip_array_ws(state, pos)

    if State.peek_byte(state, pos) == ?] do
      {pos + 1, []}
    else
      {pos, values} = parse_array_values(state, pos, [])
      pos = skip_array_ws(state, pos)
      pos = expect_prefix(state, pos, "]")
      {pos, Enum.reverse(values)}
    end
  end

  defp parse_array_values(%State{} = state, pos, acc) do
    {pos, value} = parse_value(state, pos)
    pos = skip_array_ws(state, pos)

    case State.peek_byte(state, pos) do
      ?, ->
        pos = skip_array_ws(state, pos + 1)

        if State.peek_byte(state, pos) == ?] do
          {pos, [value | acc]}
        else
          parse_array_values(state, pos, [value | acc])
        end

      _ ->
        {pos, [value | acc]}
    end
  end

  defp parse_inline_table(%State{} = state, pos) do
    pos = expect_prefix(state, pos, "{")
    pos = skip_inline_ws(state, pos)

    if State.peek_byte(state, pos) == ?} do
      {pos + 1, Builder.inline_table()}
    else
      {pos, table} = parse_inline_table_pairs(state, pos, Builder.inline_table())
      pos = skip_inline_ws(state, pos)
      pos = expect_prefix(state, pos, "}")
      {pos, Table.freeze(table)}
    end
  end

  defp parse_inline_table_pairs(%State{} = state, pos, table) do
    {pos, key} = parse_key(state, pos)
    pos = skip_inline_ws(state, pos)
    pos = expect_char(state, pos, ?=)
    pos = skip_inline_ws(state, pos)
    {pos, value} = parse_value(state, pos)
    table = Builder.put_inline_value(table, key, value)
    pos = skip_inline_ws(state, pos)

    case State.peek_byte(state, pos) do
      ?, ->
        pos = skip_inline_ws(state, pos + 1)

        if State.peek_byte(state, pos) == ?} do
          if state.spec == :"1.1.0" do
            {pos, table}
          else
            Error.raise("Trailing comma in inline table")
          end
        else
          parse_inline_table_pairs(state, pos, table)
        end

      _ ->
        {pos, table}
    end
  end

  defp skip_blank(%State{} = state, pos) do
    pos = skip_spaces(state, pos)

    case State.peek_byte(state, pos) do
      ?# -> skip_blank(state, skip_comment(state, pos))
      ?\n -> skip_blank(state, pos + 1)
      ?\r -> skip_blank(state, crlf_end(state, pos))
      _ -> pos
    end
  end

  defp skip_spaces(%State{input: input}, pos), do: skip_space_index(input, pos)

  defp skip_space_index(input, pos) when pos < byte_size(input) do
    if :binary.at(input, pos) in [?\s, ?\t], do: skip_space_index(input, pos + 1), else: pos
  end

  defp skip_space_index(_input, pos), do: pos

  defp skip_array_ws(%State{} = state, pos) do
    pos = skip_spaces(state, pos)

    case State.peek_byte(state, pos) do
      ?\n -> skip_array_ws(state, pos + 1)
      ?\r -> skip_array_ws(state, crlf_end(state, pos))
      ?# -> skip_array_ws(state, skip_comment(state, pos))
      _ -> pos
    end
  end

  defp skip_inline_ws(%State{} = state, pos) do
    pos = skip_spaces(state, pos)

    case State.peek_byte(state, pos) do
      ?# when state.spec == :"1.1.0" -> skip_inline_ws(state, skip_comment(state, pos))
      ?\n when state.spec == :"1.1.0" -> skip_inline_ws(state, pos + 1)
      ?\r when state.spec == :"1.1.0" -> skip_inline_ws(state, crlf_end(state, pos))
      _ -> pos
    end
  end

  defp skip_comment(%State{input: input} = state, pos) do
    pos = expect_char(state, pos, ?#)
    <<_::binary-size(^pos), rest::binary>> = input
    pos = comment_end(rest, pos)

    if State.peek_byte(state, pos) in [nil, ?\n, ?\r] do
      pos
    else
      Error.raise("Control character in comment")
    end
  end

  # Input is already valid UTF-8, so only ASCII control bytes can end a comment; a byte
  # loop avoids running a regex over the remaining document for every comment.
  defp comment_end(<<char, rest::binary>>, pos) when char == ?\t or char in 0x20..0x7E or char >= 0x80,
    do: comment_end(rest, pos + 1)

  defp comment_end(_rest, pos), do: pos

  defp consume_line_end(%State{} = state, pos) do
    pos = skip_spaces(state, pos)

    pos =
      if State.peek_byte(state, pos) == ?# do
        skip_comment(state, pos)
      else
        pos
      end

    case State.peek_byte(state, pos) do
      nil -> pos
      ?\n -> pos + 1
      ?\r -> crlf_end(state, pos)
      _ -> Error.raise("Unexpected characters after statement")
    end
  end

  defp expect_char(%State{} = state, pos, char) do
    if State.peek_byte(state, pos) == char do
      pos + 1
    else
      Error.raise("Expected #{<<char::utf8>>}")
    end
  end

  defp expect_prefix(%State{} = state, pos, prefix) do
    if State.peek_prefix?(state, pos, prefix) do
      pos + byte_size(prefix)
    else
      Error.raise("Expected #{prefix}")
    end
  end

  defp take_bare_key(%State{input: input}, pos) do
    rest = :binary.part(input, pos, byte_size(input) - pos)
    length = bare_key_length(rest, 0)
    token = input |> :binary.part(pos, length) |> :binary.copy()
    {token, pos + length}
  end

  defp bare_key_length(<<char, rest::binary>>, length)
       when char in ?a..?z or char in ?A..?Z or char in ?0..?9 or char in [?_, ?-] do
    bare_key_length(rest, length + 1)
  end

  defp bare_key_length(_, length), do: length

  defp take_value_token(%State{input: input}, pos) do
    rest = :binary.part(input, pos, byte_size(input) - pos)
    length = value_token_length(rest, 0)
    {:binary.part(input, pos, length), pos + length}
  end

  defp value_token_length(<<char, _::binary>>, length) when char in [?\s, ?\t, ?\n, ?\r, ?,, ?], ?}, ?#], do: length
  defp value_token_length(<<_, rest::binary>>, length), do: value_token_length(rest, length + 1)
  defp value_token_length("", length), do: length

  defp crlf_end(%State{} = state, pos) do
    if State.peek_prefix?(state, pos, "\r\n") do
      pos + 2
    else
      Error.raise("Bare carriage return")
    end
  end
end
