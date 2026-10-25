defmodule TomlElixir.Document do
  @moduledoc """
  Format-preserving TOML editing.

  `parse/2` keeps the original source text, so a document renders back byte for byte,
  including comments, whitespace, key order, and value formatting such as hex integers or
  literal strings. Edits only rewrite the value they change; the rest of the document is
  left as written.

      {:ok, doc} = TomlElixir.Document.parse(File.read!("config.toml"))
      {:ok, doc} = TomlElixir.Document.put(doc, ["server", "port"], 9090)
      File.write!("config.toml", TomlElixir.Document.to_iodata(doc))

  Paths list keys from the document root as strings, with integer indexes for array
  elements and arrays of tables, such as `["products", 0, "name"]`.

  ## Where new values go

  `put/3` places a value that does not exist yet next to related content:

    * A key in a table defined by a header, or in the root table, goes after the table's
      last key/value line, with the same indentation.
    * A key in a table defined by dotted keys, such as `a.b = 1`, becomes another dotted key
      after its siblings.
    * A key in an inline table becomes a new entry, and index `length` of an array appends
      an element, keeping the collection's layout.
    * A new table or array of tables entry gets its own header after the last section of
      its nearest existing parent table, or at the end of the document. A table that only
      exists through subtables, like `a` in `[a.b]`, gets a new `[a]` header.

  New lines are inserted before trailing comments and blank lines, since those usually
  introduce what follows them. New text uses the default `TomlElixir.encode/2` style.

  ## Current limits

    * Replaced values are written in the default encoder style, so a replaced hex integer
      becomes decimal and a map replacing a non-table value becomes an inline table.
    * Arrays that are values, like `ports = [80, 443]`, are replaced whole rather than
      element by element.

  Every edit re-validates the whole document, so an edit cannot produce invalid TOML.
  This re-decodes the document on each edit; batch edits on very large documents may be
  slow.
  """

  alias TomlElixir.Document.Edit
  alias TomlElixir.Document.Error
  alias TomlElixir.Document.Items
  alias TomlElixir.Document.Parser

  @bom <<0xEF, 0xBB, 0xBF>>

  @enforce_keys [:spec, :bom?, :newline, :items, :data]
  defstruct [:spec, :bom?, :newline, :items, :data]

  @opaque t :: %__MODULE__{spec: atom, bom?: boolean, newline: binary, items: [tuple], data: map}
  @type path :: [String.t() | non_neg_integer]

  @doc """
  Parses a TOML document, keeping its source formatting.

  Validation matches `TomlElixir.decode/2`, and failures return the same
  `TomlElixir.Parser.Error`.

  ## Options
    * `:spec` - `:"1.1.0"` (default) or `:"1.0.0"`. Edits are validated against the same
      version.
  """
  @spec parse(binary, keyword) :: {:ok, t} | {:error, Exception.t()}
  def parse(input, opts \\ []) when is_binary(input) do
    spec = Keyword.get(opts, :spec, :"1.1.0")

    with {:ok, data} <- TomlElixir.decode(input, spec: spec) do
      {bom?, body} =
        case input do
          <<@bom, rest::binary>> -> {true, rest}
          _ -> {false, input}
        end

      {:ok, %__MODULE__{spec: spec, bom?: bom?, newline: newline(body), items: Parser.parse(body, spec), data: data}}
    end
  end

  @doc "Same as `parse/2`, but raises on failure."
  @spec parse!(binary, keyword) :: t
  def parse!(input, opts \\ []), do: input |> parse(opts) |> unwrap!()

  # New lines follow the document's first line ending so edits do not mix styles.
  defp newline(body) do
    case :binary.match(body, "\n") do
      {index, 1} when index > 0 -> if :binary.at(body, index - 1) == ?\r, do: "\r\n", else: "\n"
      _ -> "\n"
    end
  end

  @doc "Renders the document as iodata."
  @spec to_iodata(t) :: iodata
  def to_iodata(%__MODULE__{bom?: bom?, items: items}) do
    [if(bom?, do: @bom, else: []) | Items.render(items)]
  end

  @doc "Renders the document as a binary."
  @spec to_string(t) :: String.t()
  def to_string(%__MODULE__{} = doc), do: doc |> to_iodata() |> IO.iodata_to_binary()

  @doc """
  Returns the document's data, as `TomlElixir.decode/2` would return it with default
  options.
  """
  @spec to_map(t) :: map
  def to_map(%__MODULE__{data: data}), do: data

  @doc "Fetches the value at `path`."
  @spec fetch(t, path) :: {:ok, term} | :error
  def fetch(%__MODULE__{data: data}, path) when is_list(path), do: Edit.fetch(data, path)

  @doc "Gets the value at `path`, or `default` when it does not exist."
  @spec get(t, path, term) :: term
  def get(%__MODULE__{} = doc, path, default \\ nil) do
    case fetch(doc, path) do
      {:ok, value} -> value
      :error -> default
    end
  end

  @doc """
  Puts `value` at `path`.

  Replacing an existing value keeps the text around it, such as an end-of-line comment.
  Putting a value equal to the current one leaves the document unchanged, so values read
  with `fetch/2` can be written back without losing their format.

  Putting a map on an existing table, or a list of maps on an existing array of tables,
  updates it key by key: unchanged keys keep their text and comments, changed keys are
  replaced, missing keys are deleted, and new keys are added as described in
  [Where new values go](#module-where-new-values-go). Arrays of tables are matched by
  index. Missing parent tables are created.
  """
  @spec put(t, path, term) :: {:ok, t} | {:error, Error.t()}
  def put(%__MODULE__{} = doc, path, value) when is_list(path) do
    doc |> edit_state() |> Edit.put(path, value) |> finish(doc, path)
  end

  @doc "Same as `put/3`, but raises on failure."
  @spec put!(t, path, term) :: t
  def put!(doc, path, value), do: doc |> put(path, value) |> unwrap!()

  @doc """
  Replaces the existing value at `path` with the result of calling `fun` with it.
  """
  @spec update(t, path, (term -> term)) :: {:ok, t} | {:error, Error.t()}
  def update(%__MODULE__{} = doc, path, fun) when is_list(path) and is_function(fun, 1) do
    case fetch(doc, path) do
      {:ok, value} -> put(doc, path, fun.(value))
      :error -> {:error, %Error{reason: "key does not exist", path: path}}
    end
  end

  @doc "Same as `update/3`, but raises on failure."
  @spec update!(t, path, (term -> term)) :: t
  def update!(doc, path, fun), do: doc |> update(path, fun) |> unwrap!()

  @doc """
  Deletes the value at `path`.

  Deleting a key/value line removes that line, including its end-of-line comment.
  Deleting a table removes its header sections, subtables, and dotted keys; deleting an
  array of tables entry removes that entry's sections. Comment lines above deleted content
  are kept, since they may describe more than what was deleted. A path that does not exist
  leaves the document unchanged.
  """
  @spec delete(t, path) :: {:ok, t} | {:error, Error.t()}
  def delete(%__MODULE__{} = doc, path) when is_list(path) do
    doc |> edit_state() |> Edit.delete(path) |> finish(doc, path)
  end

  @doc "Same as `delete/2`, but raises on failure."
  @spec delete!(t, path) :: t
  def delete!(doc, path), do: doc |> delete(path) |> unwrap!()

  defp unwrap!({:ok, value}), do: value
  defp unwrap!({:error, exception}), do: raise(exception)

  defp edit_state(%__MODULE__{} = doc), do: %Edit{items: doc.items, data: doc.data, spec: doc.spec, newline: doc.newline}

  defp finish({:ok, %Edit{items: items}}, doc, path),
    do: if(items == doc.items, do: {:ok, doc}, else: revalidate(doc, items, path))

  defp finish({:error, _error} = error, _doc, _path), do: error

  # Re-decoding the rendered document keeps table and duplicate-key rules in the decoder
  # alone, so a placement mistake surfaces as an error instead of invalid output.
  defp revalidate(%__MODULE__{} = doc, items, path) do
    doc = %{doc | items: items}

    case doc |> __MODULE__.to_string() |> TomlElixir.decode(spec: doc.spec) do
      {:ok, data} -> {:ok, %{doc | data: data}}
      {:error, exception} -> {:error, %Error{reason: "edit produces invalid TOML: #{exception.reason}", path: path}}
    end
  end
end
