defmodule TomlElixir.Decoder do
  @moduledoc """
  Module for decoding TOML file to map format
  """
  alias TomlElixir.{Validator, Mapper, Error}

  @doc """
  Decode TOML string to map format
  """
  @spec decode(String.t, TomlElixir.options) :: {:ok, map} | {:error, Exception.t}
  def decode(str, _opts) do
    str = add_newline(str)
    with {:ok, tokens} <- lexer(str),
         {:ok, list} <- parser(tokens)
    do
      toml =
        list
        |> Validator.validate()
        |> Mapper.to_map()
      {:ok, toml}
    end
  catch
    exception ->
      {:error, exception}
  end

  # Tokenizer fails if there are no newline
  # If there is none add one to end
  @spec add_newline(String.t) :: String.t
  defp add_newline(str) do
    if String.contains?(str, "\n") do
      str
    else
      str <> "\n"
    end
  end

  # Tokenize toml file
  @spec lexer(binary) :: {:ok, list} | {:error, String.t}
  defp lexer(str) when is_binary(str) do
    str
    |> to_charlist()
    |> :toml_lexer.string()
    |> erl_result()
  end

  # Parse tokens to tuples
  @spec parser(list) :: {:ok, list} | {:error, String.t}
  defp parser(tokens) when is_list(tokens) do
    tokens
    |> :toml_parser.parse()
    |> erl_result()
  end

  # Parses errors from lexer or parser
  @spec erl_result({:ok, [any], any} | {:ok, [any]} |
                    {:error, {number, any, binary}} |
                    {:error, {number, any, {atom, binary}, any}}) ::
                    {:ok, [any]} | {:error, String.t}
  defp erl_result({:ok, tokens, _}), do: {:ok, tokens}
  defp erl_result({:ok, list}), do: {:ok, list}
  defp erl_result({:error, {_line, _, err}}), do: {:error, Error.exception(err)}
  defp erl_result({:error, {_line, _, {err, _msg}}, _}), do: {:error, Error.exception(err)}
end
