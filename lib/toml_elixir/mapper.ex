defmodule TomlElixir.Mapper do
  @moduledoc """
  Module for transforming toml list to map format
  """
  alias TomlElixir.Error

  @doc """
  Transform TOML list to map format
  """
  @spec parse(list) :: map
  def parse([]), do: %{}
  def parse(toml) when is_list(toml), do: to_map(toml, {[], %{}})

  @spec to_map(list, {list, map}) :: map
  defp to_map([], {_to, acc}), do: acc
  defp to_map([{:table, to} | _tail], {to, _acc}) do
    throw Error.exception("Duplicate table #{Enum.join(to, ".")}")
  end
  defp to_map([{:table, to} | []], {_to, acc}) do
    do_put_in(to, nil, %{}, acc)
  end
  defp to_map([{:table, to} | tail], {_to, acc}) do
    to_map(tail, {to, acc})
  end
  defp to_map([{:array_table, to} | tail], {_to, acc}) do
    to_map(tail, {to, do_put_in_new(to, acc)})
  end
  defp to_map([{{:key, key}, {:array, val}} | tail], {to, acc}) do
    to_map(tail, {to, do_put_in(to, key, val, acc)})
  end
  defp to_map([{{:key, key}, {:datetime, val}} | tail], {to, acc}) do
    to_map(tail, {to, do_put_in(to, key, val, acc)})
  end
  defp to_map([{{:key, key}, {:date, val}} | tail], {to, acc}) do
    to_map(tail, {to, do_put_in(to, key, val, acc)})
  end
  defp to_map([{{:key, key}, {:time, val}} | tail], {to, acc}) do
    to_map(tail, {to, do_put_in(to, key, val, acc)})
  end
  defp to_map([{{:key, key}, {:string, val}} | tail], {to, acc}) do
    to_map(tail, {to, do_put_in(to, key, val, acc)})
  end
  defp to_map([{{:key, key}, {:string_ml, val}} | tail], {to, acc}) do
    to_map(tail, {to, do_put_in(to, key, val, acc)})
  end
  defp to_map([{{:key, key}, {:literal, val}} | tail], {to, acc}) do
    to_map(tail, {to, do_put_in(to, key, val, acc)})
  end
  defp to_map([{{:key, key}, {:literal_ml, val}} | tail], {to, acc}) do
    to_map(tail, {to, do_put_in(to, key, val, acc)})
  end
  defp to_map([{{:key, key}, {:inline_table, val}} | tail], {to, acc}) when is_list(val) do
    to_map(tail, {to, do_put_in(to, key, parse(val), acc)})
  end
  defp to_map([{{:key, key}, val} | tail], {to, acc}) when is_list(val) do
    to_map(tail, {to, do_put_in(to, key, parse(val), acc)})
  end
  defp to_map([{{:key, key}, val} | tail], {to, acc}) do
    to_map(tail, {to, do_put_in(to, key, val, acc)})
  end

  @spec do_put_in(list, String.t | nil, any, list | map) :: map
  defp do_put_in([], key, val, []) do
    [Map.put(%{}, key, val)]
  end
  defp do_put_in([], key, val, acc) when is_list(acc) do
    List.update_at(acc, -1, &Map.put(&1, key, val))
  end
  defp do_put_in([], key, val, acc) when is_map(acc) do
    if Map.has_key?(acc, key) do
      throw Error.exception("Duplicate key #{key}")
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
    throw Error.exception("Invalid type #{inspect acc}, should be map")
  end

  @spec do_put_in_new(list, list | map) :: list | map
  defp do_put_in_new([], acc) when is_list(acc) do
    List.insert_at(acc, -1, %{})
  end
  defp do_put_in_new([], acc) when acc == %{} do
    [%{}]
  end
  defp do_put_in_new([], acc) when is_map(acc) do
    throw Error.exception("Should be empty, but #{inspect acc} was found")
  end
  defp do_put_in_new(to, acc) when is_list(acc) do
    List.update_at(acc, -1, &do_put_in_new(to, &1))
  end
  defp do_put_in_new([head | tail], acc) when is_map(acc) do
    Map.put(acc, head, do_put_in_new(tail, Map.get(acc, head, %{})))
  end
end
