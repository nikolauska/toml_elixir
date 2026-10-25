defmodule TomlElixir.Document.Edit do
  @moduledoc false

  # Runs `TomlElixir.Document.put/3` and `delete/2` as a series of item edits.
  #
  # Replacing a table or an array of tables diffs old and new content: unchanged values
  # keep their text, changed values are replaced, removed keys are deleted, and new keys
  # are inserted. A table replacement therefore keeps the comments and formatting of every
  # key it does not change.
  #
  # Each step keeps `data` in step with `items` so later steps resolve paths against the
  # edited document. The caller re-decodes the result once at the end, which both validates
  # it and replaces `data` with exactly decoded values.

  alias TomlElixir.Document.Error
  alias TomlElixir.Document.Insert
  alias TomlElixir.Document.Items
  alias TomlElixir.Encoder.Helpers
  alias TomlElixir.Encoder.Serializer

  @enforce_keys [:items, :data, :spec, :newline]
  defstruct [:items, :data, :spec, :newline]

  @type t :: %__MODULE__{items: [tuple], data: map, spec: atom, newline: binary}

  @spec fetch(term, Items.path()) :: {:ok, term} | :error
  def fetch(value, []), do: {:ok, value}

  def fetch(map, [key | rest]) when is_map(map) and not is_struct(map) do
    case Map.fetch(map, key) do
      {:ok, value} -> fetch(value, rest)
      :error -> :error
    end
  end

  def fetch(list, [index | rest]) when is_list(list) and is_integer(index) and index >= 0 do
    case Enum.fetch(list, index) do
      {:ok, value} -> fetch(value, rest)
      :error -> :error
    end
  end

  def fetch(_value, _path), do: :error

  @spec put(t, Items.path(), term) :: {:ok, t} | {:error, Error.t()}
  def put(%__MODULE__{} = state, path, value) do
    case fetch(state.data, path) do
      {:ok, old} -> set(state, path, old, value)
      :error -> insert(state, path, value)
    end
  end

  @spec delete(t, Items.path()) :: {:ok, t} | {:error, Error.t()}
  def delete(%__MODULE__{} = state, path) do
    case fetch(state.data, path) do
      {:ok, _old} -> remove(state, path)
      :error -> {:ok, state}
    end
  end

  # An equal value leaves the text alone, so putting back what was read keeps formats such
  # as hex integers or literal strings.
  defp set(state, _path, old, old), do: {:ok, state}

  defp set(state, path, old, new) do
    cond do
      table?(old) and Serializer.map_like?(new) -> replace_table(state, path, old, new)
      array_of_tables?(state, path, old) and Serializer.array_of_maps?(new) -> replace_entries(state, path, old, new)
      true -> replace_value(state, path, new)
    end
  end

  defp table?(value), do: is_map(value) and not is_struct(value)

  # A list that no key/value line owns can only come from `[[...]]` headers.
  defp array_of_tables?(state, path, old) do
    is_list(old) and state.items |> Items.annotate() |> Items.find_pair(path) == :error
  end

  defp replace_table(state, path, old, new) do
    pairs = new |> Serializer.project() |> Helpers.sorted_pairs()
    new_keys = MapSet.new(pairs, &elem(&1, 0))
    removed = old |> Map.keys() |> Enum.reject(&MapSet.member?(new_keys, &1)) |> Enum.sort()

    with {:ok, state} <- reduce_ok(removed, state, &remove(&2, child(path, &1))) do
      reduce_ok(pairs, state, fn {key, value}, state ->
        case Map.fetch(old, key) do
          {:ok, old_value} -> set(state, child(path, key), old_value, value)
          :error -> insert(state, child(path, key), value)
        end
      end)
    end
  end

  # Entries are matched by index. Extra old entries are deleted from the end so the
  # indexes of earlier entries stay valid; extra new entries are appended in order.
  defp replace_entries(state, path, old, new) do
    common = min(length(old), length(new))
    shared = old |> Enum.zip(new) |> Enum.with_index()
    extra_old = if length(old) > common, do: Enum.to_list((length(old) - 1)..common//-1), else: []
    extra_new = new |> Enum.drop(common) |> Enum.with_index(common)

    with {:ok, state} <-
           reduce_ok(shared, state, fn {{old, new}, index}, state -> set(state, child(path, index), old, new) end),
         {:ok, state} <- reduce_ok(extra_old, state, &remove(&2, child(path, &1))) do
      reduce_ok(extra_new, state, fn {value, index}, state -> insert(state, child(path, index), value) end)
    end
  end

  # A key/value line, array element, or inline table entry is replaced in place. A table
  # or array of tables defined by headers becomes the new value, written as a new key.
  defp replace_value(state, path, value) do
    with {:ok, node} <- wrap(Insert.encode_inline(value, state.spec), path) do
      case Items.edit(state.items, path, fn _old -> node end) do
        {:ok, items} ->
          {:ok, %{state | items: items, data: put_data(state.data, path, value)}}

        :error ->
          with {:ok, state} <- remove(state, path), do: insert(state, path, value)
      end
    end
  end

  defp insert(state, path, value) do
    with {:ok, items} <- wrap(Insert.insert(state.items, state.data, path, value, state.spec, state.newline), path) do
      {:ok, %{state | items: items, data: put_data(state.data, path, value)}}
    end
  end

  defp remove(state, path) do
    result =
      with :error <- Items.edit(state.items, path, fn _old -> :delete end),
           :error <- Items.delete_table(state.items, path) do
        Items.delete_entries(state.items, path)
      end

    case result do
      {:ok, items} -> keep_parent(%{state | items: items, data: delete_data(state.data, path)}, Enum.drop(path, -1))
      :error -> {:error, %Error{reason: "value cannot be deleted", path: path}}
    end
  end

  # A table defined only by what was just deleted, like `a` in `[a.b]`, would vanish with
  # it. Deleting a key should not delete its parent, so the parent is written again as an
  # empty value of the same kind: `[a]` for a table, `a = []` for an array of tables that
  # lost its last entry. It is placed by the usual insertion rules.
  defp keep_parent(state, parent) do
    if Items.defines?(state.items, parent) do
      {:ok, state}
    else
      {:ok, old} = fetch(state.data, parent)
      empty = if is_list(old), do: [], else: %{}
      insert(%{state | data: delete_data(state.data, parent)}, parent, empty)
    end
  end

  defp child(path, key), do: List.insert_at(path, -1, key)

  defp wrap({:ok, _value} = ok, _path), do: ok
  defp wrap({:error, reason}, path), do: {:error, %Error{reason: reason, path: path}}

  defp reduce_ok(enumerable, state, fun) do
    Enum.reduce_while(enumerable, {:ok, state}, fn element, {:ok, state} ->
      case fun.(element, state) do
        {:ok, state} -> {:cont, {:ok, state}}
        error -> {:halt, error}
      end
    end)
  end

  # Values are stored as given; only their shape matters until the final re-decode.
  defp put_data(_data, [], value), do: value

  defp put_data(map, [key | rest], value) when is_map(map),
    do: Map.put(map, key, put_data(Map.get(map, key), rest, value))

  defp put_data(list, [index | rest], value) when is_list(list) and index == length(list),
    do: List.insert_at(list, -1, put_data(nil, rest, value))

  defp put_data(list, [index | rest], value) when is_list(list),
    do: List.update_at(list, index, &put_data(&1, rest, value))

  defp put_data(nil, [key | rest], value), do: %{key => put_data(nil, rest, value)}

  defp delete_data(map, [key]) when is_map(map), do: Map.delete(map, key)
  defp delete_data(list, [index]) when is_list(list), do: List.delete_at(list, index)
  defp delete_data(map, [key | rest]) when is_map(map), do: Map.update!(map, key, &delete_data(&1, rest))
  defp delete_data(list, [index | rest]) when is_list(list), do: List.update_at(list, index, &delete_data(&1, rest))
end
