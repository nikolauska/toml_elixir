inputs =
  __DIR__
  |> Path.join("fixtures/*.toml")
  |> Path.wildcard()
  |> Map.new(&{Path.basename(&1), File.read!(&1)})

Benchee.run(%{"decode" => &TomlElixir.decode!/1},
  inputs: inputs,
  memory_time: 2,
  reduction_time: 2
)
