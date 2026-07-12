defmodule TomlElixir.Parser.Document do
  @moduledoc false

  alias TomlElixir.Parser.Builder
  alias TomlElixir.Parser.Error
  alias TomlElixir.Parser.State
  alias TomlElixir.Parser.Strings
  alias TomlElixir.Parser.Table
  alias TomlElixir.Parser.Value

  @comment_end ~r/[\x00-\x08\x0A-\x1F\x7F]/

  @spec decode(binary, atom) :: map
  def decode(input, spec \\ :"1.1.0") do
    state = State.new(input, spec)
    builder = Builder.new()
    {state, builder} = parse_document(state, builder)
    state = skip_blank(state)

    if !State.eof?(state) do
      Error.raise("Unexpected trailing content")
    end

    Builder.to_map(builder)
  end

  defp parse_document(%State{} = state, %Builder{} = builder) do
    state = skip_blank(state)

    if State.eof?(state) do
      {state, builder}
    else
      {state, builder} = parse_statement(state, builder)
      parse_document(state, builder)
    end
  end

  defp parse_statement(%State{} = state, %Builder{} = builder) do
    state = skip_spaces(state)

    if State.peek_prefix?(state, "[") do
      {state, type, path} = parse_table_header(state)

      builder =
        case type do
          :table -> Builder.define_table(builder, path)
          :array_table -> Builder.define_array_table(builder, path)
        end

      state = consume_line_end(state)
      {state, builder}
    else
      {state, key} = parse_key(state)
      state = skip_spaces(state)
      state = expect_char(state, ?=)
      state = skip_spaces(state)
      {state, value} = parse_value(state, false)
      builder = Builder.put_value(builder, key, value)
      state = consume_line_end(state)
      {state, builder}
    end
  end

  defp parse_table_header(%State{} = state) do
    cond_result =
      cond do
        State.peek_prefix?(state, "[[") ->
          state = State.consume_prefix(state, "[[")
          state = skip_spaces(state)
          {state, path} = parse_key(state)
          state = skip_spaces(state)
          state = expect_prefix(state, "]]")
          {:array_table, path, state}

        State.peek_prefix?(state, "[") ->
          state = State.consume_prefix(state, "[")
          state = skip_spaces(state)
          {state, path} = parse_key(state)
          state = skip_spaces(state)
          state = expect_prefix(state, "]")
          {:table, path, state}

        true ->
          Error.raise("Invalid table header")
      end

    normalize_table_header_return(cond_result)
  end

  defp normalize_table_header_return({:array_table, path, state}), do: {state, :array_table, path}
  defp normalize_table_header_return({:table, path, state}), do: {state, :table, path}

  defp parse_key(%State{} = state) do
    {state, first} = parse_key_part(state)
    {state, parts} = parse_key_tail(state, [first])
    {state, Enum.reverse(parts)}
  end

  defp parse_key_tail(%State{} = state, parts) do
    state = skip_spaces(state)

    case State.peek_codepoint(state) do
      ?. ->
        state = State.consume_prefix(state, ".")
        state = skip_spaces(state)
        {state, part} = parse_key_part(state)
        parse_key_tail(state, [part | parts])

      _ ->
        {state, parts}
    end
  end

  defp parse_key_part(%State{} = state) do
    state = skip_spaces(state)

    case State.peek_byte(state) do
      ?" ->
        if State.peek_prefix?(state, "\"\"\"") do
          Error.raise("Multiline strings are not allowed in keys")
        end

        {value, state} = Strings.parse_basic(state, false)
        {state, value}

      ?' ->
        if State.peek_prefix?(state, "'''") do
          Error.raise("Multiline strings are not allowed in keys")
        end

        {value, state} = Strings.parse_literal(state, false)
        {state, value}

      _ ->
        {token, state} = take_bare_key(state)

        if token == "" do
          Error.raise("Invalid key")
        end

        {state, token}
    end
  end

  defp parse_value(%State{} = state, inline?) do
    case State.peek_byte(state) do
      ?" ->
        {value, state} = Strings.parse_basic(state, State.peek_prefix?(state, "\"\"\""))
        {state, value}

      ?' ->
        {value, state} = Strings.parse_literal(state, State.peek_prefix?(state, "'''"))
        {state, value}

      ?[ ->
        {state, value} = parse_array(state, inline?)
        {state, value}

      ?{ ->
        {state, value} = parse_inline_table(state)
        {state, value}

      _ ->
        {token, state} = take_value_token(state)

        {token, state} =
          if match?(<<_::binary-size(4), ?-, _::binary-size(2), ?-, _::binary-size(2)>>, token) and
               State.peek_codepoint(state) == ?\s do
            state_after_space = State.consume_prefix(state, " ")

            case State.peek_codepoint(state_after_space) do
              digit when digit in ?0..?9 ->
                {time_part, state_after_time} = take_value_token(state_after_space)

                if match?(<<_::binary-size(2), ?:, _::binary-size(2), _::binary>>, time_part) do
                  {token <> " " <> time_part, state_after_time}
                else
                  {token, state}
                end

              _ ->
                {token, state}
            end
          else
            {token, state}
          end

        if token == "" do
          Error.raise("Invalid value")
        end

        {state, Value.parse_scalar(token, state.spec)}
    end
  end

  defp parse_array(%State{} = state, inline?) do
    state = expect_prefix(state, "[")
    state = skip_array_ws(state, inline?)

    if State.peek_prefix?(state, "]") do
      {State.consume_prefix(state, "]"), []}
    else
      {state, values} = parse_array_values(state, inline?, [])
      state = skip_array_ws(state, inline?)
      state = expect_prefix(state, "]")
      {state, Enum.reverse(values)}
    end
  end

  defp parse_array_values(%State{} = state, inline?, acc) do
    {state, value} = parse_value(state, inline?)
    state = skip_array_ws(state, inline?)

    case State.peek_codepoint(state) do
      ?, ->
        state = State.consume_prefix(state, ",")
        state = skip_array_ws(state, inline?)

        if State.peek_prefix?(state, "]") do
          {state, [value | acc]}
        else
          parse_array_values(state, inline?, [value | acc])
        end

      _ ->
        {state, [value | acc]}
    end
  end

  defp parse_inline_table(%State{} = state) do
    state = expect_prefix(state, "{")
    state = skip_inline_ws(state)

    if State.peek_prefix?(state, "}") do
      {State.consume_prefix(state, "}"), Builder.inline_table()}
    else
      {state, table} = parse_inline_table_pairs(state, Builder.inline_table())
      state = skip_inline_ws(state)
      state = expect_prefix(state, "}")
      {state, Table.freeze(table)}
    end
  end

  defp parse_inline_table_pairs(%State{} = state, table) do
    {state, key} = parse_key(state)
    state = skip_inline_ws(state)
    state = expect_char(state, ?=)
    state = skip_inline_ws(state)
    {state, value} = parse_value(state, true)
    table = Builder.put_inline_value(table, key, value)
    state = skip_inline_ws(state)

    case State.peek_codepoint(state) do
      ?, ->
        state = State.consume_prefix(state, ",")
        state = skip_inline_ws(state)

        if State.peek_prefix?(state, "}") do
          if state.spec == :"1.1.0" do
            {state, table}
          else
            Error.raise("Trailing comma in inline table")
          end
        else
          parse_inline_table_pairs(state, table)
        end

      _ ->
        {state, table}
    end
  end

  defp skip_blank(%State{} = state) do
    state = skip_spaces(state)

    case State.peek_codepoint(state) do
      ?# ->
        state = skip_comment(state)
        skip_blank(state)

      ?\n ->
        skip_blank(State.consume_prefix(state, "\n"))

      ?\r ->
        state = consume_newline(state)
        skip_blank(state)

      _ ->
        state
    end
  end

  defp skip_spaces(%State{input: input, index: index} = state) do
    if index < byte_size(input) and :binary.at(input, index) in [?\s, ?\t] do
      %{state | index: skip_space_index(input, index + 1)}
    else
      state
    end
  end

  defp skip_space_index(input, index) when index < byte_size(input) do
    if :binary.at(input, index) in [?\s, ?\t], do: skip_space_index(input, index + 1), else: index
  end

  defp skip_space_index(_input, index), do: index

  defp skip_array_ws(%State{} = state, inline?) do
    case State.peek_codepoint(state) do
      ?\s ->
        skip_array_ws(State.consume_prefix(state, " "), inline?)

      ?\t ->
        skip_array_ws(State.consume_prefix(state, "\t"), inline?)

      ?\n ->
        skip_array_ws(State.consume_prefix(state, "\n"), inline?)

      ?\r ->
        state = consume_newline(state)
        skip_array_ws(state, inline?)

      ?# ->
        state = skip_comment(state)
        skip_array_ws(state, inline?)

      _ ->
        state
    end
  end

  defp skip_inline_ws(%State{} = state) do
    state = skip_spaces(state)

    case State.peek_codepoint(state) do
      ?# ->
        if state.spec == :"1.1.0" do
          state = skip_comment(state)
          skip_inline_ws(state)
        else
          state
        end

      ?\n ->
        if state.spec == :"1.1.0" do
          skip_inline_ws(State.consume_prefix(state, "\n"))
        else
          state
        end

      ?\r ->
        if state.spec == :"1.1.0" do
          state = consume_newline(state)
          skip_inline_ws(state)
        else
          state
        end

      _ ->
        state
    end
  end

  defp skip_comment(%State{input: input} = state) do
    state = expect_char(state, ?#)

    case Regex.run(@comment_end, input, return: :index, offset: state.index) do
      nil ->
        %{state | index: byte_size(input)}

      [{index, 1}] ->
        if :binary.at(input, index) in [?\n, ?\r] do
          %{state | index: index}
        else
          Error.raise("Control character in comment")
        end
    end
  end

  defp consume_line_end(%State{} = state) do
    state = skip_spaces(state)

    state =
      if State.peek_codepoint(state) == ?# do
        skip_comment(state)
      else
        state
      end

    case State.peek_codepoint(state) do
      nil -> state
      ?\n -> State.consume_prefix(state, "\n")
      ?\r -> consume_newline(state)
      _ -> Error.raise("Unexpected characters after statement")
    end
  end

  defp expect_char(%State{} = state, char) do
    case State.peek_codepoint(state) do
      ^char -> State.consume_prefix(state, <<char::utf8>>)
      _ -> Error.raise("Expected #{<<char::utf8>>}")
    end
  end

  defp expect_prefix(%State{} = state, prefix) do
    if State.peek_prefix?(state, prefix) do
      State.consume_prefix(state, prefix)
    else
      Error.raise("Expected #{prefix}")
    end
  end

  defp take_bare_key(%State{input: input, index: index} = state) do
    rest = :binary.part(input, index, byte_size(input) - index)
    length = bare_key_length(rest, 0)
    token = input |> :binary.part(index, length) |> :binary.copy()
    {token, %{state | index: index + length}}
  end

  defp bare_key_length(<<char, rest::binary>>, length)
       when char in ?a..?z or char in ?A..?Z or char in ?0..?9 or char in [?_, ?-] do
    bare_key_length(rest, length + 1)
  end

  defp bare_key_length(_, length), do: length

  defp take_value_token(%State{input: input, index: index} = state) do
    rest = :binary.part(input, index, byte_size(input) - index)
    length = value_token_length(rest, 0)
    token = :binary.part(input, index, length)
    {token, %{state | index: index + length}}
  end

  defp value_token_length(<<char, _::binary>>, length) when char in [?\s, ?\t, ?\n, ?\r, ?,, ?], ?}, ?#], do: length
  defp value_token_length(<<_, rest::binary>>, length), do: value_token_length(rest, length + 1)
  defp value_token_length("", length), do: length

  defp consume_newline(%State{} = state) do
    if State.peek_prefix?(state, "\r\n") do
      State.consume_prefix(state, "\r\n")
    else
      Error.raise("Bare carriage return")
    end
  end
end
