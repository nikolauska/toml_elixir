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
  TomlElixir is used by calling decode functions

  * `TomlElixir.decode/2`
  * `TomlElixir.decode!/2`
  """

  @type options :: map | keyword

  @doc """
  Decode toml string to map.

  ## Options
    * `:spec` - The TOML specification version to follow. Can be `:"1.1.0"` (default) or `:"1.0.0"`.

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
end
