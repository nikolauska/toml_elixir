defmodule TomlElixir.Validator do
  @moduledoc """
  Parse and validate toml returned by parse
  """
  alias TomlElixir.Error

  @doc """
  Validate toml and parse it to proper format
  """
  @spec validate(list) :: list
  def validate([]), do: []
  def validate([{:table, to} | tail]) do
    [{:table, Enum.map(to, &to_string(&1))} | validate(tail)]
  end
  def validate([{:array_table, to} | tail]) do
    [{:array_table, Enum.map(to, &to_string(&1))} | validate(tail)]
  end
  def validate([{{:key, key}, {:array, values}} | tail]) do
    [{{:key, to_string(key)}, {:array, array(values)}} | validate(tail)]
  end
  def validate([{{:key, key}, {:datetime, dt, tz}} | tail]) do
    [{{:key, to_string(key)}, {:datetime, datetime(dt, tz)}} | validate(tail)]
  end
  def validate([{{:key, key}, {:datetime, dt}} | tail]) do
    [{{:key, to_string(key)}, {:datetime, datetime(dt, "")}} | validate(tail)]
  end
  def validate([{{:key, key}, {:date, val}} | tail]) do
    [{{:key, to_string(key)}, {:date, date(val)}} | validate(tail)]
  end
  def validate([{{:key, key}, {:time, val}} | tail]) do
    [{{:key, to_string(key)}, {:time, time(val)}} | validate(tail)]
  end
  def validate([{{:key, key}, {:string, value}} | tail]) do
    [{{:key, to_string(key)}, {:string, "#{value}"}} | validate(tail)]
  end
  def validate([{{:key, key}, {:string_ml, value}} | tail]) do
    [{{:key, to_string(key)}, {:string_ml, "#{value}"}} | validate(tail)]
  end
  def validate([{{:key, key}, {:literal, value}} | tail]) do
    [{{:key, to_string(key)}, {:literal, "#{value}"}} | validate(tail)]
  end
  def validate([{{:key, key}, {:literal_ml, value}} | tail]) do
    [{{:key, to_string(key)}, {:literal_ml, "#{value}"}} | validate(tail)]
  end
  def validate([{{:key, key}, {_, value}} | tail]) do
    [{{:key, to_string(key)}, value} | validate(tail)]
  end

  @spec array(list) :: list
  @spec array(list, atom) :: list
  defp array([]), do: []
  defp array(values = [{:string_ml, _} | _tail]), do: array(values, :string)
  defp array(values = [{:literal, _} | _tail]), do: array(values, :string)
  defp array(values = [{:literal_ml, _} | _tail]), do: array(values, :string)
  defp array(values = [{type, _, _} | _tail]), do: array(values, type)
  defp array(values = [{type, _} | _tail]), do: array(values, type)
  defp array([], _type), do: []
  defp array([{:array, values} | tail], :array) do
    [array(values) | array(tail, :array)]
  end
  defp array([{:datetime, dt, suffix} | tail], :datetime) do
    [datetime(dt, suffix) | array(tail, :datetime)]
  end
  defp array([{:datetime, dt} | tail], :datetime) do
    [datetime(dt, "") | array(tail, :datetime)]
  end
  defp array([{:date, val} | tail], :date) do
    [date(val) | array(tail, :date)]
  end
  defp array([{:time, val} | tail], :time) do
    [time(val) | array(tail, :time)]
  end
  defp array([{:string, value} | tail], :string) do
    [to_string(value) | array(tail, :string)]
  end
  defp array([{:string_ml, value} | tail], :string) do
    [to_string(value) | array(tail, :string)]
  end
  defp array([{:literal, value} | tail], :string) do
    [to_string(value) | array(tail, :string)]
  end
  defp array([{:literal_ml, value} | tail], :string) do
    [to_string(value) | array(tail, :string)]
  end
  defp array([{:integer, value} | tail], :integer) do
    [value | array(tail, :integer)]
  end
  defp array([{:float, value} | tail], :float) do
    [value | array(tail, :float)]
  end
  defp array([{:boolean, value} | tail], :boolean) do
    [value | array(tail, :boolean)]
  end
  defp array([{found, _, _} | _tail], type) do
    throw Error.exception("Array value should be #{type}, found #{found}")
  end
  defp array([{found, _} | _tail], type) do
    throw Error.exception("Array value should be #{type}, found #{found}")
  end

  @spec datetime(:calendar.datetime, binary) :: String.t
  defp datetime(dt, suffix) do
    dt = NaiveDateTime.from_erl!(dt)
    NaiveDateTime.to_iso8601(dt) <> to_string(suffix)
  end

  defp date(val) do
    to_string(Date.from_erl!(val))
  end

  defp time({val, offset}) do
    time(val) <> "." <> to_string(offset)
  end
  defp time(val) do
    to_string(Time.from_erl!(val))
  end
end
