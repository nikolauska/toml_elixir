defmodule TomlElixir.Parser.Value do
  @moduledoc false

  alias TomlElixir.Parser.Error
  alias TomlElixir.Parser.Table

  @type toml_value :: map | list | Table.t()

  @spec parse_scalar(String.t(), atom) :: any
  def parse_scalar(token, spec \\ :"1.1.0") do
    cond do
      token == "true" -> true
      token == "false" -> false
      true -> parse_number_or_datetime(token, spec)
    end
  end

  defp parse_number_or_datetime(token, spec) do
    datetime = if datetime_candidate?(token), do: parse_datetime(token, spec), else: :error

    case datetime do
      {:ok, value} ->
        value

      :error ->
        float = if float_candidate?(token), do: parse_float(token, spec), else: :error

        case float do
          {:ok, value} ->
            value

          :error ->
            case parse_integer(token) do
              {:ok, value} -> value
              :error -> Error.raise("Invalid value #{token}")
            end
        end
    end
  end

  defp float_candidate?(token) when token in ["inf", "+inf", "-inf", "nan", "+nan", "-nan"], do: true
  defp float_candidate?(token), do: :binary.match(token, [".", "e", "E"]) != :nomatch

  defp datetime_candidate?(<<_::binary-size(4), ?-, _::binary>>), do: true
  defp datetime_candidate?(<<_::binary-size(2), ?:, _::binary>>), do: true
  defp datetime_candidate?(_token), do: false

  defp parse_integer(token) do
    {sign, rest} =
      case token do
        <<sign, rest::binary>> when sign in [?-, ?+] -> {sign, rest}
        _ -> {nil, token}
      end

    {base, digits} =
      case rest do
        <<"0x", digits::binary>> -> {16, digits}
        <<"0o", digits::binary>> -> {8, digits}
        <<"0b", digits::binary>> -> {2, digits}
        _ -> {10, rest}
      end

    if sign != nil and base != 10 do
      :error
    else
      with :ok <- validate_underscores(digits),
           digits = remove_underscores(digits),
           :ok <- validate_digits(digits, base),
           :ok <- validate_leading_zero(digits, base),
           {int, ""} <- Integer.parse(digits, base) do
        value = if sign == ?-, do: -int, else: int
        {:ok, value}
      else
        _ -> :error
      end
    end
  end

  defp parse_float(token, spec) do
    case parse_special_float(token) do
      {:ok, value} -> {:ok, value}
      :error -> parse_standard_float(token, spec)
    end
  end

  defp parse_special_float(token) do
    case token do
      "inf" -> {:ok, :infinity}
      "+inf" -> {:ok, :infinity}
      "-inf" -> {:ok, :neg_infinity}
      "nan" -> {:ok, :nan}
      "+nan" -> {:ok, :nan}
      "-nan" -> {:ok, :nan}
      _ -> :error
    end
  end

  defp parse_standard_float(token, _spec) do
    regex =
      ~r/\A[+-]?(?:0|[1-9](?:_?[0-9])*)(?:\.[0-9](?:_?[0-9])*)?(?:[eE][+-]?[0-9](?:_?[0-9])*)?\z/

    with true <- Regex.match?(regex, token),
         {float, ""} <- token |> remove_underscores() |> Float.parse() do
      {:ok, float}
    else
      _ -> :error
    end
  end

  defp parse_datetime(token, spec) do
    cond do
      captures =
          Regex.run(
            if(spec == :"1.1.0",
              do: ~r/\A(\d{4}-\d{2}-\d{2})[Tt ](\d{2}:\d{2}(?::\d{2}(?:\.\d+)?)?)(Z|z|[+-]\d{2}:\d{2})\z/,
              else: ~r/\A(\d{4}-\d{2}-\d{2})[Tt ](\d{2}:\d{2}:\d{2}(?:\.\d+)?)(Z|z|[+-]\d{2}:\d{2})\z/
            ),
            token,
            capture: :all_but_first
          ) ->
        [date, time, offset] = captures

        with :ok <- validate_date(date),
             {:ok, time} <- normalize_time(time, spec),
             {:ok, offset} <- normalize_offset(offset) do
          case DateTime.from_iso8601(date <> "T" <> time <> offset) do
            {:ok, dt, _offset} -> {:ok, dt}
            _ -> :error
          end
        else
          _ -> :error
        end

      captures =
          Regex.run(
            if(spec == :"1.1.0",
              do: ~r/\A(\d{4}-\d{2}-\d{2})[Tt ](\d{2}:\d{2}(?::\d{2}(?:\.\d+)?)?)\z/,
              else: ~r/\A(\d{4}-\d{2}-\d{2})[Tt ](\d{2}:\d{2}:\d{2}(?:\.\d+)?)\z/
            ),
            token,
            capture: :all_but_first
          ) ->
        [date, time] = captures

        with :ok <- validate_date(date),
             {:ok, time} <- normalize_time(time, spec) do
          case NaiveDateTime.from_iso8601(date <> "T" <> time) do
            {:ok, ndt} -> {:ok, ndt}
            _ -> :error
          end
        else
          _ -> :error
        end

      Regex.match?(~r/\A\d{4}-\d{2}-\d{2}\z/, token) ->
        case Date.from_iso8601(token) do
          {:ok, date} -> {:ok, date}
          _ -> :error
        end

      Regex.match?(
        if(spec == :"1.1.0",
          do: ~r/\A\d{2}:\d{2}(?::\d{2})?(?:\.\d+)?\z/,
          else: ~r/\A\d{2}:\d{2}:\d{2}(?:\.\d+)?\z/
        ),
        token
      ) ->
        case normalize_time(token, spec) do
          {:ok, time} ->
            case Time.from_iso8601(time) do
              {:ok, t} -> {:ok, t}
              _ -> :error
            end

          _ ->
            :error
        end

      true ->
        :error
    end
  end

  defp normalize_time(time, spec) do
    case time do
      <<hour::binary-size(2), ":", minute::binary-size(2)>> when spec == :"1.1.0" ->
        normalize_time(hour, minute, "00", "", spec)

      <<hour::binary-size(2), ":", minute::binary-size(2), ":", second::binary-size(2)>> ->
        normalize_time(hour, minute, second, "", spec)

      <<hour::binary-size(2), ":", minute::binary-size(2), ":", second::binary-size(2), ".", fraction::binary>> ->
        normalize_time(hour, minute, second, fraction, spec)

      _ ->
        :error
    end
  end

  defp normalize_time(hour, minute, second, fraction, spec) do
    with :ok <- validate_time(hour, minute, second) do
      base_time = "#{hour}:#{minute}:#{second}"

      cond do
        fraction == "" -> {:ok, base_time}
        spec == :"1.0.0" -> {:ok, base_time <> "." <> String.pad_trailing(fraction, 3, "0")}
        true -> {:ok, base_time <> "." <> fraction}
      end
    end
  end

  defp normalize_offset("-00:00"), do: {:ok, "Z"}

  defp normalize_offset(offset) do
    if offset in ["Z", "z"] do
      {:ok, "Z"}
    else
      <<sign::binary-size(1), hour::binary-size(2), ":", minute::binary-size(2)>> = offset

      hour_i = String.to_integer(hour)
      minute_i = String.to_integer(minute)

      if sign in ["+", "-"] and hour_i in 0..23 and minute_i in 0..59 do
        {:ok, sign <> hour <> ":" <> minute}
      else
        :error
      end
    end
  end

  defp remove_underscores(value) do
    if :binary.match(value, "_") == :nomatch, do: value, else: String.replace(value, "_", "")
  end

  defp validate_date(date) do
    <<year::binary-size(4), "-", month::binary-size(2), "-", day::binary-size(2)>> = date

    case Date.new(:erlang.binary_to_integer(year), :erlang.binary_to_integer(month), :erlang.binary_to_integer(day)) do
      {:ok, _date} -> :ok
      _ -> :error
    end
  end

  defp validate_time(hour, minute, second) do
    hour = String.to_integer(hour)
    minute = String.to_integer(minute)
    second = String.to_integer(second)

    if hour in 0..23 and minute in 0..59 and second in 0..60 do
      :ok
    else
      :error
    end
  end

  defp validate_leading_zero(digits, 10) do
    if byte_size(digits) > 1 and String.starts_with?(digits, "0") do
      :error
    else
      :ok
    end
  end

  defp validate_leading_zero(_digits, _base), do: :ok

  defp validate_underscores(""), do: :ok

  defp validate_underscores(digits) do
    cond do
      String.starts_with?(digits, "_") -> :error
      String.ends_with?(digits, "_") -> :error
      String.contains?(digits, "__") -> :error
      true -> :ok
    end
  end

  defp validate_digits(<<digit, rest::binary>>, base) when digit in ?0..?9 and digit - ?0 < base,
    do: validate_digits(rest, base)

  defp validate_digits(<<digit, rest::binary>>, 16) when digit in ?a..?f or digit in ?A..?F, do: validate_digits(rest, 16)

  defp validate_digits("", _base), do: :ok
  defp validate_digits(_digits, _base), do: :error
end
