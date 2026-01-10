defmodule TomlElixir.Parser.Builder do
  @moduledoc false

  alias TomlElixir.Parser.ArrayTable
  alias TomlElixir.Parser.Error
  alias TomlElixir.Parser.Table

  defstruct root: Table.new(), current: []

  @type t :: %__MODULE__{root: Table.t(), current: [String.t()]}

  @spec new() :: t
  def new, do: %__MODULE__{}

  @spec define_table(t, [String.t()]) :: t
  def define_table(%__MODULE__{} = builder, path) do
    root = ensure_table(builder.root, path, explicit: true)
    %{builder | root: root, current: path}
  end

  @spec define_array_table(t, [String.t()]) :: t
  def define_array_table(%__MODULE__{} = builder, path) do
    root = ensure_array_table(builder.root, path)
    %{builder | root: root, current: path}
  end

  @spec put_value(t, [String.t()], any) :: t
  def put_value(%__MODULE__{} = builder, path, value) do
    depth = length(builder.current)
    root = put_value_in(builder.root, builder.current ++ path, value, allow_inline?: false, protected_depth: depth)
    %{builder | root: root}
  end

  @spec inline_table() :: Table.t()
  def inline_table do
    Table.new(inline?: true, explicit?: true)
  end

  @spec put_inline_value(Table.t(), [String.t()], any) :: Table.t()
  def put_inline_value(%Table{} = table, path, value) do
    put_value_in(table, path, value, allow_inline?: true)
  end

  @spec to_map(t) :: map
  def to_map(%__MODULE__{root: root}) do
    Table.to_map(root)
  end

  defp ensure_table(%Table{} = table, [], _opts), do: table

  defp ensure_table(%Table{} = table, [key], explicit: explicit?) do
    assert_mutable!(table, false)

    case Map.fetch(table.data, key) do
      :error ->
        new_table = Table.new(explicit?: explicit?)
        %{table | data: Map.put(table.data, key, new_table)}

      {:ok, %Table{} = existing} ->
        assert_not_inline!(existing)

        if existing.dotted? do
          Error.raise("Table #{Enum.join([key], ".")} already defined")
        end

        if explicit? and existing.explicit? do
          Error.raise("Duplicate table #{Enum.join([key], ".")}")
        else
          updated = %{existing | explicit?: existing.explicit? || explicit?}
          %{table | data: Map.put(table.data, key, updated)}
        end

      {:ok, %ArrayTable{}} ->
        Error.raise("Table #{Enum.join([key], ".")} already defined as array")

      {:ok, _value} ->
        Error.raise("Table #{Enum.join([key], ".")} conflicts with existing value")
    end
  end

  defp ensure_table(%Table{} = table, [key | tail], opts) do
    assert_mutable!(table, false)

    case Map.fetch(table.data, key) do
      :error ->
        child = Table.new()
        updated_child = ensure_table(child, tail, opts)
        %{table | data: Map.put(table.data, key, updated_child)}

      {:ok, %Table{} = existing} ->
        assert_not_inline!(existing)
        updated_child = ensure_table(existing, tail, opts)
        %{table | data: Map.put(table.data, key, updated_child)}

      {:ok, %ArrayTable{} = array_table} ->
        ensure_table_in_array(table, key, array_table, tail, opts)

      {:ok, _value} ->
        Error.raise("Key #{Enum.join([key | tail], ".")} is not a table")
    end
  end

  defp ensure_table_in_array(%Table{} = table, key, %ArrayTable{items: items}, tail, opts) do
    case List.last(items) do
      nil ->
        Error.raise("Array of tables #{key} is empty")

      %Table{} = last ->
        assert_not_inline!(last)
        updated_last = ensure_table(last, tail, opts)
        updated_items = List.update_at(items, -1, fn _ -> updated_last end)
        %{table | data: Map.put(table.data, key, %ArrayTable{items: updated_items})}
    end
  end

  defp ensure_array_table(table, keys, opts \\ [])
  defp ensure_array_table(%Table{} = table, [], _opts), do: table

  defp ensure_array_table(%Table{} = table, [key], _opts) do
    assert_mutable!(table, false)

    case Map.fetch(table.data, key) do
      :error ->
        new_table = Table.new(explicit?: true)
        %{table | data: Map.put(table.data, key, %ArrayTable{items: [new_table]})}

      {:ok, %ArrayTable{items: items}} ->
        new_table = Table.new(explicit?: true)
        %{table | data: Map.put(table.data, key, %ArrayTable{items: items ++ [new_table]})}

      {:ok, %Table{}} ->
        Error.raise("Table #{key} already defined")

      {:ok, _value} ->
        Error.raise("Table #{key} conflicts with existing value")
    end
  end

  defp ensure_array_table(%Table{} = table, [key | tail], opts) do
    assert_mutable!(table, false)

    case Map.fetch(table.data, key) do
      :error ->
        child = Table.new()
        updated_child = ensure_array_table(child, tail, opts)
        %{table | data: Map.put(table.data, key, updated_child)}

      {:ok, %Table{} = existing} ->
        assert_not_inline!(existing)
        updated_child = ensure_array_table(existing, tail, opts)
        %{table | data: Map.put(table.data, key, updated_child)}

      {:ok, %ArrayTable{items: items}} ->
        case List.last(items) do
          nil ->
            Error.raise("Array of tables #{key} is empty")

          %Table{} = last ->
            assert_not_inline!(last)
            updated_last = ensure_array_table(last, tail, opts)
            updated_items = List.update_at(items, -1, fn _ -> updated_last end)
            %{table | data: Map.put(table.data, key, %ArrayTable{items: updated_items})}
        end

      {:ok, _value} ->
        Error.raise("Key #{Enum.join([key | tail], ".")} is not a table")
    end
  end

  defp put_value_in(%Table{} = table, [], _value, _opts) do
    table
  end

  defp put_value_in(%Table{} = table, [key], value, opts) do
    assert_mutable!(table, opts[:allow_inline?])

    if Map.has_key?(table.data, key) do
      Error.raise("Duplicate key #{key}")
    else
      %{table | data: Map.put(table.data, key, value)}
    end
  end

  defp put_value_in(%Table{} = table, [key | tail], value, opts) do
    assert_mutable!(table, opts[:allow_inline?])

    depth = Keyword.get(opts, :protected_depth, 0)
    opts = Keyword.put(opts, :protected_depth, depth - 1)

    case Map.fetch(table.data, key) do
      :error ->
        child = Table.new(inline?: opts[:allow_inline?], dotted?: not opts[:allow_inline?])
        updated_child = put_value_in(child, tail, value, opts)
        %{table | data: Map.put(table.data, key, updated_child)}

      {:ok, %Table{} = existing} ->
        assert_mutable!(existing, opts[:allow_inline?])

        if not opts[:allow_inline?] and depth <= 0 and existing.explicit? do
          Error.raise("Table #{Enum.join([key], ".")} cannot be modified via dotted keys")
        end

        updated_child = put_value_in(existing, tail, value, opts)
        %{table | data: Map.put(table.data, key, updated_child)}

      {:ok, %ArrayTable{items: items}} ->
        if depth <= 0 do
          Error.raise("Table #{Enum.join([key], ".")} already defined as array")
        end

        case List.last(items) do
          nil ->
            Error.raise("Array of tables #{key} is empty")

          %Table{} = last ->
            assert_mutable!(last, opts[:allow_inline?])
            updated_last = put_value_in(last, tail, value, opts)
            updated_items = List.update_at(items, -1, fn _ -> updated_last end)
            %{table | data: Map.put(table.data, key, %ArrayTable{items: updated_items})}
        end

      {:ok, _value} ->
        Error.raise("Key #{Enum.join([key | tail], ".")} is not a table")
    end
  end

  defp assert_mutable!(%Table{frozen?: true}, _allow_inline) do
    Error.raise("Cannot modify frozen table")
  end

  defp assert_mutable!(%Table{inline?: true}, false) do
    Error.raise("Inline table cannot be modified")
  end

  defp assert_mutable!(%Table{}, _allow_inline), do: :ok

  defp assert_not_inline!(%Table{inline?: true}) do
    Error.raise("Inline table cannot be re-opened")
  end

  defp assert_not_inline!(%Table{}), do: :ok
end
