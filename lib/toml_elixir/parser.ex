defmodule TomlElixir.Parser do
  @moduledoc """
  TOML parser entry point.
  """

  alias TomlElixir.Parser.Document
  alias TomlElixir.Parser.Error

  @type options :: map | keyword

  @spec decode(binary, options) :: {:ok, map} | {:error, Exception.t()}
  def decode(str, opts \\ []) when is_binary(str) do
    str = normalize_input(str)
    spec = Keyword.get(opts, :spec, :"1.1.0")
    {:ok, Document.decode(str, spec)}
  rescue
    exception in Error -> {:error, exception}
  end

  defp normalize_input(str) do
    str =
      case :unicode.characters_to_binary(str) do
        valid when is_binary(valid) -> valid
        _ -> Error.raise("Invalid UTF-8")
      end

    # Only the document prefix is an encoding signature; other U+FEFF characters
    # are content whose validity depends on the surrounding TOML syntax.
    String.replace_prefix(str, <<0xEF, 0xBB, 0xBF>>, "")
  end
end
