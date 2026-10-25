defmodule TomlElixir.Parser.Keys do
  @moduledoc false

  alias TomlElixir.KeyPath
  alias TomlElixir.Parser.Error

  @type converter :: (String.t() -> term) | nil

  @spec converter!(term) :: converter
  def converter!(:strings), do: nil
  def converter!(:atoms!), do: &existing_atom/1
  def converter!(fun) when is_function(fun, 1), do: fun

  def converter!(other) do
    raise ArgumentError, "invalid :keys option #{inspect(other)}, expected :strings, :atoms!, or a 1-arity function"
  end

  # Conversion runs on the finished map so TOML duplicate-key validation still sees the
  # original string keys, and the default `:strings` path does no extra traversal.
  @spec convert(map, converter) :: map
  def convert(map, nil), do: map
  def convert(map, fun), do: convert_table(map, [], fun)

  defp convert_table(map, path, fun) do
    converted =
      :maps.fold(
        fn key, value, acc ->
          key_path = [key | path]
          [{convert_key(fun, key, key_path), convert_value(value, key_path, fun)} | acc]
        end,
        [],
        map
      )

    table = :maps.from_list(converted)

    # Distinct TOML keys may convert to the same term; a smaller map means one value was
    # dropped. Comparing sizes keeps collision checks off the per-key path.
    if map_size(table) != map_size(map) do
      raise_collision(map, path, fun)
    end

    table
  end

  defp raise_collision(map, path, fun) do
    map
    |> Map.keys()
    |> Enum.group_by(fun)
    |> Enum.find(&match?({_converted, [_, _ | _]}, &1))
    |> then(fn {converted, keys} ->
      Error.raise(
        "Keys #{Enum.map_join(Enum.sort(keys), ", ", &format([&1 | path]))} all convert to #{inspect(converted)}"
      )
    end)
  end

  defp convert_value(map, path, fun) when is_map(map) and not is_struct(map), do: convert_table(map, path, fun)
  defp convert_value(list, path, fun) when is_list(list), do: convert_list(list, 0, path, fun)
  defp convert_value(value, _path, _fun), do: value

  defp convert_list([value | rest], index, path, fun) do
    [convert_value(value, [index | path], fun) | convert_list(rest, index + 1, path, fun)]
  end

  defp convert_list([], _index, _path, _fun), do: []

  defp convert_key(fun, key, path) do
    fun.(key)
  rescue
    exception -> Error.raise("Cannot convert key #{format(path)}: #{Exception.message(exception)}")
  end

  defp existing_atom(key) do
    String.to_existing_atom(key)
  rescue
    ArgumentError -> reraise ArgumentError, "#{inspect(key)} is not an existing atom", __STACKTRACE__
  end

  defp format(path), do: path |> Enum.reverse() |> KeyPath.format()
end
