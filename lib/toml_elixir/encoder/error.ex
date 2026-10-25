defmodule TomlElixir.Encoder.Error do
  @moduledoc """
  Exception returned or raised when a value cannot be encoded to TOML.

    * `:reason` - message of the underlying failure.
    * `:path` - keys leading to the failing value, as strings, with integer indexes for
      array elements. An empty list means the failure happened at the top level.
  """

  alias TomlElixir.KeyPath

  defexception reason: "Unknown error", path: []

  @type t :: %__MODULE__{reason: String.t(), path: [String.t() | non_neg_integer]}

  @spec message(t) :: String.t()
  def message(%__MODULE__{reason: reason, path: path}), do: KeyPath.prefix_message(reason, path)
end
