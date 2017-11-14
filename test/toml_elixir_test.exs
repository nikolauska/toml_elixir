defmodule TomlElixirTest do
  use ExUnit.Case
  #doctest TomlElixir

  @valid Path.join(["test", "toml", "valid"])
  @invalid Path.join(["test", "toml", "invalid"])

  test "options" do
    assert {:ok, %{}} = TomlElixir.parse("")
    assert {:ok, %{}} = TomlElixir.parse("", to_map: true)
    assert {:ok, []} = TomlElixir.parse("", to_map: false)
    assert %{} = TomlElixir.parse!("")
    assert %{} = TomlElixir.parse!("", to_map: true)
    assert [] = TomlElixir.parse!("", to_map: false)

    # TODO Deprecate
    assert {:ok, []} = TomlElixir.parse("", no_parse: true)
    assert {:ok, %{}} = TomlElixir.parse("", no_parse: false)
    assert [] = TomlElixir.parse!("", no_parse: true)
    assert %{} = TomlElixir.parse!("", no_parse: false)
  end

  test "valid toml files" do
    files =
      @valid
      |> File.ls!()
      |> Enum.filter(&String.contains?(&1, ".toml"))
      |> Enum.map(fn toml -> {toml, String.replace(toml, ".toml", ".json")} end)

    for {toml_file, json_file} <- files do
      json_path = Path.join(@valid, json_file)
      json =
        json_path
        |> File.read!()
        |> Poison.decode!()

      assert {:ok, json} == TomlElixir.parse_file(Path.join(@valid, toml_file))
    end
  end

  test "invalid toml files" do
    for file <- File.ls!(@invalid) do
      assert {:error, _} = TomlElixir.parse_file(Path.join(@invalid, file))
    end
  end
end
