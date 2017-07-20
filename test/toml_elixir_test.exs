defmodule TomlElixirTest do
  use ExUnit.Case
  #doctest TomlElixir

  test "options" do
    assert {:ok, %{}} = TomlElixir.parse("")
    assert {:ok, %{}} = TomlElixir.parse("", to_map: true)
    assert {:ok, []} = TomlElixir.parse("", to_map: false)

    # TODO Deprecate
    assert {:ok, []} = TomlElixir.parse("", no_parse: true)
    assert {:ok, %{}} = TomlElixir.parse("", no_parse: false)
  end

  test "example toml" do
    {:ok, parsed} = TomlElixir.parse_file("test/toml/example.toml")

    assert is_map(parsed)
    assert parsed["title"] == "TOML Example"

    assert parsed["owner"]["name"] == "Tom Preston-Werner"
    assert parsed["owner"]["organization"] == "GitHub"
    assert parsed["owner"]["bio"] == "GitHub Cofounder & CEO\nLikes tater" <>
                                    " tots and beer."

    assert parsed["database"]["server"] == "192.168.1.1"
    assert parsed["database"]["ports"] == [ 8001, 8001, 8002 ]
    assert parsed["database"]["connection_max"] == 5000
    assert parsed["database"]["enabled"] == true

    assert parsed["servers"]["alpha"]["ip"] == "10.0.0.1"
    assert parsed["servers"]["alpha"]["dc"] == "eqdc10"

    assert parsed["servers"]["beta"]["ip"] == "10.0.0.2"
    assert parsed["servers"]["beta"]["dc"] == "eqdc10"

    assert parsed["clients"]["data"] == [["gamma", "delta"], [1, 2]]
    assert parsed["clients"]["hosts"] == ["alpha", "omega"]
  end

  test "hard toml" do
    {:ok, parsed} = TomlElixir.parse_file("test/toml/hard.toml")

    assert is_map(parsed)
    assert is_binary(parsed["the"]["test_string"])
    assert is_map(parsed["the"]["hard"])
    assert is_binary(parsed["the"]["hard"]["another_test_string"])
    assert is_map(parsed["the"]["hard"]["bit#"])
    assert is_binary(parsed["the"]["hard"]["bit#"]["what?"])
    assert is_list(parsed["the"]["hard"]["bit#"]["multi_line_array"])
    assert is_binary(parsed["the"]["hard"]["harder_test_string"])
    assert is_list(parsed["the"]["hard"]["test_array"])
    assert is_list(parsed["the"]["hard"]["test_array2"])
  end

  test "fruit toml" do
    parsed = TomlElixir.parse_file!("test/toml/fruit.toml")

    blah = parsed["fruit"]["blah"]

    blah1_physical = %{"color" => "red", "shape" => "round"}
    blah1 = %{"name" => "apple", "physical" => blah1_physical}

    blah2_physical = %{"color" => "yellow", "shape" => "bent"}
    blah2 = %{"name" => "banana", "physical" => blah2_physical}

    assert [blah1, blah2] == blah
  end

  test "invalid toml" do
    lexer = "test/toml/invalid_lexer.toml"
    assert catch_error(TomlElixir.parse_file!(lexer))
    assert {:error, _} = TomlElixir.parse_file(lexer)

    parser = "test/toml/invalid_parser.toml"
    assert catch_error(TomlElixir.parse_file!(parser))
    assert {:error, _} = TomlElixir.parse_file(parser)
  end
end
