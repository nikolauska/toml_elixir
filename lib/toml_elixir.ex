defmodule TomlElixir do
  @moduledoc """
  # TomlElixir

  [TOML](https://github.com/toml-lang/toml) parser for elixir.

  ## Installation

  The package can be installed by adding `toml_elixir` to your list of
  dependencies in `mix.exs`:

  ```elixir
  def deps do
    [{:toml_elixir, "~> 2.0.0"}]
  end
  ```

  ## Usage
  TomlElixir is used by calling parse functions

  * `TomlElixir.parse/2`
  * `TomlElixir.parse!/2`
  * `TomlElixir.parse_file/2`
  * `TomlElixir.parse_file!/2`
  """
  alias TomlElixir.Decoder

  @type options :: map | keyword

  @doc """
  Parse toml string to map

  ## Example
  ```
  TomlElixir.parse("toml = true")
  ```
  """
  @spec parse(binary, options) :: {:ok, map} | {:error, String.t}
  def parse(str, opts \\ []) when is_binary(str) do
    Decoder.decode(str, opts)
  end

  @doc """
  Same as `parse/2`, but raises error on failure

  ## Example
  ```
  TomlElixir.parse!("toml = true")
  ```
  """
  @spec parse!(binary, options) :: map
  def parse!(str, opts \\ []) when is_binary(str) do
    case parse(str, opts) do
      {:ok, map} -> map
      {:error, err} -> raise err
    end
  end

  @doc """
  Parse toml file, uses same options as `parse/2`

  ## Example
  ```
  TomlElixir.parse_file("path/to/example.toml")
  ```
  """
  @spec parse_file(binary, options) :: {:ok, map} | {:error, String.t}
  def parse_file(path, opts \\ []) do
    with {:ok, str} <- File.read(path)
    do
      parse(str, opts)
    end
  end

  @doc """
  Same as `parse_file/2`, but raises error on failure

  ## Example
  ```
  TomlElixir.parse_file!("path/to/example.toml")
  ```
  """
  @spec parse_file!(binary, options) :: map
  def parse_file!(path, opts \\ []) do
    src = File.read!(path)
    parse!(src, opts)
  end
end
