defmodule TomlElixir.Spec110Test do
  use TomlElixir.SpecCase, async: true

  @moduletag :toml_spec
  @moduletag :toml_1_1_0

  @toml_root Path.expand(".", __DIR__)
  @list_path Path.join(@toml_root, "files-toml-1.1.0")

  @toml_files @list_path
              |> File.read!()
              |> String.split("\n")
              |> Enum.map(&String.trim/1)
              |> Enum.reject(&(&1 == "" or String.starts_with?(&1, "#")))
              |> Enum.filter(&String.ends_with?(&1, ".toml"))

  for rel_path <- @toml_files do
    cond do
      String.starts_with?(rel_path, "valid/") ->
        @tag :valid
        test "valid #{rel_path}" do
          path = Path.join(@toml_root, unquote(rel_path))

          json_path =
            unquote(rel_path)
            |> Path.rootname()
            |> Kernel.<>(".json")
            |> then(&Path.join(@toml_root, &1))

          expected =
            json_path
            |> File.read!()
            |> JSON.decode!()
            |> normalize_for_test()

          toml = File.read!(path)
          assert {:ok, actual} = TomlElixir.decode(toml, spec: :"1.1.0")
          assert normalize_for_test(actual) == expected
        end

      String.starts_with?(rel_path, "invalid/") ->
        @tag :invalid
        test "invalid #{rel_path}" do
          path = Path.join(@toml_root, unquote(rel_path))
          toml = File.read!(path)
          assert {:error, _} = TomlElixir.decode(toml, spec: :"1.1.0")
        end

      true ->
        raise "Unexpected TOML fixture path: #{rel_path}"
    end
  end
end
