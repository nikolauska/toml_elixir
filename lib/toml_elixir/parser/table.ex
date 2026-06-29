defmodule TomlElixir.Parser.Table do
  @moduledoc false

  alias TomlElixir.Parser.ArrayTable

  defstruct data: %{}, inline?: false, explicit?: false, dotted?: false, frozen?: false

  @type t :: %__MODULE__{data: map, inline?: boolean, explicit?: boolean, dotted?: boolean}

  @spec new(boolean, boolean, boolean) :: t
  def new(inline? \\ false, explicit? \\ false, dotted? \\ false) do
    %__MODULE__{
      data: %{},
      inline?: inline?,
      explicit?: explicit?,
      dotted?: dotted?
    }
  end

  def freeze(%__MODULE__{} = table), do: %{table | frozen?: true}

  @spec to_map(t) :: map
  def to_map(%__MODULE__{data: data}) do
    Map.new(data, fn {key, value} -> {key, normalize_value(value)} end)
  end

  defp normalize_value(%__MODULE__{} = table), do: to_map(table)

  defp normalize_value(%ArrayTable{} = array_table) do
    array_table
    |> ArrayTable.to_list()
    |> Enum.map(&normalize_value/1)
  end

  defp normalize_value(list) when is_list(list), do: Enum.map(list, &normalize_value/1)
  defp normalize_value(value), do: value
end
