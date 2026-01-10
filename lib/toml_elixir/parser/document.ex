defmodule TomlElixir.Parser.Document do
  @moduledoc false

  alias TomlElixir.Parser.Builder
  alias TomlElixir.Parser.Error
  alias TomlElixir.Parser.State
  alias TomlElixir.Parser.Strings
  alias TomlElixir.Parser.Table
  alias TomlElixir.Parser.Value

  @spec parse(binary, atom) :: map
  def parse(input, spec \\ :"1.1.0") do
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
      {state, value} = parse_value(state, inline?: false)
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

    cond do
      State.peek_prefix?(state, "\"\"\"") ->
        Error.raise("Multiline strings are not allowed in keys")

      State.peek_prefix?(state, "'''") ->
        Error.raise("Multiline strings are not allowed in keys")

      State.peek_prefix?(state, "\"") ->
        {value, state} = Strings.parse_basic(state, multiline?: false)
        {state, value}

      State.peek_prefix?(state, "'") ->
        {value, state} = Strings.parse_literal(state, multiline?: false)
        {state, value}

      true ->
        {token, state} = take_while(state, &bare_key_char?/1, [])

        if token == "" do
          Error.raise("Invalid key")
        end

        {state, token}
    end
  end

  defp parse_value(%State{} = state, opts) do
    inline? = Keyword.get(opts, :inline?, false)

    cond do
      State.peek_prefix?(state, "\"\"\"") ->
        {value, state} = Strings.parse_basic(state, multiline?: true)
        {state, value}

      State.peek_prefix?(state, "'''") ->
        {value, state} = Strings.parse_literal(state, multiline?: true)
        {state, value}

      State.peek_prefix?(state, "\"") ->
        {value, state} = Strings.parse_basic(state, multiline?: false)
        {state, value}

      State.peek_prefix?(state, "'") ->
        {value, state} = Strings.parse_literal(state, multiline?: false)
        {state, value}

      State.peek_prefix?(state, "[") ->
        {state, value} = parse_array(state, inline?: inline?)
        {state, value}

      State.peek_prefix?(state, "{") ->
        {state, value} = parse_inline_table(state)
        {state, value}

      true ->
        {token, state} = take_while(state, &value_token_char?/1, [])

        {token, state} =
          if Regex.match?(~r/\A\d{4}-\d{2}-\d{2}\z/, token) and State.peek_codepoint(state) == ?\s do
            state_after_space = State.consume_prefix(state, " ")

            case State.peek_codepoint(state_after_space) do
              digit when digit in ?0..?9 ->
                {time_part, state_after_time} = take_while(state_after_space, &value_token_char?/1, [])

                if Regex.match?(~r/\A\d{2}:\d{2}/, time_part) do
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

  defp parse_array(%State{} = state, opts) do
    inline? = Keyword.get(opts, :inline?, false)

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
    {state, value} = parse_value(state, inline?: inline?)
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
    {state, value} = parse_value(state, inline?: true)
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

  defp skip_spaces(%State{} = state) do
    case State.peek_codepoint(state) do
      ?\s -> skip_spaces(State.consume_prefix(state, " "))
      ?\t -> skip_spaces(State.consume_prefix(state, "\t"))
      _ -> state
    end
  end

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

  defp skip_comment(%State{} = state) do
    state = expect_char(state, ?#)
    {_, state} = take_while(state, &comment_char?/1, [])
    state
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

  defp take_while(%State{} = state, predicate, acc) do
    case State.peek_codepoint(state) do
      nil ->
        {IO.iodata_to_binary(Enum.reverse(acc)), state}

      codepoint ->
        if predicate.(codepoint) do
          {cp, state} = State.next_codepoint(state)
          take_while(state, predicate, [<<cp::utf8>> | acc])
        else
          {IO.iodata_to_binary(Enum.reverse(acc)), state}
        end
    end
  end

  defp bare_key_char?(codepoint) do
    (codepoint >= ?a and codepoint <= ?z) or
      (codepoint >= ?A and codepoint <= ?Z) or
      (codepoint >= ?0 and codepoint <= ?9) or
      codepoint == ?_ or
      codepoint == ?-
  end

  defp value_token_char?(codepoint) do
    case codepoint do
      ?\s -> false
      ?\t -> false
      ?\n -> false
      ?\r -> false
      ?, -> false
      ?] -> false
      ?} -> false
      ?# -> false
      _ -> true
    end
  end

  defp comment_char?(codepoint) do
    not control_char?(codepoint) and codepoint != ?\n and codepoint != ?\r
  end

  defp control_char?(codepoint) do
    (codepoint >= 0x00 and codepoint <= 0x08) or
      codepoint == 0x0B or
      codepoint == 0x0C or
      (codepoint >= 0x0E and codepoint <= 0x1F) or
      codepoint == 0x7F
  end

  defp consume_newline(%State{} = state) do
    if State.peek_prefix?(state, "\r\n") do
      State.consume_prefix(state, "\r\n")
    else
      Error.raise("Bare carriage return")
    end
  end
end
