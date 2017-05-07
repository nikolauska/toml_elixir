defmodule TomlElixir do
  @moduledoc """
  # TomlElixir

  [TOML](https://github.com/toml-lang/toml) parser for elixir.

  ## Installation

  The package can be installed by adding `toml_elixir` to your list of
  dependencies in `mix.exs`:

  ```elixir
  def deps do
    [{:toml_elixir, "~> 1.0.0"}]
  end
  ```

  ## Usage
  TomlElixir is used by calling parse functions

  * `TomlElixir.parse/2`
  * `TomlElixir.parse!/2`
  """
  @type toml_value :: {:string, binary} |
                      {:datetime, tuple} |
                      {:number, number} |
                      {:boolean, boolean}
  @type toml_ident :: {:identifier, binary}
  @type toml_key_val :: {toml_ident, toml_value}
  @type toml_group :: {:group, [toml_ident], [toml_key_val]}
  @type toml_multi :: {:multi, [toml_ident], [toml_key_val]}
  @type toml_return :: [toml_key_val | toml_multi | toml_group]

  @type return :: toml_return | Map.t
  @type options :: [no_parse: boolean] | Keyword.t

  @doc """
  Parse toml string to map or return raw list. Return ok/error tuple

  ## Possible options
  - no_parse :: boolean
  """
  @spec parse(binary, options) :: {:ok, return} | {:error, String.t}
  def parse(str, opts \\ []) when is_binary(str) do
    with {:ok, tokens} <- lexer(str),
         {:ok, list} <- parser(tokens)
    do
      if Keyword.get(opts, :no_parse) == true do
        {:ok, list}
      else
        {:ok, to_map(list)}
      end
    end
  end

  @doc """
  Parse toml string to map or return raw list. Raises error on failure

  ## Possible options
  - no_parse :: boolean
  """
  @spec parse!(binary, options) :: return
  def parse!(str, opts \\ []) when is_binary(str) do
    case parse(str, opts) do
      {:ok, map} -> map
      {:error, err} -> raise err
    end
  end

  @spec lexer(binary) :: {:ok, List.t} | {:error, String.t}
  defp lexer(str) when is_binary(str) do
    str
    |> to_charlist()
    |> :toml_lexer.string()
    |> erl_result_parse()
  end

  @spec parser(List.t) :: {:ok, List.t} | {:error, String.t}
  defp parser(tokens) when is_list(tokens) do
    tokens
    |> :toml_parser.parse()
    |> erl_result_parse()
  end

  @spec erl_result_parse({:ok, [term], term} | {:ok, [term]} |
                         {:error, {number, term, binary}} |
                         {:error, {number, term, {atom, binary}, term}}) ::
                         {:ok, [term]} | {:error, String.t}
  defp erl_result_parse({:ok, tokens, _}),
    do: {:ok, tokens}
  defp erl_result_parse({:ok, list}),
    do: {:ok, list}
  defp erl_result_parse({:error, {line, _, err}}),
    do: {:error, "Error on line #{line}: #{err}"}
  defp erl_result_parse({:error, {line, _, {err, msg}}, _}),
    do: {:error, "Error on line #{line}: #{err} #{msg}"}

  @spec to_map(toml_return) :: Map.t
  defp to_map(val),
    do: to_map(val, %{})
  @spec to_map(toml_return, List.t | Map.t) :: List.t | Map.t
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

  @spec group([toml_ident], [toml_key_val], Map.t | List.t) :: Map.t | List.t
  defp group(idents, values, []),
    do: [group(idents, values, %{})]
  defp group(idents, values, list) when is_list(list),
    do: List.update_at(list, -1, &group(idents, values, &1))
  defp group([{:identifier, key} | tail], values, map),
    do: put(map, key, group(tail, values, get(map, key, %{})))
  defp group([], values, map),
    do: to_map(values, map)

  @spec multi([toml_ident], [toml_key_val], Map.t) :: Map.t
  defp multi([{:identifier, key} | []], values, map),
    do: put(map, key, to_map(values, insert_end(map, key, %{})))
  defp multi([{:identifier, key} | tail], values, map),
    do: put(map, key, multi(tail, values, get(map, key, %{})))

  @spec value(toml_value | [toml_value]) :: term
  defp value([head | tail]),
    do: [value(head) | value(tail)]
  defp value([]),
    do: []
  defp value({:string, val}),
    do: "#{val}"
  defp value({:datetime, val}),
    do: val
  defp value({:number, val}),
    do: val
  defp value({:boolean, val}),
    do: val

  @spec insert_end(Map.t, binary, term) :: List.t
  defp insert_end(map, key, value),
    do: List.insert_at(get(map, key, []), -1, value)

  @spec get(Map.t, binary, term) :: Map.t
  defp get(map, key, default),
    do: Map.get(map, "#{key}", default)

  @spec put(Map.t, binary, term) :: Map.t
  defp put(map, key, value),
    do: Map.put(map, "#{key}", value)
end
