defmodule TomlElixir.Mapper do

  @doc """
  Parse list of values to map
  """
  @spec parse(TomlElixir.toml_return) :: map
  def parse(toml) do
    to_map(toml)
  end

  # Turn toml tuple list to map
  @spec to_map(TomlElixir.toml_return) :: map
  @spec to_map(TomlElixir.toml_return, [] | [any] | map) :: map
  defp to_map(val),
    do: to_map(val, %{})
  defp to_map(val, []),
    do: [to_map(val, %{})]
  defp to_map(val, list) when is_list(list),
    do: List.update_at(list, -1, &(to_map(val, &1)))
  defp to_map([{:group, idents, values} | tail], map),
    do: to_map(tail, group(idents, values, map))
  defp to_map([{:multi, idents, values} | tail], map),
    do: to_map(tail, multi(idents, values, map))
  defp to_map([{{:identifier, key}, values} | tail], map) when is_list(values),
    do: to_map(tail, put(map, key, value(values)))
  defp to_map([{{:identifier, key}, val} | tail], map),
    do: to_map(tail, put(map, key, value(val)))
  defp to_map([], map),
    do: map

  # Turn group tuple to map
  @spec group([TomlElixir.toml_ident], [TomlElixir.toml_key_val], [any] | map) :: map | [any]
  defp group(idents, values, []),
    do: [group(idents, values, %{})]
  defp group(idents, values, list) when is_list(list),
    do: List.update_at(list, -1, &group(idents, values, &1))
  defp group([{:identifier, key} | tail], values, map),
    do: put(map, key, group(tail, values, get(map, key, %{})))
  defp group([], values, map),
    do: to_map(values, map)

  # Turn multi tuple to map
  @spec multi([TomlElixir.toml_ident], [TomlElixir.toml_key_val], map) :: map
  defp multi([{:identifier, key} | []], values, map),
    do: put(map, key, to_map(values, insert_end(map, key, %{})))
  defp multi([{:identifier, key} | tail], values, map),
    do: put(map, key, multi(tail, values, get(map, key, %{})))

  # Parse value from toml value tuple
  @spec value(TomlElixir.toml_value | [TomlElixir.toml_value]) :: any
  defp value([]), do: []
  defp value([head | tail]), do: [value(head) | value(tail)]
  defp value({:string, val}), do: "#{val}"
  defp value({:datetime, val}), do: val
  defp value({:number, val}), do: val
  defp value({:boolean, val}), do: val

  # Add value to end of the list
  @spec insert_end(map, binary, any) :: [map]
  defp insert_end(map, key, value),
    do: List.insert_at(get(map, key, []), -1, value)

  # Get value from map
  @spec get(map, binary, any) :: any
  defp get(map, key, default),
    do: Map.get(map, "#{key}", default)

  # Put value to map
  @spec put(map, binary, any) :: map
  defp put(map, key, value),
    do: Map.put(map, "#{key}", value)
end
