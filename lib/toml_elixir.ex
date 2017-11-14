defmodule TomlElixir do
  @moduledoc """
  # TomlElixir

  [TOML](https://github.com/toml-lang/toml) parser for elixir.

  ## Installation

  The package can be installed by adding `toml_elixir` to your list of
  dependencies in `mix.exs`:

  ```elixir
  def deps do
    [{:toml_elixir, "~> 1.1.0"}]
  end
  ```

  ## Usage
  TomlElixir is used by calling parse functions

  * `TomlElixir.parse/2`
  * `TomlElixir.parse!/2`
  * `TomlElixir.parse_file/2`
  * `TomlElixir.parse_file!/2`
  """
  alias TomlElixir.Mapper

  @typedoc """
  Toml value is a tuple with type and actual value
  """
  @type toml_value :: {:string, binary} |
                      {:datetime, tuple} |
                      {:number, number} |
                      {:boolean, boolean}

  @typedoc """
  Toml ident is same as value tuple but this means identifier or key
  """
  @type toml_ident :: {:identifier, binary}

  @typedoc """
  Toml key value means tuple with toml identifier and value

  ## Example

  Toml:
  ```toml
  key = value
  ```

  Tuple:
  ```
  {{:identifier, "key"}, {:string, "value"}}
  ```

  Map:
  ```
  %{"key" => "val"}
  ```
  """
  @type toml_key_val :: {toml_ident, toml_value}

  @typedoc """
  Toml group means list of values

  First list is list of identifiers which point to place in map

  ## Example

  Toml:
  ```toml
  [key]
  example = ["value", true]
  ```

  Tuple:
  ```
  {:group,
    [{:identifier, "key"}, {:identifier, "example"}],
    [{:string, "value"}, {:boolean, true}]}
  ```

  Map:
  ```
  %{
    "key" => %{
      "example" => ["value", true]
    }
  }
  ```
  """
  @type toml_group :: {:group, [toml_ident], [toml_key_val]}

  @typedoc """
  Multi is same as group but with difference that it's a list of maps

  ## Example

  Toml:
  ```toml
  [[key]]
  example1 = val1

  [[key]]
  example2 = val2
  ```

  Tuple:
  ```
  [
    {:multi,
      [{:identifier, "key"}, {:identifier, "example1"}],
      [{:string, "val1"}]},
    {:multi,
      [{:identifier, "key"}, {:identifier, "example2"}],
      [{:string, "val2"}]},
  ]
  ```

  Map:
  ```
  %{
    "key" => [
      %{"example1" => "val1"},
      %{"example2" => "val2"},
    ]
  }
  ```
  """
  @type toml_multi :: {:multi, [toml_ident], [toml_key_val]}

  @typedoc """
  Toml return is just list of any toml types
  """
  @type toml_return :: [toml_key_val | toml_multi | toml_group] | []

  @type options :: [to_map: boolean]

  @type result :: map | toml_return

  @doc """
  Parse toml string to map or return toml tuple list.

  ## Example
  ```
  TomlElixir.parse("toml = true")
  ```
  """
  @spec parse(binary, options) :: {:ok, result} | {:error, String.t}
  def parse(str, opts \\ []) when is_binary(str) do
    with {:ok, tokens} <- lexer(str),
         {:ok, list} <- parser(tokens)
    do
      if to_map?(opts) do
        {:ok, Mapper.parse(list)}
      else
        {:ok, list}
      end
    end
  end

  @doc """
  Same as `parse/2`, but raises error on failure

  ## Example
  ```
  TomlElixir.parse!("toml = true")
  ```
  """
  @spec parse!(binary, options) :: result
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
  @spec parse_file(binary, options) :: {:ok, result} | {:error, String.t}
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
  @spec parse_file!(binary, options) :: result
  def parse_file!(path, opts \\ []) do
    case parse_file(path, opts) do
      {:ok, toml} -> toml
      {:error, err} -> raise err
    end
  end

  # Check if we skip parsing to map
  @spec to_map?(keyword) :: boolean
  defp to_map?(opts) do
    cond do
      Keyword.get(opts, :no_parse) == true ->
        IO.puts("TomlElixir: no_parse option is deprecated, " <>
                "please use new to_map: false option")
        false

      Keyword.get(opts, :to_map) == false ->
        false

      true ->
        true
    end
  end

  # Tokenize toml file
  @spec lexer(binary) :: {:ok, list} | {:error, String.t}
  defp lexer(str) when is_binary(str) do
    str
    |> to_charlist()
    |> :toml_lexer.string()
    |> erl_result_parse()
  end

  # Parse tokens to tuples
  @spec parser(list) :: {:ok, list} | {:error, String.t}
  defp parser(tokens) when is_list(tokens) do
    tokens
    |> :toml_parser.parse()
    |> erl_result_parse()
  end

  # Parses errors from lexer or parser
  @spec erl_result_parse({:ok, [any], any} | {:ok, [any]} |
                         {:error, {number, any, binary}} |
                         {:error, {number, any, {atom, binary}, any}}) ::
                         {:ok, [any]} | {:error, String.t}
  defp erl_result_parse({:ok, tokens, _}),
    do: {:ok, tokens}
  defp erl_result_parse({:ok, list}),
    do: {:ok, list}
  defp erl_result_parse({:error, {_line, _, err}}),
    do: {:error, "Error: #{err}"}
  defp erl_result_parse({:error, {_line, _, {err, msg}}, _}),
    do: {:error, "#{err} #{msg}"}
end
