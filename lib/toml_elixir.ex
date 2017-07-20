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
  """
  @spec parse(binary, options) :: {:ok, result} | {:error, String.t}
  def parse(str, opts \\ []) when is_binary(str) do
    with {:ok, tokens} <- lexer(str),
         {:ok, list} <- parser(tokens)
    do
      if to_map?(opts) do
        {:ok, to_map(list)}
      else
        {:ok, list}
      end
    end
  end

  @doc """
  Same as `parse/2`, but raises error on failure
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
        IO.puts("#{__MODULE__}: no_parse option is deprecated, " <>
                "please use new to_map: false option")
        false
      Keyword.get(opts, :to_map) == false -> false
      true -> true
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
  defp erl_result_parse({:error, {line, _, err}}),
    do: {:error, "Error on line #{line}: #{err}"}
  defp erl_result_parse({:error, {line, _, {err, msg}}, _}),
    do: {:error, "Error on line #{line}: #{err} #{msg}"}

  # Turn toml tuple list to map
  @spec to_map(toml_return) :: map
  @spec to_map(toml_return, [] | [any] | map) :: map
  defp to_map(val),
    do: to_map(val, %{})
  defp to_map(val, []),
    do: [to_map(val, %{})]
  defp to_map(val, list) when is_list(list),
    do: List.update_at(list, -1, &(to_map(val, &1)))
  defp to_map([{:group, idents, values} | tail], map),
    do: to_map(tail, group(idents, values, map))
  defp to_map([{:multi, idents, values} | tail], map),
    do: to_map(tail, multi(idents, values, map))
  defp to_map([{{:identifier, key}, values} | tail], map) when is_list(values),
    do: to_map(tail, put(map, key, value(values)))
  defp to_map([{{:identifier, key}, val} | tail], map),
    do: to_map(tail, put(map, key, value(val)))
  defp to_map([], map),
    do: map

  # Turn group tuple to map
  @spec group([toml_ident], [toml_key_val], [any] | map) :: map | [any]
  defp group(idents, values, []),
    do: [group(idents, values, %{})]
  defp group(idents, values, list) when is_list(list),
    do: List.update_at(list, -1, &group(idents, values, &1))
  defp group([{:identifier, key} | tail], values, map),
    do: put(map, key, group(tail, values, get(map, key, %{})))
  defp group([], values, map),
    do: to_map(values, map)

  # Turn multi tuple to map
  @spec multi([toml_ident], [toml_key_val], map) :: map
  defp multi([{:identifier, key} | []], values, map),
    do: put(map, key, to_map(values, insert_end(map, key, %{})))
  defp multi([{:identifier, key} | tail], values, map),
    do: put(map, key, multi(tail, values, get(map, key, %{})))

  # Parse value from toml value tuple
  @spec value(toml_value | [toml_value]) :: any
  defp value([]), do: []
  defp value([head | tail]), do: [value(head) | value(tail)]
  defp value({:string, val}), do: "#{val}"
  defp value({:datetime, val}), do: val
  defp value({:number, val}), do: val
  defp value({:boolean, val}), do: val

  # Add value to end of the list
  @spec insert_end(map, binary, any) :: [map]
  defp insert_end(map, key, value),
    do: List.insert_at(get(map, key, []), -1, value)

  # Get value from map
  @spec get(map, binary, any) :: any
  defp get(map, key, default),
    do: Map.get(map, "#{key}", default)

  # Put value to map
  @spec put(map, binary, any) :: map
  defp put(map, key, value),
    do: Map.put(map, "#{key}", value)
end
