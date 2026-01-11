defprotocol TomlElixir.Encoder do
  @moduledoc """
  Protocol for encoding Elixir terms to TOML.
  """

  @fallback_to_any true

  @doc "Encodes a value to TOML value format (inline)."
  def encode(value)
end

defmodule TomlElixir.Encoder.Helpers do
  @moduledoc false

  def encode_key(key) do
    key = to_string(key)

    if String.match?(key, ~r/\A[A-Za-z0-9_-]+\z/) and key != "" do
      key
    else
      "\"" <> escape_string(key) <> "\""
    end
  end

  def escape_string(str) do
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

defimpl TomlElixir.Encoder, for: Integer do
  def encode(v), do: Integer.to_string(v)
end

defimpl TomlElixir.Encoder, for: Float do
  def encode(f) do
    # TOML requires a fractional part or exponent
    str = Float.to_string(f)

    if String.contains?(str, ".") or String.contains?(str, "e") do
      str
    else
      str <> ".0"
    end
  end
end

defimpl TomlElixir.Encoder, for: BitString do
  def encode(v), do: "\"" <> TomlElixir.Encoder.Helpers.escape_string(v) <> "\""
end

defimpl TomlElixir.Encoder, for: Atom do
  def encode(true), do: "true"
  def encode(false), do: "false"
  def encode(:infinity), do: "inf"
  def encode(:neg_infinity), do: "-inf"
  def encode(:nan), do: "nan"
  def encode(nil), do: raise("nil is not supported in TOML")
  def encode(atom), do: TomlElixir.Encoder.encode(Atom.to_string(atom))
end

defimpl TomlElixir.Encoder, for: List do
  def encode(list) do
    "[" <> Enum.map_join(list, ", ", &TomlElixir.Encoder.encode/1) <> "]"
  end
end

defimpl TomlElixir.Encoder, for: Map do
  alias TomlElixir.Encoder.Helpers

  def encode(map) do
    # Inline table
    pairs =
      map
      |> Enum.sort_by(fn {k, _} -> to_string(k) end)
      |> Enum.map_join(", ", fn {k, v} ->
        [Helpers.encode_key(k), " = ", TomlElixir.Encoder.encode(v)]
      end)

    ["{", pairs, "}"]
  end
end

defimpl TomlElixir.Encoder, for: DateTime do
  def encode(dt), do: DateTime.to_iso8601(dt)
end

defimpl TomlElixir.Encoder, for: NaiveDateTime do
  def encode(dt), do: NaiveDateTime.to_iso8601(dt)
end

defimpl TomlElixir.Encoder, for: Date do
  def encode(dt), do: Date.to_iso8601(dt)
end

defimpl TomlElixir.Encoder, for: Time do
  def encode(dt), do: Time.to_iso8601(dt)
end

defimpl TomlElixir.Encoder, for: Any do
  def encode(struct) do
    if is_struct(struct) do
      struct
      |> Map.from_struct()
      |> TomlElixir.Encoder.encode()
    else
      raise Protocol.UndefinedError, protocol: TomlElixir.Encoder, value: struct
    end
  end
end

defmodule TomlElixir.Encoder.Serializer do
  @moduledoc false

  alias TomlElixir.Encoder.Helpers

  def encode(data, _opts \\ []) do
    {:ok, data |> encode_map([]) |> IO.iodata_to_binary()}
  end

  defp encode_map(data, path) do
    map = if is_struct(data), do: Map.from_struct(data), else: data

    {scalars, complex} =
      map
      |> Enum.sort_by(fn {k, _} -> to_string(k) end)
      |> Enum.split_with(fn {_, v} -> not is_map_like(v) and not is_array_of_maps(v) end)

    # Scalars first in the current scope
    scalar_lines =
      Enum.map(scalars, fn {k, v} ->
        [Helpers.encode_key(k), " = ", TomlElixir.Encoder.encode(v), "\n"]
      end)

    # Then sub-tables and array of tables
    complex_lines =
      Enum.map(complex, fn {k, v} ->
        raw_key = to_string(k)
        new_path = path ++ [raw_key]

        cond do
          is_array_of_maps(v) ->
            path_str = Enum.map_join(new_path, ".", &Helpers.encode_key/1)

            Enum.map(v, fn item ->
              [
                "\n[[",
                path_str,
                "]]\n",
                encode_map(item, new_path)
              ]
            end)

          is_map_like(v) ->
            path_str = Enum.map_join(new_path, ".", &Helpers.encode_key/1)

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
    is_list(v) and v != [] and Enum.all?(v, &is_map_like/1)
  end

  defp is_map_like(v) do
    is_map(v) and not is_special_scalar(v)
  end

  defp is_special_scalar(%DateTime{}), do: true
  defp is_special_scalar(%NaiveDateTime{}), do: true
  defp is_special_scalar(%Date{}), do: true
  defp is_special_scalar(%Time{}), do: true
  defp is_special_scalar(_), do: false
end
