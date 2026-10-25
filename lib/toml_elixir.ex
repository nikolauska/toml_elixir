defmodule TomlElixir do
  @moduledoc """
  # TomlElixir

  [TOML](https://github.com/toml-lang/toml) parser for elixir.

  ## Installation

  The package can be installed by adding `toml_elixir` to your list of
  dependencies in `mix.exs`:

  ```elixir
  def deps do
    [{:toml_elixir, "~> 3.0.0"}]
  end
  ```

  ## Usage
  TomlElixir is used by calling decode functions

  * `TomlElixir.decode/2`
  * `TomlElixir.decode!/2`
  * `TomlElixir.encode/2`
  * `TomlElixir.encode!/2`
  * `TomlElixir.encode_to_iodata/2`
  * `TomlElixir.encode_to_iodata!/2`
  """

  alias TomlElixir.Encoder.Error
  alias TomlElixir.Encoder.Serializer

  @type options :: map | keyword

  @doc """
  Decode toml string to map.

  ## Options
    * `:spec` - The TOML specification version to follow. Can be `:"1.1.0"` (default) or `:"1.0.0"`.
    * `:keys` - How table keys are returned. Conversion runs after TOML validation, including
      duplicate-key checks, and applies to nested tables, inline tables, and arrays of tables.
      * `:strings` (default) - keep keys as strings.
      * `:atoms!` - convert keys to existing atoms with `String.to_existing_atom/1`. A key with
        no existing atom fails decoding. New atoms are never created, because atoms are not
        garbage-collected; existing atoms are still not an application-specific allowlist.
      * a 1-arity function - called with each string key, returning the key to use. Raise to
        reject a key; `decode/2` then returns an error. Pass an explicit mapping for the
        tightest control, for example `&Map.fetch!(%{"port" => :port}, &1)`.

      Two keys in one table that convert to the same term fail decoding instead of
      overwriting each other. Key conversion errors have no line or column.
    * `:transform` - a 2-arity function called as `transform.(path, value)` for every value
      in the document, returning the value to use. Use it to convert selected strings to
      known values, validate settings, or build structs from tables.
      * Values are visited children first, so a table's callback receives its transformed
        children. The order between sibling keys is unspecified.
      * `path` lists the TOML keys from the document root as strings, with integer indexes
        for array elements, such as `["servers", 0, "port"]`. It uses the original keys
        even when `:keys` converts them; the value's nested maps have converted keys.
      * The callback is not called for the document map itself, so decoding always
        returns a map.
      * Raise to reject a value; `decode/2` then returns an error naming the path, with
        no line or column.

      This runs after decoding, so it cannot recover precision or formatting already lost
      during scalar parsing.

  ## Example
  ```
  TomlElixir.decode("toml = true", spec: :"1.1.0")
  ```
  """
  @spec decode(binary, options) :: {:ok, map} | {:error, Exception.t()}
  def decode(str, opts \\ []) when is_binary(str) do
    TomlElixir.Parser.decode(str, opts)
  end

  @doc """
  Same as `decode/2`, but raises error on failure.

  ## Example
  ```
  TomlElixir.decode!("toml = true")
  ```
  """
  @spec decode!(binary, options) :: map
  def decode!(str, opts \\ []) when is_binary(str) do
    case decode(str, opts) do
      {:ok, map} -> map
      {:error, err} -> raise err
    end
  end

  @doc """
  Encode map to toml string.

  ## Example
  ```
  TomlElixir.encode(%{a: 1})
  ```
  """
  @spec encode(map, options) :: {:ok, binary} | {:error, Error.t()}
  def encode(map, opts \\ []) when is_map(map) do
    with {:ok, iodata} <- encode_to_iodata(map, opts) do
      {:ok, IO.iodata_to_binary(iodata)}
    end
  end

  @doc """
  Same as `encode/2`, but raises error on failure.

  ## Example
  ```
  TomlElixir.encode!(%{a: 1})
  ```
  """
  @spec encode!(map, options) :: binary
  def encode!(map, opts \\ []) when is_map(map) do
    case encode(map, opts) do
      {:ok, str} -> str
      {:error, err} -> raise err
    end
  end

  @doc """
  Encode map to TOML as iodata.

  Use this when the output goes to an API that accepts iodata, such as `File.write/3`
  or `:gen_tcp.send/2`, to skip building one contiguous binary. The whole output is
  still built in memory; this is not streaming encoding.

  ## Example
  ```
  {:ok, iodata} = TomlElixir.encode_to_iodata(%{a: 1})
  File.write!("config.toml", iodata)
  ```
  """
  @spec encode_to_iodata(map, options) :: {:ok, iodata} | {:error, Error.t()}
  def encode_to_iodata(map, opts \\ []) when is_map(map) do
    Serializer.encode_to_iodata(map, opts)
  end

  @doc """
  Same as `encode_to_iodata/2`, but raises error on failure.

  ## Example
  ```
  TomlElixir.encode_to_iodata!(%{a: 1})
  ```
  """
  @spec encode_to_iodata!(map, options) :: iodata
  def encode_to_iodata!(map, opts \\ []) when is_map(map) do
    case encode_to_iodata(map, opts) do
      {:ok, iodata} -> iodata
      {:error, err} -> raise err
    end
  end
end
