defprotocol TomlElixir.Encoder do
  @moduledoc """
  Protocol for encoding Elixir terms to TOML.

  You can derive this protocol for structs:

      @derive TomlElixir.Encoder
      defstruct [:name, :age]

      @derive {TomlElixir.Encoder, only: [:name]}
      defstruct [:name, :age, :password]

      @derive {TomlElixir.Encoder, except: [:password]}
      defstruct [:name, :age, :password]

  If you don't own the struct, you can derive externally:

      Protocol.derive(TomlElixir.Encoder, NameOfTheStruct, only: [:field])
      Protocol.derive(TomlElixir.Encoder, NameOfTheStruct, except: [:field])
      Protocol.derive(TomlElixir.Encoder, NameOfTheStruct)
  """

  @fallback_to_any true

  @impl true
  defmacro __deriving__(module, opts) do
    fields = module |> Macro.struct_info!(__CALLER__) |> Enum.map(& &1.field)
    fields = fields_to_encode(fields, opts)
    vars = Macro.generate_arguments(length(fields), __MODULE__)
    kv = Enum.zip(fields, vars)

    quote do
      defimpl TomlElixir.Encoder, for: unquote(module) do
        def encode(%{unquote_splicing(kv)}) do
          TomlElixir.Encoder.encode(%{unquote_splicing(kv)})
        end

        def project(%{unquote_splicing(kv)}) do
          %{unquote_splicing(kv)}
        end
      end
    end
  end

  defp fields_to_encode(fields, opts) do
    cond do
      only = Keyword.get(opts, :only) ->
        case only -- fields do
          [] ->
            only

          error_keys ->
            raise ArgumentError,
                  "unknown struct fields #{inspect(error_keys)} specified in :only. Expected one of: " <>
                    "#{inspect(fields -- [:__struct__])}"
        end

      except = Keyword.get(opts, :except) ->
        case except -- fields do
          [] ->
            fields -- [:__struct__ | except]

          error_keys ->
            raise ArgumentError,
                  "unknown struct fields #{inspect(error_keys)} specified in :except. Expected one of: " <>
                    "#{inspect(fields -- [:__struct__])}"
        end

      true ->
        fields -- [:__struct__]
    end
  end

  @doc "Encodes a value to TOML value format (inline)."
  def encode(value)

  @doc false
  def project(value)
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

  def project_undefined!(value) do
    raise Protocol.UndefinedError, protocol: TomlElixir.Encoder, value: value
  end
end

defimpl TomlElixir.Encoder, for: Integer do
  alias TomlElixir.Encoder.Helpers

  def encode(v), do: Integer.to_string(v)
  def project(v), do: Helpers.project_undefined!(v)
end

defimpl TomlElixir.Encoder, for: Float do
  alias TomlElixir.Encoder.Helpers

  def encode(f) do
    # TOML requires a fractional part or exponent
    str = Float.to_string(f)

    if String.contains?(str, ".") or String.contains?(str, "e") do
      str
    else
      str <> ".0"
    end
  end

  def project(f), do: Helpers.project_undefined!(f)
end

defimpl TomlElixir.Encoder, for: BitString do
  alias TomlElixir.Encoder.Helpers

  def encode(v), do: "\"" <> Helpers.escape_string(v) <> "\""
  def project(v), do: Helpers.project_undefined!(v)
end

defimpl TomlElixir.Encoder, for: Atom do
  alias TomlElixir.Encoder.Helpers

  def encode(true), do: "true"
  def encode(false), do: "false"
  def encode(:infinity), do: "inf"
  def encode(:neg_infinity), do: "-inf"
  def encode(:nan), do: "nan"
  def encode(nil), do: raise("nil is not supported in TOML")
  def encode(atom), do: TomlElixir.Encoder.encode(Atom.to_string(atom))
  def project(atom), do: Helpers.project_undefined!(atom)
end

defimpl TomlElixir.Encoder, for: List do
  alias TomlElixir.Encoder.Helpers

  def encode(list) do
    "[" <> Enum.map_join(list, ", ", &TomlElixir.Encoder.encode/1) <> "]"
  end

  def project(list), do: Helpers.project_undefined!(list)
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

  def project(map), do: map
end

defimpl TomlElixir.Encoder, for: DateTime do
  alias TomlElixir.Encoder.Helpers

  def encode(dt), do: DateTime.to_iso8601(dt)
  def project(dt), do: Helpers.project_undefined!(dt)
end

defimpl TomlElixir.Encoder, for: NaiveDateTime do
  alias TomlElixir.Encoder.Helpers

  def encode(dt), do: NaiveDateTime.to_iso8601(dt)
  def project(dt), do: Helpers.project_undefined!(dt)
end

defimpl TomlElixir.Encoder, for: Date do
  alias TomlElixir.Encoder.Helpers

  def encode(dt), do: Date.to_iso8601(dt)
  def project(dt), do: Helpers.project_undefined!(dt)
end

defimpl TomlElixir.Encoder, for: Time do
  alias TomlElixir.Encoder.Helpers

  def encode(dt), do: Time.to_iso8601(dt)
  def project(dt), do: Helpers.project_undefined!(dt)
end

defimpl TomlElixir.Encoder, for: Any do
  alias TomlElixir.Encoder.Helpers

  def encode(struct) do
    if is_struct(struct) do
      case struct_impl_for(struct.__struct__, :encode, 1) do
        {:ok, impl} ->
          impl.encode(struct)

        :error ->
          struct
          |> Map.from_struct()
          |> TomlElixir.Encoder.encode()
      end
    else
      raise Protocol.UndefinedError, protocol: TomlElixir.Encoder, value: struct
    end
  end

  def project(struct) do
    if is_struct(struct) do
      case struct_impl_for(struct.__struct__, :project, 1) do
        {:ok, impl} ->
          impl.project(struct)

        :error ->
          Map.from_struct(struct)
      end
    else
      Helpers.project_undefined!(struct)
    end
  end

  defp struct_impl_for(struct_module, fun, arity) do
    impl = Protocol.__concat__(TomlElixir.Encoder, struct_module)

    if impl != __MODULE__ and Code.ensure_loaded?(impl) and function_exported?(impl, fun, arity) do
      {:ok, impl}
    else
      :error
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
    map = TomlElixir.Encoder.project(data)

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
