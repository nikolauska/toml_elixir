defmodule TomlElixir.EncodeTest do
  use TomlElixir.SpecCase, async: true

  alias TomlElixir.Encoder.Error

  @toml_root Path.expand(".", __DIR__)
  for_result =
    for spec <- ["1.0.0", "1.1.0"] do
      @toml_root
      |> Path.join("files-toml-#{spec}")
      |> File.read!()
      |> String.split("\n")
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == "" or String.starts_with?(&1, "#")))
      |> Enum.filter(&(String.starts_with?(&1, "valid/") and String.ends_with?(&1, ".toml")))
      |> Enum.map(fn path -> {spec, path} end)
    end

  @valid_files List.flatten(for_result)

  for {spec_ver, rel_path} <- @valid_files do
    test "roundtrip encode/decode for #{spec_ver} #{rel_path}" do
      spec_atom = String.to_atom(unquote(spec_ver))

      json_path =
        unquote(rel_path)
        |> Path.rootname()
        |> Kernel.<>(".json")
        |> then(&Path.join(@toml_root, &1))

      original =
        json_path
        |> File.read!()
        |> JSON.decode!()
        |> normalize_for_test()

      # We skip nan because nan != nan
      if contains_nan?(original) do
        :ok
      else
        encoded = TomlElixir.encode!(original)
        assert IO.iodata_to_binary(TomlElixir.encode_to_iodata!(original)) == encoded
        multiline = TomlElixir.encode!(original, multiline_arrays: true)
        assert normalize_for_test(TomlElixir.decode!(multiline, spec: spec_atom)) == normalize_for_test(original)
        {:ok, decoded} = TomlElixir.decode(encoded, spec: spec_atom)

        # Normalize both for comparison (esp. datetime precision)
        assert normalize_for_test(decoded) == normalize_for_test(original)
      end
    end
  end

  describe "encode_to_iodata" do
    test "returns iodata with the same content as encode/2" do
      data = %{title: "x", server: %{ports: [1, 2]}, items: [%{a: 1}, %{a: 2}]}

      assert {:ok, iodata} = TomlElixir.encode_to_iodata(data)
      assert is_list(iodata)
      assert IO.iodata_to_binary(iodata) == TomlElixir.encode!(data)
    end

    test "returns and raises the same errors as encode/2" do
      data = %{server: %{port: nil}}

      assert TomlElixir.encode_to_iodata(data) == TomlElixir.encode(data)

      assert_raise Error, "server.port: nil is not supported in TOML", fn ->
        TomlElixir.encode_to_iodata!(data)
      end
    end
  end

  describe "floats" do
    test "always include a fraction or exponent" do
      data = %{a: 1.0, b: -0.0, c: 1.0e20, d: 1.0e-7, e: 0.1, f: 1.5e300}

      assert TomlElixir.encode!(data) ==
               "a = 1.0\nb = -0.0\nc = 1.0e20\nd = 1.0e-7\ne = 0.1\nf = 1.5e300\n"

      assert TomlElixir.decode!(TomlElixir.encode!(data)) == Map.new(data, fn {k, v} -> {to_string(k), v} end)
    end
  end

  describe "formatting options" do
    test "writes one array element per line with multiline_arrays" do
      data = %{ports: [8000, 8001], empty: [], nested: [[1, 2]]}

      assert TomlElixir.encode!(data, multiline_arrays: true) == """
             empty = []
             nested = [
               [1, 2],
             ]
             ports = [
               8000,
               8001,
             ]
             """
    end

    test "renders selected tables and arrays of tables inline" do
      data = %{
        database: %{port: 1, targets: %{cpu: 79.5}},
        points: [%{x: 1}, %{x: 2}],
        other: %{a: 1}
      }

      assert TomlElixir.encode!(data, inline_tables: [[:database, :targets], ["points"]]) == """
             points = [{x = 1}, {x = 2}]

             [database]
             port = 1
             targets = {cpu = 79.5}

             [other]
             a = 1
             """
    end

    test "applies inline paths through arrays of tables to every element" do
      data = %{products: [%{dims: %{w: 1}}, %{dims: %{w: 2}}]}

      assert TomlElixir.encode!(data, inline_tables: [[:products, :dims]]) == """

             [[products]]
             dims = {w = 1}

             [[products]]
             dims = {w = 2}
             """
    end

    test "keeps a table inline when a path below it is also listed" do
      data = %{a: %{b: %{c: 1}}}
      expected = "a = {b = {c = 1}}\n"

      assert TomlElixir.encode!(data, inline_tables: [[:a], [:a, :b]]) == expected
      assert TomlElixir.encode!(data, inline_tables: [[:a, :b], [:a]]) == expected
    end

    test "combines options and reports error paths inside inline tables" do
      data = %{points: [%{x: 1}, %{x: nil}]}

      assert TomlElixir.encode!(%{points: [%{x: 1}]}, inline_tables: [[:points]], multiline_arrays: true) ==
               "points = [\n  {x = 1},\n]\n"

      assert {:error, %Error{path: ["points", 1, "x"]}} = TomlElixir.encode(data, inline_tables: [[:points]])
    end

    test "keeps the default output without options" do
      data = %{a: [1, 2], t: %{b: 1}}
      assert TomlElixir.encode!(data, multiline_arrays: false, inline_tables: []) == TomlElixir.encode!(data)
    end

    test "raises for invalid options" do
      assert_raise ArgumentError, ~r/:multiline_arrays/, fn -> TomlElixir.encode(%{}, multiline_arrays: :yes) end
      assert_raise ArgumentError, ~r/:inline_tables option/, fn -> TomlElixir.encode(%{}, inline_tables: :all) end
      assert_raise ArgumentError, ~r/:inline_tables path/, fn -> TomlElixir.encode(%{}, inline_tables: [[]]) end
      assert_raise ArgumentError, ~r/:inline_tables key/, fn -> TomlElixir.encode(%{}, inline_tables: [[1]]) end
    end
  end

  describe "encode errors" do
    test "reports the key path of a nested failure" do
      assert {:error, %Error{reason: "nil is not supported in TOML", path: ["server", "port"]} = error} =
               TomlElixir.encode(%{server: %{port: nil}})

      assert Exception.message(error) == "server.port: nil is not supported in TOML"
    end

    test "reports array indexes in the path" do
      assert {:error, %Error{path: ["servers", 1, "port"]}} =
               TomlElixir.encode(%{servers: [%{port: 1}, %{port: nil}]})

      assert {:error, %Error{path: ["a", 1, 1]} = error} = TomlElixir.encode(%{a: [1, [2, nil]]})
      assert Exception.message(error) =~ ~r/^a\[1\]\[1\]: /
    end

    test "reports the first failure in encoding order" do
      assert {:error, %Error{path: ["a"]}} = TomlElixir.encode(%{a: nil, b: %{c: nil}})
      # Scalars are written before sub-tables, so `b` fails before `a.c`.
      assert {:error, %Error{path: ["b"]}} = TomlElixir.encode(%{a: %{c: nil}, b: nil})
    end

    test "quotes keys that are not bare in the message" do
      assert {:error, error} = TomlElixir.encode(%{"a b" => %{c: nil}})
      assert Exception.message(error) == ~s("a b".c: nil is not supported in TOML)
    end

    test "uses an empty path for top-level failures" do
      assert {:error, %Error{path: []} = error} = TomlElixir.encode(%{{1} => 1})
      assert Exception.message(error) == error.reason
    end

    test "raises the error from encode!/2" do
      assert_raise Error, "server.port: nil is not supported in TOML", fn ->
        TomlElixir.encode!(%{server: %{port: nil}})
      end
    end
  end

  defp contains_nan?(map) when is_map(map) do
    if Map.has_key?(map, :__struct__) do
      false
    else
      Enum.any?(map, fn {_, v} -> contains_nan?(v) end)
    end
  end

  defp contains_nan?(list) when is_list(list), do: Enum.any?(list, &contains_nan?/1)
  defp contains_nan?(:nan), do: true
  defp contains_nan?(_), do: false
end
