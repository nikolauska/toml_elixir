defmodule TomlElixir.Document.Insert do
  @moduledoc false

  # Places new keys, tables, array elements, and array of tables entries in a document's
  # items. New text comes from the regular encoder, so it matches `TomlElixir.encode/2`.
  #
  # Placement rules:
  #
  #   * A key in an existing header or root table goes after the table's last key/value line,
  #     with that line's indentation.
  #   * A key in a table defined by dotted keys becomes another dotted key after its siblings.
  #   * A key in an inline table becomes a new entry; an array element is appended.
  #   * New tables and array of tables entries go after the last section belonging to the
  #     nearest existing parent table, or at the end of the document.
  #
  # New lines are inserted before trailing comments and blank lines, which usually
  # introduce whatever comes next.

  alias TomlElixir.Document.Items
  alias TomlElixir.Document.Parser
  alias TomlElixir.Encoder.Helpers
  alias TomlElixir.Encoder.Serializer

  @spec encode_inline(term, atom) :: {:ok, tuple} | {:error, String.t()}
  def encode_inline(value, spec) do
    {:ok, value |> Helpers.encode_value() |> IO.iodata_to_binary() |> Parser.parse_value(spec)}
  rescue
    exception -> {:error, Exception.message(exception)}
  end

  @doc """
  Inserts `value` at `path`, which must not exist in `data`. Returns the new items or the
  reason the value cannot be placed.
  """
  @spec insert([tuple], map, Items.path(), term, atom, binary) :: {:ok, [tuple]} | {:error, String.t()}
  def insert(items, data, path, value, spec, newline) do
    {parent_path, rest, parent} = existing_prefix(data, path, [])
    context = %{items: items, annotated: Items.annotate(items), spec: spec, newline: newline}

    cond do
      is_list(parent) -> insert_element(context, parent_path, length(parent), rest, value)
      is_map(parent) and not is_struct(parent) -> insert_key(context, parent_path, rest, value)
      true -> {:error, "parent is not a table or array"}
    end
  end

  # The deepest existing value on `path` is the container the new value goes into.
  defp existing_prefix(value, [key | rest] = path, acc) do
    case child(value, key) do
      {:ok, child} -> existing_prefix(child, rest, [key | acc])
      :error -> {Enum.reverse(acc), path, value}
    end
  end

  defp child(map, key) when is_map(map) and not is_struct(map), do: Map.fetch(map, key)
  defp child(list, index) when is_list(list) and is_integer(index) and index >= 0, do: Enum.fetch(list, index)
  defp child(_value, _key), do: :error

  defp insert_element(context, array_path, size, [size | keys], value) do
    with {:ok, element} <- nest(keys, value) do
      case Items.find_pair(context.annotated, array_path) do
        {:ok, _index, _rest} -> append_inline(context, array_path, nil, element)
        :error -> insert_array_table_entry(context, array_path, element)
      end
    end
  end

  defp insert_element(_context, _array_path, size, _rest, _value),
    do: {:error, "arrays can only grow by appending at index #{size}"}

  defp insert_key(context, table_path, keys, value) do
    with {:ok, _value} <- nest(keys, value) do
      cond do
        match?({:ok, _index, _rest}, Items.find_pair(context.annotated, table_path)) ->
          append_inline(context, table_path, keys, value)

        table_path == [] or header_index(context.annotated, table_path) ->
          insert_into_section(context, table_path, keys, value)

        dotted = last_dotted_pair(context.annotated, table_path) ->
          insert_dotted(context, table_path, dotted, keys, value)

        true ->
          # Only subtables define this table so far, so it gets its own header.
          insert_block(context, table_path, :table, nest!(keys, value))
      end
    end
  end

  defp nest(keys, value) do
    if Enum.all?(keys, &is_binary/1) do
      {:ok, nest!(keys, value)}
    else
      {:error, "only the next index of an existing array can be added"}
    end
  end

  defp nest!(keys, value), do: List.foldr(keys, value, &%{&1 => &2})

  defp append_inline(context, path, keys, value) do
    with {:ok, node} <- encode_inline(value, context.spec) do
      append_inline_node(context, path, keys, node)
    end
  end

  # A table made by dotted keys inside an inline table, like `a` in `{ a.b = 1 }`, has no
  # node of its own, so the entry goes into the enclosing inline table as a dotted key.
  defp append_inline_node(context, path, keys, node) do
    case Items.edit(context.items, path, &Items.append_member(&1, keys, node)) do
      {:ok, items} ->
        {:ok, items}

      :error when is_list(keys) and path != [] ->
        {parent, [key]} = Enum.split(path, -1)
        if is_binary(key), do: append_inline_node(context, parent, [key | keys], node), else: placement_error()

      :error ->
        placement_error()
    end
  end

  defp placement_error, do: {:error, "value cannot be placed"}

  defp insert_array_table_entry(context, array_path, element) do
    if is_map(element) do
      insert_block(context, array_path, :array_table, element)
    else
      {:error, "arrays of tables can only hold tables"}
    end
  end

  defp insert_dotted(context, table_path, {index, {:pair, _keys, key_raw, _value, _suffix}, section, _path}, keys, value) do
    with {:ok, node} <- encode_inline(value, context.spec) do
      dotted_keys = Enum.drop(table_path, length(section)) ++ keys
      pair = {:pair, dotted_keys, indent(key_raw) <> Items.encode_keys(dotted_keys) <> " = ", node, context.newline}
      {:ok, insert_at(context, index + 1, [pair])}
    end
  end

  # Scalars go into the table's own section; generated subtables go after every section
  # that belongs to the table. The later position is filled first so the earlier index
  # still points at the same item.
  defp insert_into_section(context, table_path, keys, value) do
    with {:ok, pairs, sections} <- generate(context, table_path, nest!(keys, value)) do
      {anchor, indent} = section_anchor(context.annotated, table_path)
      pairs = Enum.map(pairs, fn {:pair, k, key_raw, v, suffix} -> {:pair, k, indent <> key_raw, v, suffix} end)
      pairs = separate_from_header(context.items, anchor + 1, pairs, context.newline)
      position = block_position(context.annotated, table_path)
      items = insert_at(context, position, separate(position, sections, context.newline))
      {:ok, insert_at(%{context | items: items}, anchor + 1, pairs)}
    end
  end

  # Writes a header for `table_path` itself, followed by the generated content.
  defp insert_block(context, table_path, kind, map) do
    with {:ok, pairs, sections} <- generate(context, table_path, map) do
      header = header(kind, header_keys(table_path), context.newline)
      position = block_position(context.annotated, table_path)

      body =
        if pairs != [] and sections != [],
          do: Enum.concat([pairs, [{:trivia, context.newline}], sections]),
          else: pairs ++ sections

      {:ok, insert_at(context, position, separate(position, [header | body], context.newline))}
    end
  end

  # Encodes `map` as a document and moves its headers below `table_path`. Returns the
  # key/value lines before the first header and everything from the first header on.
  defp generate(context, table_path, map) do
    case Serializer.encode_to_iodata(map) do
      {:ok, iodata} ->
        text = iodata |> IO.iodata_to_binary() |> String.replace("\n", context.newline)
        {leading, sections} = text |> Parser.parse(context.spec) |> Enum.split_while(&(elem(&1, 0) != :header))
        pairs = Enum.filter(leading, &(elem(&1, 0) == :pair))
        prefix = header_keys(table_path)

        sections =
          sections
          |> drop_empty_parents()
          |> Enum.map(fn
            {:header, kind, keys, _raw} -> header(kind, prefix ++ keys, context.newline)
            item -> item
          end)

        {:ok, pairs, sections}

      {:error, exception} ->
        {:error, exception.reason}
    end
  end

  # The encoder writes a header for every table, so `%{"a" => %{"b" => %{"c" => 1}}}`
  # starts with empty `[a]` and `[a.b]` sections. `[a.b.c]` defines them implicitly, and
  # leaving them out matches how such tables are usually written by hand.
  defp drop_empty_parents([{:header, :table, keys, _raw} | rest] = items) do
    case Enum.drop_while(rest, &(elem(&1, 0) == :trivia)) do
      [{:header, _kind, child_keys, _raw} | _] = next ->
        if match?({:ok, [_ | _]}, Items.strip_prefix(child_keys, keys)),
          do: drop_empty_parents(next),
          else: keep_and_continue(items)

      _other ->
        keep_and_continue(items)
    end
  end

  defp drop_empty_parents([_item | _rest] = items), do: keep_and_continue(items)
  defp drop_empty_parents([]), do: []

  defp keep_and_continue([item | rest]), do: [item | drop_empty_parents(rest)]

  # New sections go after the sections of the nearest table that has any, so a header is
  # never placed above key/value lines that belong to an earlier table.
  defp block_position(annotated, table_path) do
    case section_end(annotated, table_path) do
      -1 when table_path != [] -> block_position(annotated, Enum.drop(table_path, -1))
      last -> last + 1
    end
  end

  defp header(kind, keys, newline) do
    {open, close} = if kind == :array_table, do: {"[[", "]]"}, else: {"[", "]"}
    {:header, kind, keys, open <> Items.encode_keys(keys) <> close <> newline}
  end

  # Array indexes resolve implicitly in headers, through the latest entry.
  defp header_keys(path), do: Enum.filter(path, &is_binary/1)

  # A blank line keeps new sections apart from whatever precedes them.
  defp separate(_position, [], _newline), do: []
  defp separate(0, items, _newline), do: items
  defp separate(_position, items, newline), do: [{:trivia, newline} | items]

  # Root keys added above the first header get a blank line before that header.
  defp separate_from_header(items, position, [_ | _] = pairs, newline) do
    case Enum.at(items, position) do
      {:header, _kind, _keys, _raw} -> List.insert_at(pairs, -1, {:trivia, newline})
      _item -> pairs
    end
  end

  defp separate_from_header(_items, _position, pairs, _newline), do: pairs

  defp header_index(annotated, table_path) do
    Enum.find_value(annotated, fn
      {index, {:header, _kind, _keys, _raw}, _table, ^table_path} -> index
      _item -> nil
    end)
  end

  defp last_dotted_pair(annotated, table_path) do
    annotated
    |> Enum.filter(fn
      {_index, {:pair, _keys, _key_raw, _value, _suffix}, section, pair_path} ->
        length(section) < length(table_path) and match?({:ok, [_ | _]}, Items.strip_prefix(pair_path, table_path))

      _item ->
        false
    end)
    |> List.last()
  end

  # Returns the index to insert key/value lines after, and the indentation of the last
  # key/value line in the table's own section. Without key/value lines, new lines go
  # right after the header, or for the root table after leading comments.
  defp section_anchor(annotated, table_path) do
    own_pairs =
      Enum.filter(annotated, fn
        {_index, {:pair, _keys, _key_raw, _value, _suffix}, ^table_path, _path} -> true
        _item -> false
      end)

    case {List.last(own_pairs), table_path, annotated} do
      {{index, {:pair, _keys, key_raw, _value, _suffix}, _table, _path}, _table_path, _annotated} ->
        {index, indent(key_raw)}

      {nil, [], [{0, {:trivia, _raw}, _table, _path} | _rest]} ->
        {0, ""}

      {nil, [], _annotated} ->
        {-1, ""}

      {nil, _table_path, _annotated} ->
        {header_index(annotated, table_path), ""}
    end
  end

  # Returns the index of the last key/value line or header in any section that belongs to
  # `table_path`, or -1 when there is none.
  defp section_end(annotated, table_path) do
    {last, _inside?} =
      Enum.reduce(annotated, {-1, table_path == []}, fn
        {index, {:header, _kind, _keys, _raw}, _table, path}, {last, _inside?} ->
          inside? = match?({:ok, _rest}, Items.strip_prefix(path, table_path))
          {if(inside?, do: index, else: last), inside?}

        {index, {:pair, _keys, _key_raw, _value, _suffix}, _table, _path}, {_last, true} ->
          {index, true}

        _item, acc ->
          acc
      end)

    last
  end

  defp indent(key_raw) do
    [indent | _rest] = String.split(key_raw, ~r/[^ \t]/, parts: 2)
    indent
  end

  defp insert_at(context, _position, []), do: context.items

  defp insert_at(context, position, new_items) do
    # The document's last line may have no line ending; anything inserted after it needs one.
    items =
      if position > 0,
        do: List.update_at(context.items, position - 1, &terminate(&1, context.newline)),
        else: context.items

    {before, after_items} = Enum.split(items, position)
    before ++ new_items ++ after_items
  end

  defp terminate(item, newline) do
    rendered = [item] |> Items.render() |> IO.iodata_to_binary()

    cond do
      String.ends_with?(rendered, "\n") -> item
      elem(item, 0) == :pair -> put_elem(item, 4, elem(item, 4) <> newline)
      elem(item, 0) == :header -> put_elem(item, 3, elem(item, 3) <> newline)
      true -> {:trivia, elem(item, 1) <> newline}
    end
  end
end
