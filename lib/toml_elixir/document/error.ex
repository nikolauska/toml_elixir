defmodule TomlElixir.Document.Error do
  @moduledoc """
  Exception returned or raised when a `TomlElixir.Document` edit fails.

    * `:reason` - why the edit failed.
    * `:path` - the key path passed to the edit, as strings with integer indexes.
  """

  alias TomlElixir.KeyPath

  defexception reason: "Unknown error", path: []

  @type t :: %__MODULE__{reason: String.t(), path: [String.t() | non_neg_integer]}

  @spec message(t) :: String.t()
  def message(%__MODULE__{reason: reason, path: path}), do: KeyPath.prefix_message(reason, path)
end
