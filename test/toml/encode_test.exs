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
      |> Enum.filter(&String.starts_with?(&1, "valid/"))
      |> Enum.filter(&String.ends_with?(&1, ".toml"))
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
