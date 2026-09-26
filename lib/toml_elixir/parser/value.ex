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
    if plain_decimal?(token) do
      # Plain decimal integers are the most common scalar and already in the form
      # `binary_to_integer/1` accepts, so the general number and datetime checks are skipped.
      :erlang.binary_to_integer(token)
    else
      parse_non_decimal(token, spec)
    end
  end

  defp parse_non_decimal(token, spec) do
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

  # Matches `[+-]?(0|[1-9][0-9]*)`. The checks below use `:binary.at/2` because they run
  # for every scalar token and, unlike binary matching, it does not allocate.
  defp plain_decimal?(token) do
    start = if byte_size(token) > 0 and :binary.at(token, 0) in [?+, ?-], do: 1, else: 0
    digits = byte_size(token) - start

    digits > 0 and (digits == 1 or :binary.at(token, start) != ?0) and all_digits?(token, start)
  end

  defp all_digits?(token, index) when index < byte_size(token) do
    :binary.at(token, index) in ?0..?9 and all_digits?(token, index + 1)
  end

  defp all_digits?(_token, _index), do: true

  defp float_candidate?(token) when token in ["inf", "+inf", "-inf", "nan", "+nan", "-nan"], do: true
  defp float_candidate?(token), do: float_marker?(token, 0)

  defp float_marker?(token, index) when index < byte_size(token) do
    :binary.at(token, index) in [?., ?e, ?E] or float_marker?(token, index + 1)
  end

  defp float_marker?(_token, _index), do: false

  defp datetime_candidate?(token) do
    (byte_size(token) > 4 and :binary.at(token, 4) == ?-) or (byte_size(token) > 2 and :binary.at(token, 2) == ?:)
  end

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
      with {:ok, digits} <- integer_digits(digits),
           :ok <- validate_digits(digits, base),
           :ok <- validate_leading_zero(digits, base),
           false <- digits == "" do
        int = :erlang.binary_to_integer(digits, base)
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
    if valid_float?(token) do
      token |> remove_underscores() |> to_float()
    else
      :error
    end
  end

  # The grammar check above leaves only forms `:erlang.binary_to_float/1` understands,
  # except that it needs a fraction before any exponent.
  defp to_float(number) do
    number =
      case :binary.match(number, ".") do
        :nomatch -> number |> :binary.split(["e", "E"]) |> Enum.join(".0e")
        _ -> number
      end

    {:ok, :erlang.binary_to_float(number)}
  rescue
    # Out-of-range exponents such as `1e400` are rejected like other invalid values.
    ArgumentError -> :error
  end

  # Hand-written form of
  # `\A[+-]?(?:0|[1-9](?:_?[0-9])*)(?:\.[0-9](?:_?[0-9])*)?(?:[eE][+-]?[0-9](?:_?[0-9])*)?\z`,
  # avoiding regex execution for every float token.
  defp valid_float?(<<sign, rest::binary>>) when sign in [?+, ?-], do: valid_unsigned_float?(rest)
  defp valid_float?(token), do: valid_unsigned_float?(token)

  defp valid_unsigned_float?(<<?0, rest::binary>>), do: valid_fraction?(rest)
  defp valid_unsigned_float?(<<digit, rest::binary>>) when digit in ?1..?9, do: rest |> digit_tail() |> valid_fraction?()
  defp valid_unsigned_float?(_token), do: false

  defp valid_fraction?(<<?., digit, rest::binary>>) when digit in ?0..?9, do: rest |> digit_tail() |> valid_exponent?()
  defp valid_fraction?(rest), do: valid_exponent?(rest)

  defp valid_exponent?(<<e, sign, digit, rest::binary>>) when e in [?e, ?E] and sign in [?+, ?-] and digit in ?0..?9,
    do: digit_tail(rest) == ""

  defp valid_exponent?(<<e, digit, rest::binary>>) when e in [?e, ?E] and digit in ?0..?9, do: digit_tail(rest) == ""
  defp valid_exponent?(rest), do: rest == ""

  defp digit_tail(<<?_, digit, rest::binary>>) when digit in ?0..?9, do: digit_tail(rest)
  defp digit_tail(<<digit, rest::binary>>) when digit in ?0..?9, do: digit_tail(rest)
  defp digit_tail(rest), do: rest

  # Datetime shapes are checked with binary patterns instead of regexes: this runs for
  # every date-like token, and regex execution dominated its cost.
  defp parse_datetime(<<date::binary-size(10), separator, rest::binary>>, spec) when separator in [?T, ?t, ?\s] do
    case split_time(rest, spec) do
      {:ok, hour, minute, second, fraction, ""} ->
        with :ok <- validate_date(date),
             {:ok, time} <- normalize_time(hour, minute, second, fraction, spec),
             {:ok, ndt} <- NaiveDateTime.from_iso8601(date <> "T" <> time) do
          {:ok, ndt}
        else
          _ -> :error
        end

      {:ok, hour, minute, second, fraction, offset} ->
        with {:ok, offset} <- normalize_offset(offset),
             :ok <- validate_date(date),
             {:ok, time} <- normalize_time(hour, minute, second, fraction, spec),
             {:ok, dt, _offset} <- DateTime.from_iso8601(date <> "T" <> time <> offset) do
          {:ok, dt}
        else
          _ -> :error
        end

      :error ->
        :error
    end
  end

  defp parse_datetime(<<_::binary-size(4), ?-, _::binary-size(5)>> = token, _spec) do
    case Date.from_iso8601(token) do
      {:ok, date} -> {:ok, date}
      _ -> :error
    end
  end

  defp parse_datetime(token, spec) do
    with {:ok, hour, minute, second, fraction, ""} <- split_time(token, spec),
         {:ok, time} <- normalize_time(hour, minute, second, fraction, spec),
         {:ok, t} <- Time.from_iso8601(time) do
      {:ok, t}
    else
      _ -> :error
    end
  end

  # Splits `HH:MM[:SS[.fraction]]` (seconds required by TOML 1.0.0) from whatever follows it.
  defp split_time(<<h1, h2, ?:, m1, m2, rest::binary>>, spec)
       when h1 in ?0..?9 and h2 in ?0..?9 and m1 in ?0..?9 and m2 in ?0..?9 do
    case rest do
      <<?:, s1, s2, rest::binary>> when s1 in ?0..?9 and s2 in ?0..?9 ->
        split_fraction(<<h1, h2>>, <<m1, m2>>, <<s1, s2>>, rest)

      _ when spec == :"1.1.0" ->
        {:ok, <<h1, h2>>, <<m1, m2>>, "00", "", rest}

      _ ->
        :error
    end
  end

  defp split_time(_token, _spec), do: :error

  defp split_fraction(hour, minute, second, <<?., digits_and_rest::binary>> = rest) do
    case fraction_length(digits_and_rest, 0) do
      0 ->
        {:ok, hour, minute, second, "", rest}

      length ->
        <<fraction::binary-size(^length), rest::binary>> = digits_and_rest
        {:ok, hour, minute, second, fraction, rest}
    end
  end

  defp split_fraction(hour, minute, second, rest), do: {:ok, hour, minute, second, "", rest}

  defp fraction_length(<<d, rest::binary>>, length) when d in ?0..?9, do: fraction_length(rest, length + 1)
  defp fraction_length(_rest, length), do: length

  defp normalize_time(hour, minute, second, fraction, spec) do
    with :ok <- validate_time(hour, minute, second) do
      base_time = hour <> ":" <> minute <> ":" <> second

      cond do
        fraction == "" -> {:ok, base_time}
        spec == :"1.0.0" -> {:ok, base_time <> "." <> String.pad_trailing(fraction, 3, "0")}
        true -> {:ok, base_time <> "." <> fraction}
      end
    end
  end

  defp normalize_offset("-00:00"), do: {:ok, "Z"}
  defp normalize_offset(offset) when offset in ["Z", "z"], do: {:ok, "Z"}

  defp normalize_offset(<<sign, h1, h2, ?:, m1, m2>> = offset)
       when sign in [?+, ?-] and h1 in ?0..?9 and h2 in ?0..?9 and m1 in ?0..?9 and m2 in ?0..?9, do: {:ok, offset}

  defp normalize_offset(_offset), do: :error

  defp remove_underscores(value) do
    if :binary.match(value, "_") == :nomatch, do: value, else: String.replace(value, "_", "")
  end

  defp validate_date(<<y1, y2, y3, y4, ?-, m1, m2, ?-, d1, d2>>)
       when y1 in ?0..?9 and y2 in ?0..?9 and y3 in ?0..?9 and y4 in ?0..?9 and m1 in ?0..?9 and m2 in ?0..?9 and
              d1 in ?0..?9 and d2 in ?0..?9 do
    year = (y1 - ?0) * 1000 + (y2 - ?0) * 100 + (y3 - ?0) * 10 + (y4 - ?0)

    case Date.new(year, (m1 - ?0) * 10 + (m2 - ?0), (d1 - ?0) * 10 + (d2 - ?0)) do
      {:ok, _date} -> :ok
      _ -> :error
    end
  end

  defp validate_date(_date), do: :error

  # Callers only pass two-digit ASCII fields, so plain arithmetic replaces integer parsing.
  defp validate_time(<<h1, h2>>, <<m1, m2>>, <<s1, s2>>) do
    hour = (h1 - ?0) * 10 + (h2 - ?0)
    minute = (m1 - ?0) * 10 + (m2 - ?0)
    second = (s1 - ?0) * 10 + (s2 - ?0)

    if hour <= 23 and minute <= 59 and second <= 60, do: :ok, else: :error
  end

  defp validate_leading_zero(digits, 10) do
    if byte_size(digits) > 1 and String.starts_with?(digits, "0") do
      :error
    else
      :ok
    end
  end

  defp validate_leading_zero(_digits, _base), do: :ok

  defp integer_digits(digits) do
    case :binary.match(digits, "_") do
      :nomatch ->
        {:ok, digits}

      {index, _} ->
        if index == 0 or :binary.last(digits) == ?_ or String.contains?(digits, "__") do
          :error
        else
          {:ok, String.replace(digits, "_", "")}
        end
    end
  end

  defp validate_digits(<<digit, rest::binary>>, base) when digit in ?0..?9 and digit - ?0 < base,
    do: validate_digits(rest, base)

  defp validate_digits(<<digit, rest::binary>>, 16) when digit in ?a..?f or digit in ?A..?F, do: validate_digits(rest, 16)

  defp validate_digits("", _base), do: :ok
  defp validate_digits(_digits, _base), do: :error
end
