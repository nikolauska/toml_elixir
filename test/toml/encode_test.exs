defmodule TomlElixir.EncodeTest do
  use ExUnit.Case, async: true

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
