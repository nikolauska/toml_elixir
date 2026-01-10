defmodule TomlElixir.SpecCase do
  @moduledoc false
  use ExUnit.CaseTemplate

  using do
    quote do
      import TomlElixir.SpecCase
    end
  end

  def normalize_for_test(val) when is_map(val) do
    cond do
      Map.has_key?(val, :__struct__) and val.__struct__ in [DateTime, NaiveDateTime, Time] ->
        %{val | microsecond: {elem(val.microsecond, 0), 6}}

      Map.has_key?(val, :__struct__) ->
        val

      Map.has_key?(val, "type") and Map.has_key?(val, "value") and map_size(val) == 2 ->
        val["type"] |> convert_scalar(val["value"]) |> normalize_for_test()

      true ->
        Map.new(val, fn {k, v} -> {k, normalize_for_test(v)} end)
    end
  end

  def normalize_for_test(val) when is_list(val) do
    Enum.map(val, &normalize_for_test/1)
  end

  def normalize_for_test(val), do: val

  def convert_scalar("string", value), do: value
  def convert_scalar("bool", "true"), do: true
  def convert_scalar("bool", "false"), do: false
  def convert_scalar("integer", value), do: String.to_integer(value)

  def convert_scalar("float", value) do
    case value do
      v when v in ["inf", "+inf"] ->
        :infinity

      "-inf" ->
        :neg_infinity

      v when v in ["nan", "+nan", "-nan"] ->
        :nan

      _ ->
        {f, _} = Float.parse(value)
        f
    end
  end

  def convert_scalar("datetime", value), do: value |> DateTime.from_iso8601() |> elem(1)
  def convert_scalar("datetime-local", value), do: NaiveDateTime.from_iso8601!(value)
  def convert_scalar("date-local", value), do: Date.from_iso8601!(value)
  def convert_scalar("time-local", value), do: Time.from_iso8601!(value)
end
