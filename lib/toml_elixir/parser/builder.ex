defmodule TomlElixir.Parser.Builder do
  @moduledoc false

  alias TomlElixir.Parser.ArrayTable
  alias TomlElixir.Parser.Error
  alias TomlElixir.Parser.Table

  # `table` is the table addressed by the latest header, detached from `root`. Key/value
  # lines only touch it, so they avoid rewriting every map from the root on each insert;
  # `root` has a stale copy at `current` until `close/1` writes `table` back.
  defstruct root: nil, current: [], table: Table.new()

  @type t :: %__MODULE__{root: Table.t() | nil, current: [String.t()], table: Table.t()}

  @spec new() :: t
  def new, do: %__MODULE__{}

  @spec define_table(t, [String.t()]) :: t
  def define_table(%__MODULE__{} = builder, path) do
    root = builder |> close() |> ensure_table(path, explicit: true)
    %{builder | root: root, current: path, table: fetch_table(root, path)}
  end

  @spec define_array_table(t, [String.t()]) :: t
  def define_array_table(%__MODULE__{} = builder, path) do
    root = builder |> close() |> ensure_array_table(path)
    %{builder | root: root, current: path, table: fetch_table(root, path)}
  end

  @spec put_value(t, [String.t()], any) :: t
  def put_value(%__MODULE__{} = builder, path, value) do
    # Header segments were validated when the header was defined, so only the dotted
    # key segments below the open table need checking.
    %{builder | table: put_value_in(builder.table, path, value, false)}
  end

  @spec inline_table() :: Table.t()
  def inline_table do
    Table.new(true, true)
  end

  @spec put_inline_value(Table.t(), [String.t()], any) :: Table.t()
  def put_inline_value(%Table{} = table, path, value) do
    put_value_in(table, path, value, true)
  end

  @spec to_map(t) :: map
  def to_map(%__MODULE__{} = builder) do
    builder |> close() |> Table.to_map()
  end

  defp close(%__MODULE__{root: nil, table: table}), do: table
  defp close(%__MODULE__{root: root, current: path, table: table}), do: replace_table(root, path, table)

  # Headers resolve through the most recent entry of an array of tables, matching
  # the navigation used by `ensure_table/3` and `ensure_array_table/3`.
  defp fetch_table(%Table{} = table, []), do: table

  defp fetch_table(%Table{data: data}, [key | tail]) do
    case Map.fetch!(data, key) do
      %Table{} = child -> fetch_table(child, tail)
      %ArrayTable{items: [last | _]} -> fetch_table(last, tail)
    end
  end

  defp replace_table(%Table{}, [], table), do: table

  defp replace_table(%Table{data: data} = parent, [key | tail], table) do
    child =
      case Map.fetch!(data, key) do
        %Table{} = child -> replace_table(child, tail, table)
        %ArrayTable{items: [last | rest]} -> %ArrayTable{items: [replace_table(last, tail, table) | rest]}
      end

    %{parent | data: Map.put(data, key, child)}
  end

  defp ensure_table(%Table{} = table, [], _opts), do: table

  defp ensure_table(%Table{} = table, [key], explicit: explicit?) do
    assert_mutable!(table, false)

    case Map.fetch(table.data, key) do
      :error ->
        new_table = Table.new(false, explicit?)
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
    case items do
      [] ->
        Error.raise("Array of tables #{key} is empty")

      [%Table{} = last | rest] ->
        assert_not_inline!(last)
        updated_last = ensure_table(last, tail, opts)
        updated_items = [updated_last | rest]
        %{table | data: Map.put(table.data, key, %ArrayTable{items: updated_items})}
    end
  end

  defp ensure_array_table(table, keys, opts \\ [])
  defp ensure_array_table(%Table{} = table, [], _opts), do: table

  defp ensure_array_table(%Table{} = table, [key], _opts) do
    assert_mutable!(table, false)

    case Map.fetch(table.data, key) do
      :error ->
        new_table = Table.new(false, true)
        %{table | data: Map.put(table.data, key, %ArrayTable{items: [new_table]})}

      {:ok, %ArrayTable{items: items}} ->
        new_table = Table.new(false, true)
        %{table | data: Map.put(table.data, key, %ArrayTable{items: [new_table | items]})}

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
        case items do
          [] ->
            Error.raise("Array of tables #{key} is empty")

          [%Table{} = last | rest] ->
            assert_not_inline!(last)
            updated_last = ensure_array_table(last, tail, opts)
            updated_items = [updated_last | rest]
            %{table | data: Map.put(table.data, key, %ArrayTable{items: updated_items})}
        end

      {:ok, _value} ->
        Error.raise("Key #{Enum.join([key | tail], ".")} is not a table")
    end
  end

  defp put_value_in(%Table{} = table, [], _value, _allow_inline?) do
    table
  end

  defp put_value_in(%Table{} = table, [key], value, allow_inline?) do
    assert_mutable!(table, allow_inline?)

    if Map.has_key?(table.data, key) do
      Error.raise("Duplicate key #{key}")
    else
      %{table | data: Map.put(table.data, key, value)}
    end
  end

  # Every segment handled here is a dotted key segment: callers start at the open header
  # table or at an inline table, never above it.
  defp put_value_in(%Table{} = table, [key | tail], value, allow_inline?) do
    assert_mutable!(table, allow_inline?)

    case Map.fetch(table.data, key) do
      :error ->
        child = Table.new(allow_inline?, false, not allow_inline?)
        updated_child = put_value_in(child, tail, value, allow_inline?)
        %{table | data: Map.put(table.data, key, updated_child)}

      {:ok, %Table{} = existing} ->
        assert_mutable!(existing, allow_inline?)

        if not allow_inline? and existing.explicit? do
          Error.raise("Table #{key} cannot be modified via dotted keys")
        end

        updated_child = put_value_in(existing, tail, value, allow_inline?)
        %{table | data: Map.put(table.data, key, updated_child)}

      {:ok, %ArrayTable{}} ->
        Error.raise("Table #{key} already defined as array")

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
