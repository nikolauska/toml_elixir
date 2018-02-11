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
  end

  test "without newline" do
    assert {:ok, %{"toml" => true}} = TomlElixir.parse("toml = true")
  end

  test "valid toml files" do
    files =
      @valid
      |> File.ls!()
      |> Enum.filter(&String.contains?(&1, ".toml"))
      |> Enum.map(&String.replace(&1, ".toml", ""))

    for file <- files do
      json =
        @valid
        |> Path.join(file <> ".json")
        |> File.read!()
        |> Poison.decode!()

      toml_file = Path.join(@valid, file <> ".toml")

      assert {{:ok, json}, file} == {TomlElixir.parse_file(toml_file), file}
    end
  end

  test "invalid toml files" do
    files =
      @invalid
      |> File.ls!()
      |> Enum.map(&String.replace(&1, ".toml", ""))

    for file <- files do
      toml_file = Path.join(@invalid, file <> ".toml")
      assert {{:error, _}, file} = {TomlElixir.parse_file(toml_file), file}
    end
  end
end
