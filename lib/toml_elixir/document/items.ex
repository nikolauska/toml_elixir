defmodule TomlElixir.Document.Items do
  @moduledoc false

  # Rendering, path resolution, and value edits over the items produced by
  # `TomlElixir.Document.Parser`.

  alias TomlElixir.Encoder.Helpers

  @type item :: tuple
  @type path :: [String.t() | non_neg_integer]

  @spec render([item]) :: iodata
  def render(items), do: Enum.map(items, &render_item/1)

  defp render_item({:trivia, raw}), do: raw
  defp render_item({:header, _kind, _keys, raw}), do: raw
  defp render_item({:pair, _keys, key_raw, value, suffix}), do: [key_raw, render_value(value), suffix]

  defp render_value({:raw, raw}), do: raw

  defp render_value({:array, members, close}) do
    rendered =
      Enum.map_intersperse(members, ?,, fn {before, value, after_raw} -> [before, render_value(value), after_raw] end)

    [?[, rendered, close, ?]]
  end

  defp render_value({:inline_table, members, close}) do
    rendered =
      Enum.map_intersperse(members, ?,, fn {before, _keys, key_raw, value, after_raw} ->
        [before, key_raw, render_value(value), after_raw]
      end)

    [?{, rendered, close, ?}]
  end

  @doc """
  Pairs each item with its index, the full path of the table its section opens, and its
  own full path: the header's table for headers, the key's path for pairs, `nil` for trivia.
  """
  @spec annotate([item]) :: [{non_neg_integer, item, path, path | nil}]
  def annotate(items) do
    {annotated, _context} =
      items
      |> Enum.with_index()
      |> Enum.map_reduce({[], %{}}, fn
        {{:header, kind, keys, _raw} = item, index}, {_table, arrays} ->
          {path, arrays} = header_path(kind, keys, arrays)
          {{index, item, path, path}, {path, arrays}}

        {{:pair, keys, _key_raw, _value, _suffix} = item, index}, {table, _arrays} = context ->
          {{index, item, table, table ++ keys}, context}

        {{:trivia, _raw} = item, index}, {table, _arrays} = context ->
          {{index, item, table, nil}, context}
      end)

    annotated
  end

  # A header resolves through the latest entry of every array of tables above it, so
  # `arrays` tracks the last index of each array of tables by its full path.
  defp header_path(kind, keys, arrays) do
    # Built in reverse so each step prepends; `arrays` is keyed by the same reversed paths.
    reversed =
      Enum.reduce(keys, [], fn key, path ->
        path = [key | path]

        case Map.fetch(arrays, path) do
          {:ok, index} -> [index | path]
          :error -> path
        end
      end)

    case kind do
      :table ->
        {Enum.reverse(reversed), arrays}

      :array_table ->
        # The header's own array entry is new, so drop the index of its previous entry.
        reversed = if is_integer(hd(reversed)), do: tl(reversed), else: reversed
        index = Map.get(arrays, reversed, -1) + 1
        {Enum.reverse([index | reversed]), Map.put(arrays, reversed, index)}
    end
  end

  @doc """
  Finds the key/value line that owns `path` and the rest of the path inside its value.

  Header and dotted key validation already happened during parsing, so at most one line's
  full key path can be a prefix of `path`.
  """
  @spec find_pair([{non_neg_integer, item, path, path | nil}], path) :: {:ok, non_neg_integer, path} | :error
  def find_pair(annotated, path) do
    Enum.find_value(annotated, :error, fn
      {index, {:pair, _keys, _key_raw, _value, _suffix}, _table, pair_path} ->
        case strip_prefix(path, pair_path) do
          {:ok, rest} -> {:ok, index, rest}
          :error -> nil
        end

      _item ->
        nil
    end)
  end

  @spec strip_prefix(path, path) :: {:ok, path} | :error
  def strip_prefix(rest, []), do: {:ok, rest}
  def strip_prefix([key | rest], [key | prefix]), do: strip_prefix(rest, prefix)
  def strip_prefix(_path, _prefix), do: :error

  @doc """
  Edits the value at `path` inside the key/value line that owns it. `leaf` gets the value
  node at `path` and returns its replacement, `:delete` to remove it, or `:error`.
  """
  @spec edit([item], path, (tuple -> tuple | :delete | :error)) :: {:ok, [item]} | :error
  def edit(items, path, leaf) do
    with {:ok, index, rest} <- items |> annotate() |> find_pair(path),
         {:pair, keys, key_raw, value, suffix} = Enum.at(items, index),
         {:ok, result} <- edit_value(value, rest, leaf) do
      case result do
        :delete -> {:ok, List.delete_at(items, index)}
        value -> {:ok, List.replace_at(items, index, {:pair, keys, key_raw, value, suffix})}
      end
    end
  end

  defp edit_value(value, [], leaf) do
    case leaf.(value) do
      :error -> :error
      result -> {:ok, result}
    end
  end

  defp edit_value(value, path, leaf) do
    edit_member(value, path, fn member, rest ->
      case edit_value(member_value(member), rest, leaf) do
        {:ok, :delete} -> {:ok, :delete}
        {:ok, child} -> {:ok, put_member_value(member, child)}
        :error -> :error
      end
    end)
  end

  # Finds the array element or inline table entry addressed by the head of `path` and
  # calls `fun` with it and the rest of the path below it.
  defp edit_member({kind, members, close}, path, fun) when kind in [:array, :inline_table] do
    with {:ok, index, rest} <- find_member(kind, members, path),
         {:ok, result} <- fun.(Enum.at(members, index), rest) do
      case result do
        :delete ->
          {members, close} = drop_member(members, index, close)
          {:ok, {kind, members, close}}

        member ->
          {:ok, {kind, List.replace_at(members, index, member), close}}
      end
    end
  end

  defp edit_member(_value, _path, _fun), do: :error

  defp find_member(:array, members, [index | rest]) when is_integer(index) and index >= 0 and index < length(members),
    do: {:ok, index, rest}

  defp find_member(:inline_table, members, path) do
    members
    |> Enum.with_index()
    |> Enum.find_value(:error, fn {{_before, keys, _key_raw, _value, _after}, index} ->
      case strip_prefix(path, keys) do
        {:ok, rest} -> {:ok, index, rest}
        :error -> nil
      end
    end)
  end

  defp find_member(_kind, _members, _path), do: :error

  defp member_value({_before, value, _after}), do: value
  defp member_value({_before, _keys, _key_raw, value, _after}), do: value

  defp put_member_value({before, _value, after_raw}, value), do: {before, value, after_raw}
  defp put_member_value({before, keys, key_raw, _value, after_raw}, value), do: {before, keys, key_raw, value, after_raw}

  # A removed member hands its surrounding whitespace to a neighbour so the remaining
  # members keep the collection's layout: the next member takes its leading whitespace,
  # or the previous member takes the whitespace before the closing bracket.
  defp drop_member([_only], 0, _close), do: {[], ""}

  defp drop_member(members, index, close) do
    removed = Enum.at(members, index)
    rest = List.delete_at(members, index)

    if index == length(rest) do
      after_raw = elem(removed, tuple_size(removed) - 1)
      {List.update_at(rest, index - 1, &put_elem(&1, tuple_size(&1) - 1, after_raw)), close}
    else
      {List.update_at(rest, index, &put_elem(&1, 0, elem(removed, 0))), close}
    end
  end

  @doc """
  Deletes a table made by dotted keys inside an inline table, like `a` in `{ a.b = 1 }`,
  by removing every entry below it from the enclosing inline table.
  """
  @spec delete_entries([item], path) :: {:ok, [item]} | :error
  def delete_entries(items, path), do: delete_entries(items, path, [])

  defp delete_entries(_items, [], _keys), do: :error

  defp delete_entries(items, path, keys) do
    {parent, [key]} = Enum.split(path, -1)
    keys = [key | keys]

    result =
      edit(items, parent, fn
        {:inline_table, members, close} -> drop_entries(members, keys, close)
        _value -> :error
      end)

    cond do
      result != :error -> result
      is_binary(key) -> delete_entries(items, parent, keys)
      true -> :error
    end
  end

  defp drop_entries(members, keys, close) do
    indexes =
      members
      |> Enum.with_index()
      |> Enum.filter(fn {{_before, member_keys, _key_raw, _value, _after}, _index} ->
        match?({:ok, [_ | _]}, strip_prefix(member_keys, keys))
      end)
      |> Enum.map(&elem(&1, 1))

    if indexes == [] do
      :error
    else
      # Dropping from the end keeps the remaining indexes valid.
      {members, close} =
        indexes |> Enum.reverse() |> Enum.reduce({members, close}, fn index, {m, c} -> drop_member(m, index, c) end)

      {:inline_table, members, close}
    end
  end

  @doc """
  Reports whether `items` still define the table at `path`: through a header at or below
  it, a key/value line below it, or a key/value line that owns it as a value.
  """
  @spec defines?([item], path) :: boolean
  def defines?(_items, []), do: true

  def defines?(items, path) do
    annotated = annotate(items)

    case find_pair(annotated, path) do
      {:ok, index, rest} ->
        {:pair, _keys, _key_raw, value, _suffix} = Enum.at(items, index)
        value_defines?(value, rest)

      :error ->
        defined_by_lines?(annotated, path)
    end
  end

  defp defined_by_lines?(annotated, path) do
    Enum.any?(annotated, fn
      {_index, {:header, _kind, _keys, _raw}, _table, header_path} ->
        match?({:ok, _rest}, strip_prefix(header_path, path))

      {_index, {:pair, _keys, _key_raw, _value, _suffix}, _table, pair_path} ->
        match?({:ok, [_ | _]}, strip_prefix(pair_path, path))

      _item ->
        false
    end)
  end

  defp value_defines?(_value, []), do: true

  defp value_defines?({:array, members, _close}, [index | rest]) when is_integer(index) do
    case Enum.fetch(members, index) do
      {:ok, {_before, value, _after}} -> value_defines?(value, rest)
      :error -> false
    end
  end

  defp value_defines?({:inline_table, members, _close}, path) do
    Enum.any?(members, fn {_before, keys, _key_raw, value, _after} ->
      case {strip_prefix(keys, path), strip_prefix(path, keys)} do
        {{:ok, [_ | _]}, _below} -> true
        {_above, {:ok, rest}} -> value_defines?(value, rest)
        _neither -> false
      end
    end)
  end

  defp value_defines?(_value, _path), do: false

  @doc """
  Deletes the table at `path` when headers or dotted keys define it: every section whose
  header is the table or below it, and every dotted key/value line below it.

  One blank line next to a removed section goes with it, preferring the one before, so
  the sections around it keep a single blank line between them. Comment lines stay, as
  when deleting a key.
  """
  @spec delete_table([item], path) :: {:ok, [item]} | :error
  def delete_table(items, path) do
    annotated = annotate(items)
    ends = section_ends(annotated)

    removed =
      annotated
      |> Enum.flat_map(fn
        {index, {:header, _kind, _keys, _raw}, _table, header_path} ->
          if match?({:ok, _rest}, strip_prefix(header_path, path)),
            do: section_indexes(items, index, Map.fetch!(ends, index)),
            else: []

        {index, {:pair, _keys, _key_raw, _value, _suffix}, _table, pair_path} ->
          if match?({:ok, [_ | _]}, strip_prefix(pair_path, path)), do: [index], else: []

        _item ->
          []
      end)
      |> MapSet.new()

    if MapSet.size(removed) == 0 do
      :error
    else
      {:ok, items |> Enum.with_index() |> Enum.reject(&MapSet.member?(removed, elem(&1, 1))) |> Enum.map(&elem(&1, 0))}
    end
  end

  # Maps each header's index to the index of the last key/value line in its section, or to
  # its own index. Trailing comments and blank lines usually introduce the next section,
  # so they are not part of it.
  defp section_ends(annotated) do
    {ends, _current} =
      Enum.reduce(annotated, {%{}, nil}, fn
        {index, {:header, _kind, _keys, _raw}, _table, _path}, {ends, _current} ->
          {Map.put(ends, index, index), index}

        {index, {:pair, _keys, _key_raw, _value, _suffix}, _table, _path}, {ends, current} when current != nil ->
          {Map.put(ends, current, index), current}

        _item, acc ->
          acc
      end)

    ends
  end

  defp section_indexes(items, first, last) do
    blank? = &blank_trivia?(Enum.at(items, &1))

    cond do
      first > 0 and blank?.(first - 1) -> Enum.to_list((first - 1)..last)
      # Comments above stay attached to whatever now follows, without a blank line between.
      blank?.(last + 1) -> Enum.to_list(first..(last + 1))
      true -> Enum.to_list(first..last)
    end
  end

  defp blank_trivia?({:trivia, raw}), do: String.trim(raw) == ""
  defp blank_trivia?(_item), do: false

  @doc """
  Appends `value` to an array node, or appends an entry at `keys` to an inline table node.
  """
  @spec append_member(tuple, [String.t()] | nil, tuple) :: tuple
  def append_member({:array, _members, _close} = array, nil, value), do: append(array, {"", value, ""})

  def append_member({:inline_table, _members, _close} = table, keys, value),
    do: append(table, {"", keys, encode_keys(keys) <> " = ", value, ""})

  # An empty collection's inner whitespace would otherwise end up after the new member.
  defp append({kind, [], _close}, member), do: {kind, [member], ""}

  # Comments after the last member stay with it, so the new member goes after them, with
  # the last member's line break and indentation. The text before the closing bracket
  # moves after the new member.
  defp append({kind, members, close}, member) do
    last = List.last(members)
    last_after = tuple_size(last) - 1

    {comment, member_after, last, close} =
      case close do
        "," <> rest ->
          {comment, tail} = split_comment(rest)
          {comment, "", last, "," <> tail}

        _close ->
          {comment, tail} = split_comment(elem(last, last_after))
          {comment, tail, put_elem(last, last_after, ""), close}
      end

    before = comment <> member_layout(members, elem(last, 0), comment)
    member = member |> put_elem(0, before) |> put_elem(tuple_size(member) - 1, member_after)
    {kind, members |> List.replace_at(-1, last) |> List.insert_at(-1, member), close}
  end

  # Splits whitespace after a member into the comment that ends its line, if any, and the
  # line break and indentation that follow.
  defp split_comment(text) do
    case :binary.matches(text, "\n") do
      [] ->
        {"", text}

      matches ->
        {index, 1} = List.last(matches)
        line = binary_part(text, 0, index)
        rest = binary_part(text, index + 1, byte_size(text) - index - 1)
        {line, newline} = if String.ends_with?(line, "\r"), do: {binary_slice(line, 0..-2//1), "\r\n"}, else: {line, "\n"}
        {if(String.trim(line) == "", do: "", else: line), newline <> rest}
    end
  end

  # Keeps only the line break and indentation of the last member's leading whitespace;
  # comments in it belong to the member they describe. After a comment, the new member
  # needs a line of its own.
  defp member_layout(members, before, comment) do
    layout =
      case {members, String.split(before, "\n")} do
        {[_only], [""]} -> " "
        {_members, [_single_line]} -> before
        {_members, lines} -> if(String.contains?(before, "\r\n"), do: "\r\n", else: "\n") <> List.last(lines)
      end

    if comment != "" and not String.contains?(layout, "\n"), do: "\n", else: layout
  end

  @spec encode_keys([String.t()]) :: binary
  def encode_keys(keys), do: keys |> Enum.map_intersperse(?., &Helpers.encode_key/1) |> IO.iodata_to_binary()
end
