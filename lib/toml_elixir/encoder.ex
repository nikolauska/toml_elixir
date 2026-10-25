defprotocol TomlElixir.Encoder do
  @moduledoc """
  Protocol for encoding Elixir terms to TOML.

  You can derive this protocol for structs:

      @derive TomlElixir.Encoder
      defstruct [:name, :age]

      @derive {TomlElixir.Encoder, only: [:name]}
      defstruct [:name, :age, :password]

      @derive {TomlElixir.Encoder, except: [:password]}
      defstruct [:name, :age, :password]

  If you don't own the struct, you can derive externally:

      Protocol.derive(TomlElixir.Encoder, NameOfTheStruct, only: [:field])
      Protocol.derive(TomlElixir.Encoder, NameOfTheStruct, except: [:field])
      Protocol.derive(TomlElixir.Encoder, NameOfTheStruct)
  """

  @fallback_to_any true

  @impl true
  defmacro __deriving__(module, opts) do
    fields = module |> Macro.struct_info!(__CALLER__) |> Enum.map(& &1.field)
    fields = fields_to_encode(fields, opts)
    vars = Macro.generate_arguments(length(fields), __MODULE__)
    kv = Enum.zip(fields, vars)

    quote do
      defimpl TomlElixir.Encoder, for: unquote(module) do
        def encode(%{unquote_splicing(kv)}) do
          TomlElixir.Encoder.encode(%{unquote_splicing(kv)})
        end

        def project(%{unquote_splicing(kv)}) do
          %{unquote_splicing(kv)}
        end
      end
    end
  end

  defp fields_to_encode(fields, opts) do
    cond do
      only = Keyword.get(opts, :only) ->
        case only -- fields do
          [] ->
            only

          error_keys ->
            raise ArgumentError,
                  "unknown struct fields #{inspect(error_keys)} specified in :only. Expected one of: " <>
                    "#{inspect(fields -- [:__struct__])}"
        end

      except = Keyword.get(opts, :except) ->
        case except -- fields do
          [] ->
            fields -- [:__struct__ | except]

          error_keys ->
            raise ArgumentError,
                  "unknown struct fields #{inspect(error_keys)} specified in :except. Expected one of: " <>
                    "#{inspect(fields -- [:__struct__])}"
        end

      true ->
        fields -- [:__struct__]
    end
  end

  @doc "Encodes a value to TOML value format (inline)."
  def encode(value)

  @doc false
  def project(value)
end

defmodule TomlElixir.Encoder.Helpers do
  @moduledoc false

  import Bitwise

  @ones 0x01010101010101
  @high_bits 0x80808080808080
  @control_limit 0x20 * @ones
  @quotes 0x22 * @ones
  @backslashes 0x5C * @ones

  # Checks 7 bytes per step (the word stays a small integer) instead of one clause per byte.
  # A byte sets its high bit here when it is >= 0x7F, < 0x20, `"` or `\`. Carries and borrows can
  # only add false positives, which fall back to the exact per-byte clauses.
  defguardp plain_word?(word)
            when band(
                   bor(
                     bor(word + @ones, word),
                     bor(
                       band(word - @control_limit, bnot(word)),
                       bor(
                         band(bxor(word, @quotes) - @ones, bnot(bxor(word, @quotes))),
                         band(bxor(word, @backslashes) - @ones, bnot(bxor(word, @backslashes)))
                       )
                     )
                   ),
                   @high_bits
                 ) == 0

  defguardp bare_key_char?(char)
            when char in ?a..?z or char in ?A..?Z or char in ?0..?9 or char == ?_ or char == ?-

  # Converting each key once and sorting on it keeps the stable `Enum.sort_by(&to_string/1)`
  # order without stringifying keys again when encoding them.
  def sorted_pairs(map) do
    map |> :maps.to_list() |> stringify_keys() |> List.keysort(0)
  end

  defp stringify_keys([{key, _value} = pair | rest]) when is_binary(key), do: [pair | stringify_keys(rest)]
  defp stringify_keys([{key, value} | rest]), do: [{to_string(key), value} | stringify_keys(rest)]
  defp stringify_keys([]), do: []

  def encode_key(key) do
    if key != "" and bare_key?(key) do
      key
    else
      [?", escape_iodata(key), ?"]
    end
  end

  # A byte scan replaces the former regex, whose per-call setup dominated key encoding.
  defp bare_key?(<<char, rest::binary>>) when bare_key_char?(char), do: bare_key?(rest)
  defp bare_key?(<<>>), do: true
  defp bare_key?(_key), do: false

  def encode_value(value) when is_binary(value), do: [?", escape_iodata(value), ?"]
  def encode_value(value) when is_integer(value), do: Integer.to_string(value)
  def encode_value(value) when is_float(value), do: encode_float(value)
  def encode_value(value) when is_list(value), do: encode_array(value)
  def encode_value(value) when is_map(value) and not is_struct(value), do: encode_inline_table(value)
  def encode_value(value), do: TomlElixir.Encoder.encode(value)

  # TOML requires a fractional part or exponent. The shortest round-trip format always has
  # one (`1.0`, `1.0e20`), so the output needs no scan for `.` or `e`.
  def encode_float(float), do: :erlang.float_to_binary(float, [:short])

  def encode_array(list), do: [?[, encode_items(list, list), ?]]

  defp encode_items([value | rest], list) do
    value = encode_value(value)
    [value | encode_next_items(rest, list)]
  end

  defp encode_items([], _list), do: []

  defp encode_next_items([value | rest], list) do
    value = encode_value(value)
    [", ", value | encode_next_items(rest, list)]
  end

  defp encode_next_items([], _list), do: []

  # Improper lists: rerun the former `Enum.map_join/3` path so the raised error stays the same.
  defp encode_next_items(_tail, list), do: Enum.map_join(list, ", ", &TomlElixir.Encoder.encode/1)

  def encode_inline_table(map), do: [?{, encode_inline_pairs(sorted_pairs(map)), ?}]

  defp encode_inline_pairs([{key, value} | rest]) do
    pair = encode_pair(key, value)
    [pair | encode_next_inline_pairs(rest)]
  end

  defp encode_inline_pairs([]), do: []

  defp encode_next_inline_pairs([{key, value} | rest]) do
    pair = encode_pair(key, value)
    [", ", pair | encode_next_inline_pairs(rest)]
  end

  defp encode_next_inline_pairs([]), do: []

  def encode_pair(key, value) do
    key = encode_key(key)
    [key, " = " | encode_value(value)]
  end

  def escape_string(str), do: str |> escape_iodata() |> IO.iodata_to_binary()

  # Returns the original binary when nothing needs escaping, otherwise iodata of unchanged spans
  # and escapes so callers embedding it in larger iodata avoid an intermediate copy.
  defp escape_iodata(str), do: escape_string(str, str, 0, 0, [])

  defp escape_string(<<word::56, rest::binary>>, original, start, length, acc) when plain_word?(word) do
    escape_string(rest, original, start, length + 7, acc)
  end

  defp escape_string(<<char, rest::binary>>, original, start, length, acc) when char < 0x20 or char in [?\\, ?", 0x7F] do
    segment = binary_part(original, start, length)
    escape_string(rest, original, start + length + 1, 0, [acc, segment | escape_char(char)])
  end

  defp escape_string(<<char, rest::binary>>, original, start, length, acc) when char < 0x80 do
    escape_string(rest, original, start, length + 1, acc)
  end

  defp escape_string(<<char::utf8, rest::binary>>, original, start, length, acc) do
    escape_string(rest, original, start, length + utf8_size(char), acc)
  end

  defp escape_string("", original, _start, _length, []), do: original

  defp escape_string("", original, start, length, acc) do
    # Keep unchanged spans intact instead of allocating an output entry for every codepoint.
    [acc | binary_part(original, start, length)]
  end

  defp escape_string(_rest, original, _start, _length, _acc) do
    # Preserve the existing conversion error for malformed UTF-8 and non-binary bitstrings.
    original |> String.to_charlist() |> Enum.map(&escape_char/1) |> IO.iodata_to_binary()
  end

  defp utf8_size(char) when char < 0x800, do: 2
  defp utf8_size(char) when char < 0x10000, do: 3
  defp utf8_size(_char), do: 4

  defp escape_char(?\\), do: "\\\\"
  defp escape_char(?"), do: "\\\""
  defp escape_char(?\b), do: "\\b"
  defp escape_char(?\f), do: "\\f"
  defp escape_char(?\n), do: "\\n"
  defp escape_char(?\r), do: "\\r"
  defp escape_char(?\t), do: "\\t"

  defp escape_char(c) when c < 0x20 or c == 0x7F do
    "\\u" <> (c |> Integer.to_string(16) |> String.pad_leading(4, "0"))
  end

  defp escape_char(c), do: <<c::utf8>>

  def project_undefined!(value) do
    raise Protocol.UndefinedError, protocol: TomlElixir.Encoder, value: value
  end
end

defimpl TomlElixir.Encoder, for: Integer do
  alias TomlElixir.Encoder.Helpers

  def encode(v), do: Integer.to_string(v)
  def project(v), do: Helpers.project_undefined!(v)
end

defimpl TomlElixir.Encoder, for: Float do
  alias TomlElixir.Encoder.Helpers

  def encode(f), do: Helpers.encode_float(f)
  def project(f), do: Helpers.project_undefined!(f)
end

defimpl TomlElixir.Encoder, for: BitString do
  alias TomlElixir.Encoder.Helpers

  def encode(v), do: "\"" <> Helpers.escape_string(v) <> "\""
  def project(v), do: Helpers.project_undefined!(v)
end

defimpl TomlElixir.Encoder, for: Atom do
  alias TomlElixir.Encoder.Helpers

  def encode(true), do: "true"
  def encode(false), do: "false"
  def encode(:infinity), do: "inf"
  def encode(:neg_infinity), do: "-inf"
  def encode(:nan), do: "nan"
  def encode(nil), do: raise("nil is not supported in TOML")
  def encode(atom), do: TomlElixir.Encoder.encode(Atom.to_string(atom))
  def project(atom), do: Helpers.project_undefined!(atom)
end

defimpl TomlElixir.Encoder, for: List do
  alias TomlElixir.Encoder.Helpers

  def encode(list), do: list |> Helpers.encode_array() |> IO.iodata_to_binary()
  def project(list), do: Helpers.project_undefined!(list)
end

defimpl TomlElixir.Encoder, for: Map do
  alias TomlElixir.Encoder.Helpers

  # Inline table
  def encode(map), do: Helpers.encode_inline_table(map)
  def project(map), do: map
end

defimpl TomlElixir.Encoder, for: DateTime do
  alias TomlElixir.Encoder.Helpers

  def encode(dt), do: DateTime.to_iso8601(dt)
  def project(dt), do: Helpers.project_undefined!(dt)
end

defimpl TomlElixir.Encoder, for: NaiveDateTime do
  alias TomlElixir.Encoder.Helpers

  def encode(dt), do: NaiveDateTime.to_iso8601(dt)
  def project(dt), do: Helpers.project_undefined!(dt)
end

defimpl TomlElixir.Encoder, for: Date do
  alias TomlElixir.Encoder.Helpers

  def encode(dt), do: Date.to_iso8601(dt)
  def project(dt), do: Helpers.project_undefined!(dt)
end

defimpl TomlElixir.Encoder, for: Time do
  alias TomlElixir.Encoder.Helpers

  def encode(dt), do: Time.to_iso8601(dt)
  def project(dt), do: Helpers.project_undefined!(dt)
end

defimpl TomlElixir.Encoder, for: Any do
  alias TomlElixir.Encoder.Helpers

  def encode(struct) do
    if is_struct(struct) do
      case struct_impl_for(struct.__struct__, :encode, 1) do
        {:ok, impl} ->
          impl.encode(struct)

        :error ->
          struct
          |> Map.from_struct()
          |> TomlElixir.Encoder.encode()
      end
    else
      raise Protocol.UndefinedError, protocol: TomlElixir.Encoder, value: struct
    end
  end

  def project(struct) do
    if is_struct(struct) do
      case struct_impl_for(struct.__struct__, :project, 1) do
        {:ok, impl} ->
          impl.project(struct)

        :error ->
          Map.from_struct(struct)
      end
    else
      Helpers.project_undefined!(struct)
    end
  end

  defp struct_impl_for(struct_module, fun, arity) do
    impl = Protocol.__concat__(TomlElixir.Encoder, struct_module)

    if impl != __MODULE__ and Code.ensure_loaded?(impl) and function_exported?(impl, fun, arity) do
      {:ok, impl}
    else
      :error
    end
  end
end

defmodule TomlElixir.Encoder.Serializer do
  @moduledoc false

  alias TomlElixir.Encoder.Error
  alias TomlElixir.Encoder.Helpers

  def encode_to_iodata(data, opts \\ [])
  def encode_to_iodata(data, []), do: encode_root(data, false, %{})

  def encode_to_iodata(data, opts) do
    # Invalid options are caller bugs, so they raise instead of becoming an encode error.
    multiline? = multiline_option!(opts[:multiline_arrays])
    inline = opts[:inline_tables] |> inline_option!() |> Enum.reduce(%{}, &put_inline_path(&2, &1))
    encode_root(data, multiline?, inline)
  end

  defp encode_root(data, multiline?, inline) do
    {:ok, encode_map(data, [], multiline?, inline)}
  rescue
    exception -> {:error, %Error{reason: Exception.message(exception), path: error_path(data, inline)}}
  end

  defp multiline_option!(value) when value in [nil, false], do: false
  defp multiline_option!(true), do: true

  defp multiline_option!(other) do
    raise ArgumentError, "invalid :multiline_arrays option #{inspect(other)}, expected a boolean"
  end

  defp inline_option!(nil), do: []

  defp inline_option!(paths) when is_list(paths) do
    Enum.map(paths, fn
      [_ | _] = path -> Enum.map(path, &inline_key!/1)
      other -> raise ArgumentError, "invalid :inline_tables path #{inspect(other)}, expected a non-empty list of keys"
    end)
  end

  defp inline_option!(other) do
    raise ArgumentError, "invalid :inline_tables option #{inspect(other)}, expected a list of key paths"
  end

  defp inline_key!(key) when is_binary(key) or is_atom(key), do: to_string(key)
  defp inline_key!(key), do: raise(ArgumentError, "invalid :inline_tables key #{inspect(key)}, expected a string or atom")

  # Inline paths become a tree keyed like the data, so each table only looks up its own
  # children. `true` marks a table rendered inline; everything below it is inline too.
  defp put_inline_path(true, _path), do: true
  defp put_inline_path(node, [key]), do: Map.put(node, key, true)
  defp put_inline_path(node, [key | rest]), do: Map.put(node, key, put_inline_path(Map.get(node, key, %{}), rest))

  defp encode_map(data, path, multiline?, inline) do
    # Every entry is classified before any value is encoded so errors surface in the same order
    # as the former sort/split/map pipeline, while walking the entries only once per phase.
    {scalars, complex} = data |> project() |> Helpers.sorted_pairs() |> classify(inline, [], [])

    # Scalars first in the current scope, then sub-tables and array of tables
    [encode_scalars(scalars, multiline?), encode_complex(complex, path, multiline?, inline)]
  end

  # Plain maps project to themselves; skip protocol dispatch for the common case.
  # `project/1`, `map_like?/1`, and `array_of_maps?/1` are shared with `TomlElixir.Document`
  # so replacing a table there classifies values exactly like encoding does.
  @doc false
  def project(data) when is_map(data) and not is_struct(data), do: data
  def project(data), do: TomlElixir.Encoder.project(data)

  # Tables chosen for inline rendering are encoded as values among the scalars. Guards cost
  # no extra calls, and the size check short-circuits when there are no inline paths.
  defp classify([{key, _value} = pair | rest], inline, scalars, complex)
       when map_size(inline) > 0 and is_map_key(inline, key) and :erlang.map_get(key, inline) == true do
    classify(rest, inline, [pair | scalars], complex)
  end

  defp classify([{_key, value} = pair | rest], inline, scalars, complex) do
    cond do
      map_like?(value) -> classify(rest, inline, scalars, [{:table, pair} | complex])
      array_of_maps?(value) -> classify(rest, inline, scalars, [{:array, pair} | complex])
      true -> classify(rest, inline, [pair | scalars], complex)
    end
  end

  defp classify([], _inline, scalars, complex), do: {:lists.reverse(scalars), :lists.reverse(complex)}

  # The multiline check lives in the clause heads so default encoding adds no call per scalar.
  defp encode_scalars([{key, [_ | _] = list} | rest], true) do
    line = [Helpers.encode_key(key), " = [\n", encode_lines(list, list), "]\n"]
    [line | encode_scalars(rest, true)]
  end

  defp encode_scalars([{key, value} | rest], multiline?) do
    line = [Helpers.encode_pair(key, value), ?\n]
    [line | encode_scalars(rest, multiline?)]
  end

  defp encode_scalars([], _multiline?), do: []

  # TOML allows a trailing comma, so every element line ends the same way.
  defp encode_lines([value | rest], list), do: ["  ", Helpers.encode_value(value), ",\n" | encode_lines(rest, list)]
  defp encode_lines([], _list), do: []
  # Improper lists: let the inline encoder raise its usual error.
  defp encode_lines(_tail, list), do: Helpers.encode_array(list)

  defp encode_complex([{kind, {key, value}} | rest], path, multiline?, inline) do
    # An inline branch instead of a helper call keeps the no-options path free of extra calls.
    child_inline = if map_size(inline) == 0, do: inline, else: Map.get(inline, key, %{})
    key = Helpers.encode_key(key)
    # Reuse escaped parent segments across siblings and array entries.
    new_path = if path == [], do: key, else: [path, ?. | key]
    table = encode_table(kind, value, new_path, multiline?, child_inline)
    [table | encode_complex(rest, path, multiline?, inline)]
  end

  defp encode_complex([], _path, _multiline?, _inline), do: []

  defp encode_table(:array, items, path, multiline?, inline) do
    Enum.map(items, fn item -> ["\n[[", path, "]]\n" | encode_map(item, path, multiline?, inline)] end)
  end

  defp encode_table(:table, map, path, multiline?, inline) do
    ["\n[", path, "]\n" | encode_map(map, path, multiline?, inline)]
  end

  # Tracking keys while encoding would cost every successful call, so the failing path is
  # found afterwards by re-walking the input in the same order the serializer encodes it.
  defp error_path(data, inline), do: data |> table_error_path([], inline) |> List.wrap() |> Enum.reverse()

  defp table_error_path(data, path, inline) do
    case attempt(fn -> data |> project() |> Helpers.sorted_pairs() |> classify(inline, [], []) end) do
      {:ok, {scalars, complex}} ->
        Enum.find_value(scalars, fn {key, value} -> value_error_path(value, [key | path]) end) ||
          Enum.find_value(complex, &complex_error_path(&1, path, inline))

      :error ->
        path
    end
  end

  defp complex_error_path({kind, {key, value}}, path, inline) do
    child_inline = Map.get(inline, key, %{})

    case kind do
      :table -> table_error_path(value, [key | path], child_inline)
      :array -> items_error_path(value, 0, [key | path], &table_error_path(&1, &2, child_inline))
    end
  end

  defp value_error_path(value, path) do
    case attempt(fn -> Helpers.encode_value(value) end) do
      {:ok, _encoded} -> nil
      :error -> nested_error_path(value, path) || path
    end
  end

  defp nested_error_path(list, path) when is_list(list), do: items_error_path(list, 0, path, &value_error_path/2)

  defp nested_error_path(map, path) when is_map(map) and not is_struct(map) do
    case attempt(fn -> Helpers.sorted_pairs(map) end) do
      {:ok, pairs} -> Enum.find_value(pairs, fn {key, value} -> value_error_path(value, [key | path]) end)
      :error -> nil
    end
  end

  defp nested_error_path(_value, _path), do: nil

  # Walks manually so an improper list tail stops the search instead of raising.
  defp items_error_path([item | rest], index, path, fun) do
    fun.(item, [index | path]) || items_error_path(rest, index + 1, path, fun)
  end

  defp items_error_path(_tail, _index, _path, _fun), do: nil

  defp attempt(fun) do
    {:ok, fun.()}
  rescue
    _exception -> :error
  end

  @doc false
  def array_of_maps?(v) do
    is_list(v) and v != [] and Enum.all?(v, &map_like?/1)
  end

  @doc false
  def map_like?(v) do
    is_map(v) and not special_scalar?(v)
  end

  defp special_scalar?(%DateTime{}), do: true
  defp special_scalar?(%NaiveDateTime{}), do: true
  defp special_scalar?(%Date{}), do: true
  defp special_scalar?(%Time{}), do: true
  defp special_scalar?(_), do: false
end
