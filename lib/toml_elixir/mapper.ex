defmodule TomlElixir.Mapper do
  @moduledoc """
  Transform toml list to map format
  """

  @spec to_map(list) :: map
  def to_map([]), do: %{}
  def to_map(toml), do: to_map(toml, {[], %{}})
  def to_map([], {_to, acc}), do: acc
  def to_map([{:table, to} | _tail], {to, _acc}) do
    throw "Error: duplicate table #{Enum.join(to, ".")}"
  end
  def to_map([{:table, to} | []], {_to, acc}) do
    do_put_in(to, nil, %{}, acc)
  end
  def to_map([{:table, to} | tail], {_to, acc}) do
    to_map(tail, {to, acc})
  end
  def to_map([{:array_table, to} | tail], {_to, acc}) do
    to_map(tail, {to, do_put_in_new(to, acc)})
  end
  def to_map([{{:key, key}, {:array, val}} | tail], {to, acc}) do
    to_map(tail, {to, do_put_in(to, key, val, acc)})
  end
  def to_map([{{:key, key}, {:datetime, val}} | tail], {to, acc}) do
    to_map(tail, {to, do_put_in(to, key, val, acc)})
  end
  def to_map([{{:key, key}, {:date, val}} | tail], {to, acc}) do
    to_map(tail, {to, do_put_in(to, key, val, acc)})
  end
  def to_map([{{:key, key}, {:time, val}} | tail], {to, acc}) do
    to_map(tail, {to, do_put_in(to, key, val, acc)})
  end
  def to_map([{{:key, key}, {:string, val}} | tail], {to, acc}) do
    to_map(tail, {to, do_put_in(to, key, val, acc)})
  end
  def to_map([{{:key, key}, {:string_ml, val}} | tail], {to, acc}) do
    to_map(tail, {to, do_put_in(to, key, val, acc)})
  end
  def to_map([{{:key, key}, {:literal, val}} | tail], {to, acc}) do
    to_map(tail, {to, do_put_in(to, key, val, acc)})
  end
  def to_map([{{:key, key}, {:literal_ml, val}} | tail], {to, acc}) do
    to_map(tail, {to, do_put_in(to, key, val, acc)})
  end
  def to_map([{{:key, key}, val} | tail], {to, acc}) do
    to_map(tail, {to, do_put_in(to, key, val, acc)})
  end

  defp do_put_in([], key, val, []) do
    [Map.put(%{}, key, val)]
  end
  defp do_put_in([], key, val, acc) when is_list(acc) do
    List.update_at(acc, -1, &Map.put(&1, key, val))
  end
  defp do_put_in([], key, val, acc) when is_map(acc) do
    if Map.has_key?(acc, key) do
      throw "Error: duplicate key #{key}"
    else
      Map.put(acc, key, val)
    end
  end
  defp do_put_in([key], nil, val, acc) when is_map(acc) do
    Map.put(acc, key, val)
  end
  defp do_put_in(to, key, val, acc) when is_list(acc) do
    List.update_at(acc, -1, &do_put_in(to, key, val, &1))
  end
  defp do_put_in([head | tail], key, val, acc) when is_map(acc) do
    Map.put(acc, head, do_put_in(tail, key, val, Map.get(acc, head, %{})))
  end
  defp do_put_in(_to, _key, _val, acc) do
    throw "Error: invalid type #{inspect acc}, should be map"
  end

  defp do_put_in_new([], acc) when is_list(acc) do
    List.insert_at(acc, -1, %{})
  end
  defp do_put_in_new([], acc) when is_map(acc) do
    [%{}]
  end
  defp do_put_in_new(to, acc) when is_list(acc) do
    List.update_at(acc, -1, &do_put_in_new(to, &1))
  end
  defp do_put_in_new([head | tail], acc) when is_map(acc) do
    Map.put(acc, head, do_put_in_new(tail, Map.get(acc, head, %{})))
  end
end
