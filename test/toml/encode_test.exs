defmodule TomlElixir.EncodeTest do
  use TomlElixir.SpecCase, async: true

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
        {:ok, decoded} = TomlElixir.decode(encoded, spec: spec_atom)

        # Normalize both for comparison (esp. datetime precision)
        assert normalize_for_test(decoded) == normalize_for_test(original)
      end
    end
  end

  describe "encode errors" do
    alias TomlElixir.Encoder.Error

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
