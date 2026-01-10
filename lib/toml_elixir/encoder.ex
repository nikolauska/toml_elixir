defmodule TomlElixir.Encoder do
  @moduledoc false

  def encode(map, _opts \\ []) do
    {:ok, map |> encode_map([]) |> IO.iodata_to_binary()}
  end

  defp encode_map(map, path) do
    {scalars, complex} =
      map
      |> Enum.sort_by(fn {k, _} -> to_string(k) end)
      |> Enum.split_with(fn {_, v} -> not is_map_not_struct(v) and not is_array_of_maps(v) end)

    # Scalars first in the current scope
    scalar_lines =
      Enum.map(scalars, fn {k, v} ->
        [encode_key(k), " = ", encode_value(v), "\n"]
      end)

    # Then sub-tables and array of tables
    complex_lines =
      Enum.map(complex, fn {k, v} ->
        raw_key = to_string(k)
        # Handle cases where the key itself might be a dotted key string from decode
        # though usually decode returns nested maps.
        new_path = path ++ [raw_key]

        cond do
          is_array_of_maps(v) ->
            path_str = Enum.map_join(new_path, ".", &encode_key/1)

            Enum.map(v, fn item ->
              [
                "\n[[",
                path_str,
                "]]\n",
                encode_map(item, new_path)
              ]
            end)

          is_map_not_struct(v) ->
            path_str = Enum.map_join(new_path, ".", &encode_key/1)

            [
              "\n[",
              path_str,
              "]\n",
              encode_map(v, new_path)
            ]
        end
      end)

    [scalar_lines, complex_lines]
  end

  defp is_array_of_maps(v) do
    is_list(v) and v != [] and Enum.all?(v, &is_map_not_struct/1)
  end

  defp is_map_not_struct(v) do
    is_map(v) and not Map.has_key?(v, :__struct__)
  end

  defp encode_key(key) do
    key = to_string(key)

    if String.match?(key, ~r/\A[A-Za-z0-9_-]+\z/) and key != "" do
      key
    else
      "\"" <> escape_string(key) <> "\""
    end
  end

  defp encode_value(v) when is_binary(v), do: "\"" <> escape_string(v) <> "\""
  defp encode_value(v) when is_integer(v), do: Integer.to_string(v)
  defp encode_value(v) when is_float(v), do: encode_float(v)
  defp encode_value(true), do: "true"
  defp encode_value(false), do: "false"
  defp encode_value(%DateTime{} = dt), do: DateTime.to_iso8601(dt)
  defp encode_value(%NaiveDateTime{} = ndt), do: NaiveDateTime.to_iso8601(ndt)
  defp encode_value(%Date{} = d), do: Date.to_iso8601(d)
  defp encode_value(%Time{} = t), do: Time.to_iso8601(t)

  defp encode_value(map) when is_map(map) do
    # Inline table
    pairs =
      map
      |> Enum.sort_by(fn {k, _} -> to_string(k) end)
      |> Enum.map_join(", ", fn {k, v} -> [encode_key(k), " = ", encode_value(v)] end)

    ["{", pairs, "}"]
  end

  defp encode_value(list) when is_list(list) do
    "[" <> Enum.map_join(list, ", ", &encode_value/1) <> "]"
  end

  defp encode_value(:infinity), do: "inf"
  defp encode_value(:neg_infinity), do: "-inf"
  defp encode_value(:nan), do: "nan"

  defp encode_float(f) do
    # TOML requires a fractional part or exponent
    str = Float.to_string(f)

    if String.contains?(str, ".") or String.contains?(str, "e") do
      str
    else
      str <> ".0"
    end
  end

  defp escape_string(str) do
    str
    |> String.to_charlist()
    |> Enum.map(&escape_char/1)
    |> IO.iodata_to_binary()
  end

  defp escape_char(?\\), do: "\\\\"
  defp escape_char(?"), do: "\\\""
  defp escape_char(?\b), do: "\\b"
  defp escape_char(?\f), do: "\\f"
  defp escape_char(?\n), do: "\\n"
  defp escape_char(?\r), do: "\\r"
  defp escape_char(?\t), do: "\\t"

  defp escape_char(c) when c < 0x20 or c == 0x7F do
    "\\u" <> (c |> Integer.to_string(16) |> String.pad_leading(4, "0"))
  end

  defp escape_char(c), do: <<c::utf8>>
end
