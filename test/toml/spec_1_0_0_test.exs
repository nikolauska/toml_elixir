defmodule TomlElixir.Spec100Test do
  use ExUnit.Case, async: true

  @moduletag :toml_spec
  @moduletag :toml_1_0_0

  @toml_root Path.expand(".", __DIR__)
  @list_path Path.join(@toml_root, "files-toml-1.0.0")

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

          assert {:ok, actual} = TomlElixir.parse_file(path, spec: :"1.0.0")
          assert normalize_for_test(actual) == expected
        end

      String.starts_with?(rel_path, "invalid/") ->
        @tag :invalid
        test "invalid #{rel_path}" do
          path = Path.join(@toml_root, unquote(rel_path))
          assert {:error, _} = TomlElixir.parse_file(path, spec: :"1.0.0")
        end

      true ->
        raise "Unexpected TOML fixture path: #{rel_path}"
    end
  end

  defp normalize_for_test(val) when is_map(val) do
    cond do
      Map.has_key?(val, :__struct__) and val.__struct__ in [DateTime, NaiveDateTime, Time] ->
        %{val | microsecond: {elem(val.microsecond, 0), 6}}

      Map.has_key?(val, :__struct__) ->
        val

      Map.has_key?(val, "type") and Map.has_key?(val, "value") and map_size(val) == 2 ->
        val["type"] |> convert_scalar(val["value"]) |> normalize_for_test()

      true ->
        Map.new(val, fn {k, v} -> {k, normalize_for_test(v)} end)
    end
  end

  defp normalize_for_test(val) when is_list(val) do
    Enum.map(val, &normalize_for_test/1)
  end

  defp normalize_for_test(val), do: val

  defp convert_scalar("string", value), do: value
  defp convert_scalar("bool", "true"), do: true
  defp convert_scalar("bool", "false"), do: false
  defp convert_scalar("integer", value), do: String.to_integer(value)

  defp convert_scalar("float", value) do
    case value do
      v when v in ["inf", "+inf"] ->
        :infinity

      "-inf" ->
        :neg_infinity

      v when v in ["nan", "+nan", "-nan"] ->
        :nan

      _ ->
        {f, _} = Float.parse(value)
        f
    end
  end

  defp convert_scalar("datetime", value), do: value |> DateTime.from_iso8601() |> elem(1)
  defp convert_scalar("datetime-local", value), do: NaiveDateTime.from_iso8601!(value)
  defp convert_scalar("date-local", value), do: Date.from_iso8601!(value)
  defp convert_scalar("time-local", value), do: Time.from_iso8601!(value)
end
