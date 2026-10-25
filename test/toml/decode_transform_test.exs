defmodule TomlElixir.DecodeTransformTest do
  use ExUnit.Case, async: true

  alias TomlElixir.Parser.Error

  defmodule Server do
    @moduledoc false
    defstruct [:host, :port]
  end

  defp record(path, value) do
    send(self(), {:visit, path, value})
    value
  end

  defp visits do
    receive do
      {:visit, path, value} -> [{path, value} | visits()]
    after
      0 -> []
    end
  end

  test "visits every value with its path, children before parents, but not the document" do
    TomlElixir.decode!("a = 1\n[[s]]\nt = [2, { u = 3 }]", transform: &record/2)
    visited = visits()

    assert Enum.sort(Enum.map(visited, &elem(&1, 0))) ==
             Enum.sort([["a"], ["s"], ["s", 0], ["s", 0, "t"], ["s", 0, "t", 0], ["s", 0, "t", 1], ["s", 0, "t", 1, "u"]])

    order = visited |> Enum.map(&elem(&1, 0)) |> Enum.with_index() |> Map.new()
    assert order[["s", 0, "t", 1, "u"]] < order[["s", 0, "t", 1]]
    assert order[["s", 0, "t", 1]] < order[["s", 0, "t"]]
    assert order[["s", 0]] < order[["s"]]
  end

  test "passes transformed children to table callbacks to build structs" do
    toml = """
    [server]
    host = "localhost"
    port = 8080
    """

    transform = fn
      ["server"], %{"host" => host, "port" => port} -> %Server{host: host, port: port}
      ["server", "host"], host -> String.upcase(host)
      _path, value -> value
    end

    assert TomlElixir.decode!(toml, transform: transform) == %{"server" => %Server{host: "LOCALHOST", port: 8080}}
  end

  test "converts selected strings to known values" do
    transform = fn
      ["log", "level"], level -> Map.fetch!(%{"debug" => :debug, "info" => :info}, level)
      _path, value -> value
    end

    assert TomlElixir.decode!(~s([log]\nlevel = "info"), transform: transform) == %{"log" => %{"level" => :info}}
  end

  test "returns an error naming the path when the callback raises" do
    transform = fn
      ["servers", _index, "port"], port when port not in 1..65_535 -> raise ArgumentError, "port out of range"
      _path, value -> value
    end

    toml = "[[servers]]\nport = 80\n[[servers]]\nport = 70000"

    assert {:error, %Error{reason: "Cannot transform servers[1].port: port out of range", line: nil}} =
             TomlElixir.decode(toml, transform: transform)

    assert_raise Error, "Cannot transform servers[1].port: port out of range", fn ->
      TomlElixir.decode!(toml, transform: transform)
    end
  end

  test "uses original keys in paths when keys are converted" do
    _known = [:server, :port]
    TomlElixir.decode!("[server]\nport = 80", keys: :atoms!, transform: &record/2)

    assert Enum.sort(visits()) == [{["server"], %{port: 80}}, {["server", "port"], 80}]
  end

  test "passes datetimes as values" do
    assert %{"d" => :date} =
             TomlElixir.decode!("d = 1979-05-27", transform: fn _path, %Date{} -> :date end)
  end

  test "raises for unsupported options" do
    assert_raise ArgumentError, ~r/invalid :transform option/, fn ->
      TomlElixir.decode("a = 1", transform: fn value -> value end)
    end
  end
end
