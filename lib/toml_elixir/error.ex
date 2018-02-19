defmodule TomlElixir.Error do
  @moduledoc """
  TomlElixir exception module
  """
  defexception [:reason]

  @doc """
  Generate TomlElixir.Error exception
  """
  @spec exception(any) :: Exception.t
  def exception(reason) do
    %__MODULE__{reason: reason}
  end

  @doc """
  Return error reason from TomlElixir.Error exception
  """
  @spec message(Exception.t) :: String.t
  def message(%__MODULE__{reason: reason}) do
    reason
  end
end
