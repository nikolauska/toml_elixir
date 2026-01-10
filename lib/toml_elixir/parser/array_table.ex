defmodule TomlElixir.Parser.ArrayTable do
  @moduledoc false

  defstruct items: []

  @type t :: %__MODULE__{items: list}

  def new, do: %__MODULE__{items: []}

  def to_list(%__MODULE__{items: items}), do: items
end
