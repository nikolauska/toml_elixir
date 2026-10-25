defmodule TomlElixir.KeyPath do
  @moduledoc false

  alias TomlElixir.Encoder.Helpers

  # Paths are rendered with TOML key quoting so keys containing dots or spaces stay
  # unambiguous in error messages.
  @spec format([term]) :: String.t()
  def format([]), do: ""
  def format([key | rest]), do: IO.iodata_to_binary([format_key(key) | Enum.map(rest, &format_segment/1)])

  # Error messages lead with the path because some underlying reasons, like protocol errors,
  # span several lines.
  @spec prefix_message(String.t(), [term]) :: String.t()
  def prefix_message(reason, []), do: reason
  def prefix_message(reason, path), do: "#{format(path)}: #{reason}"

  defp format_segment(index) when is_integer(index), do: "[#{index}]"
  defp format_segment(key), do: [?. | format_key(key)]

  defp format_key(key) when is_binary(key), do: Helpers.encode_key(key)
  defp format_key(key), do: inspect(key)
end
