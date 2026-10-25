defmodule TomlElixir.Parser do
  @moduledoc """
  TOML parser entry point.
  """

  alias TomlElixir.Parser.Document
  alias TomlElixir.Parser.Error

  @type options :: map | keyword

  @bom <<0xEF, 0xBB, 0xBF>>

  @spec decode(binary, options) :: {:ok, map} | {:error, Exception.t()}
  def decode(str, opts \\ []) when is_binary(str) do
    # Only the document prefix is an encoding signature; other U+FEFF characters
    # are content whose validity depends on the surrounding TOML syntax.
    {input, prefix_size} =
      case str do
        <<@bom, rest::binary>> -> {rest, byte_size(@bom)}
        _ -> {str, 0}
      end

    try do
      validate_utf8!(input)
      spec = Keyword.get(opts, :spec, :"1.1.0")
      {:ok, Document.decode(input, spec)}
    rescue
      exception in Error -> {:error, Error.locate(exception, input, prefix_size)}
    end
  end

  defp validate_utf8!(input) do
    case :unicode.characters_to_binary(input) do
      valid when is_binary(valid) -> :ok
      {_error, valid, _rest} -> Error.raise("Invalid UTF-8", byte_size(valid))
    end
  end
end
