defmodule TomlElixir.Document.Parser do
  @moduledoc false

  # Splits a TOML document into source slices that render back to the exact input.
  #
  # Input must already have passed `TomlElixir.Parser.decode/2`. This parser only finds
  # boundaries, so it does not repeat syntax or table validation; anything it accepts that
  # decoding would reject could otherwise drift from the decoder's rules.
  #
  # Items, in source order:
  #
  #   * `{:trivia, raw}` - whole blank or comment-only lines.
  #   * `{:header, :table | :array_table, keys, raw}` - a header line, including its indent,
  #     trailing comment, and line end.
  #   * `{:pair, keys, key_raw, value, suffix}` - `key_raw` runs from the line start to the
  #     value and `suffix` from the value through the line end.
  #
  # Values:
  #
  #   * `{:raw, raw}` - strings, numbers, booleans, and datetimes.
  #   * `{:array, [{before, value, after}], close}`
  #   * `{:inline_table, [{before, keys, key_raw, value, after}], close}`
  #
  # Array and inline table members are separated by single commas when rendered. `close`
  # holds what follows the last member's `after` up to the closing bracket: a trailing comma
  # with its whitespace, or the whitespace of an empty collection.

  alias TomlElixir.Parser.Document
  alias TomlElixir.Parser.State
  alias TomlElixir.Parser.Strings

  @spec parse(binary, atom) :: [tuple]
  def parse(input, spec) do
    input |> State.new(spec) |> parse_items(0, [])
  end

  @spec parse_value(binary, atom) :: tuple
  def parse_value(input, spec) do
    {value, _pos} = input |> State.new(spec) |> value(0)
    value
  end

  defp parse_items(%State{} = state, pos, acc) do
    trivia_end = skip_trivia(state, pos)
    acc = if trivia_end > pos, do: [{:trivia, slice(state, pos, trivia_end)} | acc], else: acc

    if State.eof?(state, trivia_end) do
      Enum.reverse(acc)
    else
      {item, pos} = statement(state, trivia_end)
      parse_items(state, pos, [item | acc])
    end
  end

  # Trivia covers whole lines only, so a statement keeps its own indentation and deleting
  # it leaves surrounding lines untouched.
  defp skip_trivia(%State{} = state, pos) do
    content = Document.skip_spaces(state, pos)

    case State.peek_byte(state, content) do
      nil -> content
      ?# -> skip_trivia(state, line_end(state, Document.skip_comment(state, content)))
      byte when byte in [?\n, ?\r] -> skip_trivia(state, line_end(state, content))
      _ -> pos
    end
  end

  defp statement(%State{} = state, start) do
    content = Document.skip_spaces(state, start)

    if State.peek_byte(state, content) == ?[ do
      {kind, open} = if State.peek_prefix?(state, content, "[["), do: {:array_table, 2}, else: {:table, 1}
      {pos, keys} = Document.parse_key(state, content + open)
      pos = finish_line(state, pos + open)
      {{:header, kind, keys, slice(state, start, pos)}, pos}
    else
      {keys, key_raw, pos} = key_value_prefix(state, start)
      {value, value_end} = value(state, pos)
      pos = finish_line(state, value_end)
      {{:pair, keys, key_raw, value, slice(state, value_end, pos)}, pos}
    end
  end

  defp key_value_prefix(%State{} = state, start) do
    {pos, keys} = Document.parse_key(state, start)
    # `parse_key/2` already consumed the spaces before `=`.
    pos = Document.skip_spaces(state, pos + 1)
    {keys, slice(state, start, pos), pos}
  end

  defp value(%State{} = state, pos) do
    case State.peek_byte(state, pos) do
      ?" -> string(state, pos, &Strings.parse_basic/3, "\"\"\"")
      ?' -> string(state, pos, &Strings.parse_literal/3, "'''")
      ?[ -> members(state, pos + 1, ?], &array_member/3, :array)
      ?{ -> members(state, pos + 1, ?}, &inline_member/3, :inline_table)
      _ -> scalar(state, pos)
    end
  end

  defp string(%State{} = state, pos, parse, multiline_quote) do
    {_value, value_end} = parse.(state, pos, State.peek_prefix?(state, pos, multiline_quote))
    {{:raw, slice(state, pos, value_end)}, value_end}
  end

  defp scalar(%State{} = state, pos) do
    {_token, value_end} = Document.take_scalar_token(state, pos)
    {{:raw, slice(state, pos, value_end)}, value_end}
  end

  defp array_member(%State{} = state, pos, before) do
    {value, pos} = value(state, pos)
    {fn after_raw -> {before, value, after_raw} end, pos}
  end

  defp inline_member(%State{} = state, pos, before) do
    {keys, key_raw, pos} = key_value_prefix(state, pos)
    {value, pos} = value(state, pos)
    {fn after_raw -> {before, keys, key_raw, value, after_raw} end, pos}
  end

  # Arrays and inline tables share one member loop; `member` returns a function that
  # completes the member once the whitespace after it is known.
  defp members(%State{} = state, pos, close_char, member, kind) do
    members(state, pos, close_char, member, kind, [])
  end

  defp members(%State{} = state, pos, close_char, member, kind, acc) do
    content = skip_ws(state, pos)

    if State.peek_byte(state, content) == close_char do
      # Only an empty collection gets here: after a comma, the loop exits on its own.
      {{kind, [], slice(state, pos, content)}, content + 1}
    else
      {complete, value_end} = member.(state, content, slice(state, pos, content))
      separator = skip_ws(state, value_end)
      acc = [complete.(slice(state, value_end, separator)) | acc]

      if State.peek_byte(state, separator) == ?, do
        next = skip_ws(state, separator + 1)

        if State.peek_byte(state, next) == close_char do
          {{kind, Enum.reverse(acc), slice(state, separator, next)}, next + 1}
        else
          members(state, separator + 1, close_char, member, kind, acc)
        end
      else
        {{kind, Enum.reverse(acc), ""}, separator + 1}
      end
    end
  end

  # Validated input only allows newlines and comments inside collections where the spec
  # permits them, so arrays and inline tables can share one whitespace scan.
  defp skip_ws(%State{} = state, pos) do
    pos = Document.skip_spaces(state, pos)

    case State.peek_byte(state, pos) do
      ?# -> skip_ws(state, Document.skip_comment(state, pos))
      byte when byte in [?\n, ?\r] -> skip_ws(state, line_end(state, pos))
      _ -> pos
    end
  end

  defp finish_line(%State{} = state, pos) do
    pos = Document.skip_spaces(state, pos)
    pos = if State.peek_byte(state, pos) == ?#, do: Document.skip_comment(state, pos), else: pos
    line_end(state, pos)
  end

  defp line_end(%State{} = state, pos) do
    case State.peek_byte(state, pos) do
      ?\n -> pos + 1
      ?\r -> pos + 2
      _ -> pos
    end
  end

  defp slice(%State{input: input}, from, to), do: binary_part(input, from, to - from)
end
