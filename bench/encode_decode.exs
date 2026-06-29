toml = File.read!(Path.expand("fixtures/example.toml", __DIR__))
decoded = TomlElixir.decode!(toml)

Benchee.run(%{
  "decode" => fn -> TomlElixir.decode!(toml) end,
  "encode" => fn -> TomlElixir.encode!(decoded) end
})
