inputs =
  __DIR__
  |> Path.join("fixtures/*.toml")
  |> Path.wildcard()
  |> Map.new(&{Path.basename(&1), &1 |> File.read!() |> TomlElixir.decode!()})

Benchee.run(%{"encode" => &TomlElixir.encode!/1},
  inputs: inputs,
  memory_time: 2,
  reduction_time: 2
)
