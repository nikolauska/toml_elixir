defmodule TomlElixir.DecodeKeysTest do
  use ExUnit.Case, async: true

  alias TomlElixir.Parser.Error

  @toml """
  title = "x"
  owner = { name = "a", dob = 1979-05-27T07:32:00Z }

  [server]
  port = 80

  [[server.items]]
  name = "first"

  [[server.items]]
  name = "second"
  tags = [{ name = "t" }]
  """

  test "keeps string keys by default" do
    assert %{"server" => %{"port" => 80}} = TomlElixir.decode!(@toml)
    assert TomlElixir.decode!(@toml, keys: :strings) == TomlElixir.decode!(@toml)
  end

  test "converts nested tables, inline tables, and arrays of tables to existing atoms" do
    _known = [:title, :owner, :name, :dob, :server, :port, :items, :tags]

    assert %{
             title: "x",
             owner: %{name: "a", dob: %DateTime{}},
             server: %{port: 80, items: [%{name: "first"}, %{name: "second", tags: [%{name: "t"}]}]}
           } = TomlElixir.decode!(@toml, keys: :atoms!)
  end

  test "fails for keys without an existing atom" do
    assert {:error, %Error{line: nil} = error} =
             TomlElixir.decode("[server]\ntoml_elixir_no_such_atom_key = 1", keys: :atoms!)

    assert error.reason ==
             ~s(Cannot convert key server.toml_elixir_no_such_atom_key: "toml_elixir_no_such_atom_key" is not an existing atom)

    assert_raise ArgumentError, fn -> String.to_existing_atom("toml_elixir_no_such_atom_key") end
  end

  test "uses an explicit mapping function" do
    mapping = %{"server" => :server, "port" => :port}

    assert TomlElixir.decode!("[server]\nport = 80", keys: &Map.fetch!(mapping, &1)) == %{server: %{port: 80}}

    assert {:error, %Error{reason: "Cannot convert key server.host: key \"host\" not found in:" <> _}} =
             TomlElixir.decode("[server]\nhost = 1", keys: &Map.fetch!(mapping, &1))
  end

  test "reports array indexes in conversion errors" do
    assert {:error, %Error{reason: "Cannot convert key items[1].bad: rejected"}} =
             TomlElixir.decode("[[items]]\nok = 1\n[[items]]\nbad = 2", keys: &reject_bad/1)
  end

  test "rejects keys that convert to the same term" do
    assert {:error, %Error{reason: ~s(Keys t.A, t.a all convert to "a")}} =
             TomlElixir.decode("[t]\na = 1\nA = 2", keys: &String.downcase/1)
  end

  test "validates duplicate keys before conversion" do
    assert {:error, %Error{reason: "Duplicate key a", line: 2}} =
             TomlElixir.decode("a = 1\na = 2", keys: &String.downcase/1)
  end

  test "raises for unsupported options" do
    assert_raise ArgumentError, ~r/invalid :keys option :atoms/, fn -> TomlElixir.decode("a = 1", keys: :atoms) end
  end

  defp reject_bad("bad"), do: raise("rejected")
  defp reject_bad(key), do: key
end
