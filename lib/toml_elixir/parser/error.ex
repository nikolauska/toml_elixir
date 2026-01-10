defmodule TomlElixir.Parser.Error do
  @moduledoc """
  Exception raised during TOML parsing.
  """

  defexception [:reason]

  @spec exception(String.t()) :: Exception.t()
  def exception(reason) when is_binary(reason) do
    %__MODULE__{reason: reason}
  end

  def exception(opts) when is_list(opts) do
    %__MODULE__{reason: Keyword.get(opts, :reason, "Unknown error")}
  end

  @spec message(Exception.t()) :: String.t()
  def message(%__MODULE__{reason: reason}), do: reason

  @spec raise(String.t()) :: no_return()
  def raise(reason) do
    raise(__MODULE__, reason: reason)
  end
end
