defmodule TomlElixir.Parser.Table do
  @moduledoc false

  alias TomlElixir.Parser.ArrayTable

  defstruct data: %{}, inline?: false, explicit?: false, dotted?: false, frozen?: false

  @type t :: %__MODULE__{data: map, inline?: boolean, explicit?: boolean, dotted?: boolean}

  @spec new(keyword) :: t
  def new(opts \\ []) do
    %__MODULE__{
      data: %{},
      inline?: Keyword.get(opts, :inline?, false),
      explicit?: Keyword.get(opts, :explicit?, false),
      dotted?: Keyword.get(opts, :dotted?, false)
    }
  end

  def freeze(%__MODULE__{} = table), do: %{table | frozen?: true}

  @spec to_map(t) :: map
  def to_map(%__MODULE__{data: data}) do
    Enum.reduce(data, %{}, fn {key, value}, acc ->
      Map.put(acc, key, normalize_value(value))
    end)
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
