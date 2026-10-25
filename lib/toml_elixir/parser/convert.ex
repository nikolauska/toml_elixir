defmodule TomlElixir.Parser.Convert do
  @moduledoc false

  alias TomlElixir.KeyPath
  alias TomlElixir.Parser.Error

  @type key_converter :: (String.t() -> term) | nil
  @type transformer :: ([String.t() | non_neg_integer], term -> term) | nil

  @spec key_converter!(term) :: key_converter
  def key_converter!(:strings), do: nil
  def key_converter!(:atoms!), do: &existing_atom/1
  def key_converter!(fun) when is_function(fun, 1), do: fun

  def key_converter!(other) do
    raise ArgumentError, "invalid :keys option #{inspect(other)}, expected :strings, :atoms!, or a 1-arity function"
  end

  @spec transformer!(term) :: transformer
  def transformer!(nil), do: nil
  def transformer!(fun) when is_function(fun, 2), do: fun

  def transformer!(other) do
    raise ArgumentError, "invalid :transform option #{inspect(other)}, expected a 2-arity function"
  end

  # Conversion runs on the finished map so TOML duplicate-key validation still sees the
  # original string keys. Key conversion and transforms share one traversal, and decoding
  # without either option does no extra traversal.
  @spec convert(map, key_converter, transformer) :: map
  def convert(map, nil, nil), do: map
  def convert(map, keys, transform), do: convert_table(map, [], keys, transform)

  # Paths are built in reverse while descending and only reversed when a callback or
  # error message needs one.
  defp convert_table(map, path, keys, transform) do
    converted =
      :maps.fold(
        fn key, value, acc ->
          key_path = [key | path]
          [{convert_key(keys, key, key_path), convert_value(value, key_path, keys, transform)} | acc]
        end,
        [],
        map
      )

    table = :maps.from_list(converted)

    # Distinct TOML keys may convert to the same term; a smaller map means one value was
    # dropped. Comparing sizes keeps collision checks off the per-key path.
    if map_size(table) != map_size(map) do
      raise_collision(map, path, keys)
    end

    table
  end

  defp raise_collision(map, path, keys) do
    map
    |> Map.keys()
    |> Enum.group_by(keys)
    |> Enum.find(&match?({_converted, [_, _ | _]}, &1))
    |> then(fn {converted, colliding} ->
      Error.raise(
        "Keys #{Enum.map_join(Enum.sort(colliding), ", ", &format([&1 | path]))} all convert to #{inspect(converted)}"
      )
    end)
  end

  # Children are converted before their parent is transformed, so a table callback sees
  # transformed values and can build structs from them.
  defp convert_value(value, path, keys, transform) do
    converted =
      cond do
        is_map(value) and not is_struct(value) -> convert_table(value, path, keys, transform)
        is_list(value) -> convert_list(value, 0, path, keys, transform)
        true -> value
      end

    apply_transform(transform, path, converted)
  end

  defp convert_list([value | rest], index, path, keys, transform) do
    [convert_value(value, [index | path], keys, transform) | convert_list(rest, index + 1, path, keys, transform)]
  end

  defp convert_list([], _index, _path, _keys, _transform), do: []

  defp convert_key(nil, key, _path), do: key

  defp convert_key(keys, key, path) do
    keys.(key)
  rescue
    exception -> Error.raise("Cannot convert key #{format(path)}: #{Exception.message(exception)}")
  end

  defp apply_transform(nil, _path, value), do: value

  defp apply_transform(transform, path, value) do
    transform.(Enum.reverse(path), value)
  rescue
    exception -> Error.raise("Cannot transform #{format(path)}: #{Exception.message(exception)}")
  end

  defp existing_atom(key) do
    String.to_existing_atom(key)
  rescue
    ArgumentError -> reraise ArgumentError, "#{inspect(key)} is not an existing atom", __STACKTRACE__
  end

  defp format(path), do: path |> Enum.reverse() |> KeyPath.format()
end
