defmodule TomlElixir.Error do
  defexception [:reason, :source]

  def exception(reason, source) do
    %__MODULE__{reason: reason, source: source}
  end

  def message(%__MODULE__{reason: reason}) do
    reason
  end
end
