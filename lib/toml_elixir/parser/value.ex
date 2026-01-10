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
    case parse_datetime(token, spec) do
      {:ok, value} ->
        value

      :error ->
        case parse_float(token, spec) do
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

  defp parse_integer(token) do
    sign = if String.starts_with?(token, "-") or String.starts_with?(token, "+"), do: String.first(token), else: ""
    rest = if sign == "", do: token, else: String.slice(token, 1..-1//1)

    {base, digits} =
      cond do
        String.starts_with?(rest, "0x") -> {16, String.slice(rest, 2..-1//1)}
        String.starts_with?(rest, "0o") -> {8, String.slice(rest, 2..-1//1)}
        String.starts_with?(rest, "0b") -> {2, String.slice(rest, 2..-1//1)}
        true -> {10, rest}
      end

    if sign != "" and base != 10 do
      :error
    else
      with :ok <- validate_underscores(digits),
           :ok <- validate_digits(digits, base),
           :ok <- validate_leading_zero(digits, base),
           {int, ""} <- Integer.parse(String.replace(digits, "_", ""), base) do
        value = if sign == "-", do: -int, else: int
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
    # Regex captures:
    # 1. sign
    # 2. integer part
    # 3. fractional part (optional)
    # 4. exponent sign (optional)
    # 5. exponent digits (optional)
    regex =
      ~r/\A(?<sign>[+-]?)(?<int>0|[1-9][0-9_]*)(?:\.(?<frac>[0-9_]+))?(?:[eE](?<exp_sign>[+-]?)(?<exp>[0-9_]+))?\z/

    case Regex.named_captures(regex, token) do
      %{"sign" => _sign, "int" => int, "frac" => frac, "exp_sign" => _exp_sign, "exp" => exp} ->
        # Regex.named_captures returns "" for unmatched groups
        frac = if frac == "", do: nil, else: frac
        exp = if exp == "", do: nil, else: exp

        has_exp = exp != nil
        has_frac = frac != nil

        if not has_exp and not has_frac do
          :error
        else
          with :ok <- validate_underscores(int),
               :ok <- validate_underscores(frac || ""),
               :ok <- validate_underscores(exp || ""),
               :ok <- validate_leading_zero(int, 10) do
            value = token |> String.replace("_", "") |> Float.parse()

            case value do
              {float, ""} -> {:ok, float}
              _ -> :error
            end
          else
            _ -> :error
          end
        end

      nil ->
        :error
    end
  end

  defp parse_datetime(token, spec) do
    cond do
      captures =
          Regex.named_captures(
            if(spec == :"1.1.0",
              do:
                ~r/\A(?<date>\d{4}-\d{2}-\d{2})[Tt ](?<time>\d{2}:\d{2}(?::\d{2}(?:\.\d+)?)?)(?<offset>Z|z|[+-]\d{2}:\d{2})\z/,
              else:
                ~r/\A(?<date>\d{4}-\d{2}-\d{2})[Tt ](?<time>\d{2}:\d{2}:\d{2}(?:\.\d+)?)(?<offset>Z|z|[+-]\d{2}:\d{2})\z/
            ),
            token
          ) ->
        %{"date" => date, "time" => time, "offset" => offset} = captures

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
          Regex.named_captures(
            if(spec == :"1.1.0",
              do: ~r/\A(?<date>\d{4}-\d{2}-\d{2})[Tt ](?<time>\d{2}:\d{2}(?::\d{2}(?:\.\d+)?)?)\z/,
              else: ~r/\A(?<date>\d{4}-\d{2}-\d{2})[Tt ](?<time>\d{2}:\d{2}:\d{2}(?:\.\d+)?)\z/
            ),
            token
          ) ->
        %{"date" => date, "time" => time} = captures

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
    regex =
      if spec == :"1.1.0" do
        ~r/\A(?<hour>\d{2}):(?<minute>\d{2})(?::(?<second>\d{2})(?:\.(?<fraction>\d+))?)?\z/
      else
        ~r/\A(?<hour>\d{2}):(?<minute>\d{2}):(?<second>\d{2})(?:\.(?<fraction>\d+))?\z/
      end

    case Regex.named_captures(regex, time) do
      %{"hour" => hour, "minute" => minute, "second" => second, "fraction" => fraction} ->
        second = if second == "", do: "00", else: second

        case validate_time(hour, minute, second) do
          :ok ->
            base_time = "#{hour}:#{minute}:#{second}"

            time =
              cond do
                fraction == "" ->
                  base_time

                spec == :"1.0.0" ->
                  base_time <> "." <> String.pad_trailing(fraction, 3, "0")

                true ->
                  base_time <> "." <> fraction
              end

            {:ok, time}

          _ ->
            :error
        end

      nil ->
        :error
    end
  end

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

  defp validate_date(date) do
    [year, month, day] = date |> String.split("-") |> Enum.map(&String.to_integer/1)

    case Date.new(year, month, day) do
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
    cleaned = String.replace(digits, "_", "")

    if String.length(cleaned) > 1 and String.starts_with?(cleaned, "0") do
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

  defp validate_digits(digits, base) do
    digits
    |> String.replace("_", "")
    |> String.to_charlist()
    |> Enum.all?(fn digit ->
      cond do
        digit >= ?0 and digit <= ?9 -> digit - ?0 < base
        digit >= ?a and digit <= ?f -> base == 16
        digit >= ?A and digit <= ?F -> base == 16
        true -> false
      end
    end)
    |> case do
      true -> :ok
      false -> :error
    end
  end
end
