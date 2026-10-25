alias TomlElixir.Document

# Edits need a path that exists in every fixture, so pick the first scalar in sorted key
# order. Any scalar belongs to a key/value line, which `put/3` and `delete/2` support.
find_leaf = fn find_leaf, value, path ->
  case value do
    map when is_map(map) and not is_struct(map) ->
      map |> Enum.sort() |> Enum.find_value(fn {key, child} -> find_leaf.(find_leaf, child, [key | path]) end)

    list when is_list(list) ->
      list |> Enum.with_index() |> Enum.find_value(fn {child, index} -> find_leaf.(find_leaf, child, [index | path]) end)

    scalar ->
      {Enum.reverse(path), scalar}
  end
end

inputs =
  __DIR__
  |> Path.join("fixtures/*.toml")
  |> Path.wildcard()
  |> Map.new(fn path ->
    source = File.read!(path)
    doc = Document.parse!(source)
    {leaf, current} = find_leaf.(find_leaf, Document.to_map(doc), [])
    # Putting an equal value is a no-op, so the replacement must differ.
    value = if is_integer(current), do: current + 1, else: "changed"
    # The table holding the leaf, extended by one key, so the replacement diffs every key.
    table_path =
      leaf
      |> Enum.drop(-1)
      |> Stream.iterate(&Enum.drop(&1, -1))
      |> Enum.find(&match?(%{}, Document.get(doc, &1)))

    table = doc |> Document.get(table_path) |> Map.put("__bench_new_key__", 1)

    {Path.basename(path), %{source: source, doc: doc, leaf: leaf, value: value, table_path: table_path, table: table}}
  end)

# `decode` is the baseline: `parse` runs it first, and every edit runs it again to
# re-validate, so the gap between them is the cost of the lossless representation.
# `put` replaces an existing value, `insert` adds a new root key, and `replace table`
# puts a table back with one extra key.
Benchee.run(
  %{
    "decode" => fn %{source: source} -> TomlElixir.decode!(source) end,
    "parse" => fn %{source: source} -> Document.parse!(source) end,
    "to_iodata" => fn %{doc: doc} -> Document.to_iodata(doc) end,
    "put" => fn %{doc: doc, leaf: leaf, value: value} -> Document.put!(doc, leaf, value) end,
    "insert" => fn %{doc: doc} -> Document.put!(doc, ["__bench_new_key__"], 1) end,
    "replace table" => fn %{doc: doc, table_path: path, table: table} -> Document.put!(doc, path, table) end,
    "delete" => fn %{doc: doc, leaf: leaf} -> Document.delete!(doc, leaf) end
  },
  inputs: inputs,
  memory_time: 2,
  reduction_time: 2
)
