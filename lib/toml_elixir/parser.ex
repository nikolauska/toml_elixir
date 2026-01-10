defmodule TomlElixir.Parser do
  @moduledoc """
  TOML parser entry point.
  """

  alias TomlElixir.Parser.Document
  alias TomlElixir.Parser.Error

  @type options :: map | keyword

  @spec parse(binary, options) :: {:ok, map} | {:error, Exception.t()}
  def parse(str, opts \\ []) when is_binary(str) do
    str = normalize_input(str)
    spec = Keyword.get(opts, :spec, :"1.1.0")
    {:ok, Document.parse(str, spec)}
  rescue
    exception in Error -> {:error, exception}
  end

  defp normalize_input(str) do
    if not String.valid?(str) do
      Error.raise("Invalid UTF-8")
    end

    {str, had_bom?} =
      case str do
        <<0xEF, 0xBB, 0xBF, rest::binary>> -> {rest, true}
        _ -> {str, false}
      end

    if had_bom? and String.contains?(str, <<0xEF, 0xBB, 0xBF>>) do
      Error.raise("BOM must appear only at start of document")
    end

    if not had_bom? and String.contains?(str, <<0xEF, 0xBB, 0xBF>>) do
      Error.raise("BOM must appear only at start of document")
    end

    str
  end
end
