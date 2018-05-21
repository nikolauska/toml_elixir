defmodule TomlElixirTest do
  use ExUnit.Case
  #doctest TomlElixir

  @valid Path.join(["test", "toml", "valid"])
  @invalid Path.join(["test", "toml", "invalid"])

  test "without newline" do
    assert {:ok, %{"toml" => true}} = TomlElixir.parse("toml = true")
  end

  test "test ! parsers" do
    toml_file = Path.join(@valid, "bool.toml")
    assert %{"f" => false, "t" => true} = TomlElixir.parse!(File.read!(toml_file))
    assert %{"f" => false, "t" => true} = TomlElixir.parse_file!(toml_file)

    assert_raise File.Error, fn ->
      TomlElixir.parse_file!(toml_file <> "a")
    end

    err = assert_raise TomlElixir.Error, fn ->
      TomlElixir.parse!("a =")
    end

    assert err.reason == TomlElixir.Error.message(err)
  end

  test "invalid path" do
    assert {:error, _} = TomlElixir.parse_file("not_found.toml")
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
      assert {{:error, _}, ^file} = {TomlElixir.parse_file(toml_file), file}
    end
  end
end
