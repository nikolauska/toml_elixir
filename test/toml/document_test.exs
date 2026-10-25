defmodule TomlElixir.DocumentTest do
  use ExUnit.Case, async: true

  alias TomlElixir.Document
  alias TomlElixir.Document.Error

  @toml_root Path.expand(".", __DIR__)

  for spec <- [:"1.0.0", :"1.1.0"] do
    files =
      @toml_root
      |> Path.join("files-toml-#{spec}")
      |> File.read!()
      |> String.split("\n", trim: true)
      |> Enum.filter(&String.ends_with?(&1, ".toml"))

    {valid, invalid} = Enum.split_with(files, &String.starts_with?(&1, "valid/"))

    # Every valid fixture checks that rendering is lossless and that the document's data
    # matches decoding; every invalid fixture checks that validation matches decoding.
    test "round-trips every valid #{spec} fixture" do
      for rel_path <- unquote(valid) do
        toml = File.read!(Path.join(@toml_root, rel_path))
        assert {:ok, doc} = Document.parse(toml, spec: unquote(spec)), rel_path
        assert Document.to_string(doc) == toml, rel_path
        assert {:ok, Document.to_map(doc)} == TomlElixir.decode(toml, spec: unquote(spec)), rel_path
      end
    end

    # Adding to every table and array in every fixture exercises placement against all the
    # ways the fixtures define tables: headers, dotted keys, inline tables, arrays of tables.
    test "adds values under every table and array of every valid #{spec} fixture" do
      for rel_path <- unquote(valid),
          doc = Document.parse!(File.read!(Path.join(@toml_root, rel_path)), spec: unquote(spec)),
          {path, value} <- insertions(Document.to_map(doc), []) do
        assert {:ok, edited} = Document.put(doc, path, value), "#{rel_path} #{inspect(path)}"
        reparsed = Document.parse!(Document.to_string(edited), spec: unquote(spec))
        assert Document.fetch(reparsed, path) == {:ok, value}, "#{rel_path} #{inspect(path)}"
      end
    end

    test "deletes and replaces every value of every valid #{spec} fixture" do
      for rel_path <- unquote(valid),
          doc = Document.parse!(File.read!(Path.join(@toml_root, rel_path)), spec: unquote(spec)),
          path <- value_paths(Document.to_map(doc), []),
          {op, expected} <- [delete: nil, put: replacement(Document.get(doc, path))] do
        data = Document.to_map(doc)

        access =
          Enum.map(path, fn
            index when is_integer(index) -> Access.at(index)
            key -> Access.key(key)
          end)

        {result, expected} =
          case op do
            :delete -> {Document.delete(doc, path), data |> pop_in(access) |> elem(1)}
            :put -> {Document.put(doc, path, expected), put_in(data, access, expected)}
          end

        assert {:ok, edited} = result, "#{op} #{rel_path} #{inspect(path)}"

        assert TomlElixir.decode!(Document.to_string(edited), spec: unquote(spec)) == expected,
               "#{op} #{rel_path} #{inspect(path)}"
      end
    end

    test "rejects every invalid #{spec} fixture" do
      for rel_path <- unquote(invalid) do
        toml = File.read!(Path.join(@toml_root, rel_path))
        assert {:error, %TomlElixir.Parser.Error{}} = Document.parse(toml, spec: unquote(spec)), rel_path
      end
    end
  end

  defp insertions(map, path) when is_map(map) and not is_struct(map) do
    [
      {Enum.reverse(["zz_key" | path]), 1},
      {Enum.reverse(["zz_table" | path]), %{"x" => 1, "sub" => %{"y" => [%{"z" => 2}]}}}
    ] ++
      Enum.flat_map(map, fn {key, value} -> insertions(value, [key | path]) end)
  end

  defp insertions(list, path) when is_list(list) do
    [{Enum.reverse([length(list) | path]), %{"zz" => 1}}] ++
      (list |> Enum.with_index() |> Enum.flat_map(fn {value, index} -> insertions(value, [index | path]) end))
  end

  defp insertions(_value, _path), do: []

  defp value_paths(value, path) do
    here = if path == [], do: [], else: [Enum.reverse(path)]

    cond do
      is_map(value) and not is_struct(value) ->
        here ++ Enum.flat_map(value, fn {key, child} -> value_paths(child, [key | path]) end)

      is_list(value) ->
        indexed = Enum.with_index(value)
        here ++ Enum.flat_map(indexed, fn {child, index} -> value_paths(child, [index | path]) end)

      true ->
        here
    end
  end

  # Tables drop their first key and gain one, so a replacement deletes, keeps, and adds.
  defp replacement(map) when is_map(map) and not is_struct(map) do
    dropped = if map == %{}, do: [], else: [map |> Map.keys() |> Enum.min()]
    map |> Map.drop(dropped) |> Map.put("zz_new", 1)
  end

  defp replacement(_value), do: "replaced"

  @config """
  # Service settings
  title = "demo"   # shown in the UI
  port = 0x1F90

  [server]
    host = 'localhost'
    ports = [
      80, # http
      443,
    ]
    meta = { a = 1, b.c = [1, 2] }

  [[products]]
  name = "a"

  [[products]]
  name = "b"
  """

  setup do
    {:ok, doc: Document.parse!(@config)}
  end

  test "keeps a byte order mark and CRLF line endings" do
    toml = <<0xEF, 0xBB, 0xBF>> <> "a = 1 # one\r\n\r\n[t]\r\nb = 2\r\n"
    doc = toml |> Document.parse!() |> Document.put!(["t", "b"], 3)
    assert Document.to_string(doc) == <<0xEF, 0xBB, 0xBF>> <> "a = 1 # one\r\n\r\n[t]\r\nb = 3\r\n"
  end

  test "fetch/2 and get/3 read through tables, arrays, and arrays of tables", %{doc: doc} do
    assert Document.fetch(doc, ["port"]) == {:ok, 8080}
    assert Document.fetch(doc, ["server", "meta", "b", "c", 1]) == {:ok, 2}
    assert Document.get(doc, ["products", 1, "name"]) == "b"
    assert Document.fetch(doc, ["products", 2]) == :error
    assert Document.get(doc, ["missing"], :default) == :default
  end

  test "put/3 replaces a value and keeps its line's comment", %{doc: doc} do
    doc = Document.put!(doc, ["title"], "new")
    assert Document.to_string(doc) =~ ~s(title = "new"   # shown in the UI\n)
    assert Document.get(doc, ["title"]) == "new"
  end

  test "put/3 leaves the rest of the document untouched", %{doc: doc} do
    doc = Document.put!(doc, ["server", "host"], "0.0.0.0")
    assert Document.to_string(doc) == String.replace(@config, "'localhost'", ~s("0.0.0.0"))
  end

  test "put/3 reaches array elements, inline table entries, and arrays of tables", %{doc: doc} do
    doc =
      doc
      |> Document.put!(["server", "ports", 1], 8443)
      |> Document.put!(["server", "meta", "b", "c", 0], %{"x" => true})
      |> Document.put!(["products", 1, "name"], "bee")

    rendered = Document.to_string(doc)
    assert rendered =~ "    80, # http\n    8443,\n  ]"
    assert rendered =~ "meta = { a = 1, b.c = [{x = true}, 2] }"
    assert rendered =~ ~s(name = "a"\n\n[[products]]\nname = "bee"\n)
  end

  test "replaced values can be edited again", %{doc: doc} do
    doc =
      doc
      |> Document.put!(["server", "ports"], [1, 2])
      |> Document.put!(["server", "ports", 0], 5)

    assert Document.to_string(doc) =~ "ports = [5, 2]\n"
  end

  test "put/3 resolves nested arrays of tables through their latest parent entry" do
    toml = "[[a]]\n[[a.b]]\nx = 1\n[[a]]\n[[a.b]]\nx = 2\n[[a.b]]\nx = 3\n"
    doc = toml |> Document.parse!() |> Document.put!(["a", 1, "b", 1, "x"], 30)
    assert Document.to_string(doc) == String.replace(toml, "x = 3", "x = 30")
  end

  test "update/3 replaces a value with the function's result", %{doc: doc} do
    doc = Document.update!(doc, ["port"], &(&1 + 1))
    assert Document.to_string(doc) =~ "port = 8081\n"
    assert {:error, %Error{path: ["missing"]}} = Document.update(doc, ["missing"], & &1)
  end

  describe "put/3 with new values" do
    @layout """
    # Service settings
    title = "demo"   # shown in the UI

    [server]
      host = 'localhost'
      meta = { a = 1 }
      tls.cert = "c"

    # Products follow
    [[products]]
    name = "a"

    [[products]]
    name = "b"

    [a.b]
    x = 1
    """

    defp put_new(path, value, toml \\ @layout) do
      toml |> Document.parse!() |> Document.put!(path, value) |> Document.to_string()
    end

    test "adds a root key after the last root key/value line" do
      assert put_new(["version"], 2) == String.replace(@layout, "UI\n", "UI\nversion = 2\n")
    end

    test "adds a root key after leading comments when the root has no keys" do
      assert put_new(["a"], 1, "# c\n\n[t]\nx = 1\n") == "# c\n\na = 1\n\n[t]\nx = 1\n"
      assert put_new(["a"], 1, "[t]\nx = 1\n") == "a = 1\n\n[t]\nx = 1\n"
    end

    test "adds a key to a header table with the table's indentation" do
      assert put_new(["server", "timeout"], 30) =~ ~s(  tls.cert = "c"\n  timeout = 30\n\n# Products follow)
    end

    test "adds a key to a table defined by dotted keys as another dotted key" do
      assert put_new(["server", "tls", "key"], "k") =~ ~s(  tls.cert = "c"\n  tls.key = "k"\n)
    end

    test "adds entries to inline tables" do
      assert put_new(["server", "meta", "b"], 2) =~ "meta = { a = 1, b = 2 }"
      assert put_new(["t", "x"], 1, "t = {}\n") == "t = {x = 1}\n"
      assert put_new(["t", "b", "c"], 1, "t = { a = 1 }\n") == "t = { a = 1, b.c = 1 }\n"
    end

    test "appends array elements in the array's layout" do
      assert put_new(["a", 2], 3, "a = [1, 2]\n") == "a = [1, 2, 3]\n"
      assert put_new(["a", 1], 2, "a = [1]\n") == "a = [1, 2]\n"
      assert put_new(["a", 0], 1, "a = [ ]\n") == "a = [1]\n"
      assert put_new(["a", 2], 3, "a = [\n  1,\n  2\n]\n") == "a = [\n  1,\n  2,\n  3\n]\n"
    end

    test "keeps comments with the array element they follow" do
      assert put_new(["a", 2], 3, "a = [\n  1, # one\n  2, # two\n]\n") ==
               "a = [\n  1, # one\n  2, # two\n  3,\n]\n"

      assert put_new(["a", 1], 2, "a = [\n  1 # one\n]\n") == "a = [\n  1, # one\n  2\n]\n"
    end

    test "adds a subtable after its parent's sections and before comments for the next one" do
      assert put_new(["server", "limits"], %{"rate" => 5, "burst" => %{"max" => 9}}) =~
               ~s(  tls.cert = "c"\n\n[server.limits]\nrate = 5\n\n[server.limits.burst]\nmax = 9\n\n# Products follow\n)
    end

    test "creates missing parent tables" do
      assert put_new(["server", "x", "y"], 1, "[server]\nport = 1\n") == "[server]\nport = 1\n\n[server.x]\ny = 1\n"
      assert put_new(["database", "host"], "db") == @layout <> "\n[database]\nhost = \"db\"\n"
    end

    test "adds arrays of tables and their entries" do
      assert put_new(["products", 2], %{"name" => "c"}) =~ ~s(name = "b"\n\n[[products]]\nname = "c"\n\n[a.b])
      assert put_new(["p"], [%{"n" => 1}], "a = 1\n") == "a = 1\n\n[[p]]\nn = 1\n"
    end

    test "places content for an array of tables entry inside that entry" do
      assert put_new(["products", 0, "price"], 1.5) =~ ~s(name = "a"\nprice = 1.5\n\n[[products]]\nname = "b")

      assert put_new(["p", 0, "tags"], [%{"t" => 1}], "[[p]]\nn = 1\n\n[[p]]\nn = 2\n") ==
               "[[p]]\nn = 1\n\n[[p.tags]]\nt = 1\n\n[[p]]\nn = 2\n"
    end

    test "gives a table defined only by subtables its own header" do
      assert put_new(["a", "y"], 1) == @layout <> "\n[a]\ny = 1\n"
    end

    test "handles empty documents, a missing final line ending, and CRLF" do
      assert put_new(["a", "b"], 1, "") == "[a]\nb = 1\n"
      assert put_new(["b"], 2, "a = 1 # c") == "a = 1 # c\nb = 2\n"
      assert put_new(["t", "b"], 2, "a = 1\r\n") == "a = 1\r\n\r\n[t]\r\nb = 2\r\n"
    end

    test "re-reads the new value" do
      doc = @layout |> Document.parse!() |> Document.put!(["server", "limits", "rate"], 5)
      assert Document.get(doc, ["server", "limits"]) == %{"rate" => 5}
      assert doc |> Document.put!(["server", "limits", "rate"], 6) |> Document.get(["server", "limits", "rate"]) == 6
    end
  end

  test "put/3 explains values it cannot place", %{doc: doc} do
    assert {:error, %Error{reason: "arrays can only grow by appending at index 2"}} =
             Document.put(doc, ["server", "ports", 5], 1)

    assert {:error, %Error{reason: "parent is not a table or array"}} = Document.put(doc, ["title", "x"], 1)
    assert {:error, %Error{reason: "only the next index" <> _}} = Document.put(doc, ["new", 0], 1)
    assert {:error, %Error{reason: "arrays of tables can only hold tables"}} = Document.put(doc, ["products", 2], 1)
  end

  test "put/3 returns encoding failures" do
    doc = Document.parse!("a = 1\n")
    assert {:error, %Error{reason: "nil is not supported in TOML", path: ["a"]}} = Document.put(doc, ["a"], nil)

    assert_raise Error, ~r/^a: nil is not supported/, fn -> Document.put!(doc, ["a"], nil) end
  end

  test "delete/2 removes a key/value line but keeps comment lines above it", %{doc: doc} do
    doc = Document.delete!(doc, ["title"])
    assert Document.to_string(doc) == String.replace(@config, ~s(title = "demo"   # shown in the UI\n), "")
    assert Document.fetch(doc, ["title"]) == :error
  end

  test "delete/2 removes array elements and inline table entries", %{doc: doc} do
    doc =
      doc
      |> Document.delete!(["server", "ports", 0])
      |> Document.delete!(["server", "meta", "a"])
      |> Document.delete!(["server", "meta", "b", "c", 1])

    rendered = Document.to_string(doc)
    assert rendered =~ "  ports = [\n    443,\n  ]\n"
    assert rendered =~ "meta = { b.c = [1] }"
  end

  test "delete/2 keeps single-line layout when removing the last member" do
    doc = Document.parse!("a = [ 1, 2 ]\nb = { x = 1, y = 2 }\nc = [1]\n")

    doc =
      doc
      |> Document.delete!(["a", 1])
      |> Document.delete!(["b", "y"])
      |> Document.delete!(["c", 0])

    assert Document.to_string(doc) == "a = [ 1 ]\nb = { x = 1 }\nc = []\n"
  end

  test "delete/2 ignores missing paths", %{doc: doc} do
    assert Document.delete(doc, ["missing"]) == {:ok, doc}
  end

  describe "tables" do
    @tables """
    title = "demo"

    # Server block
    [server]
      host = 'localhost' # dev only
      port = 0x1F90
      tls.cert = "c"

    [server.limits]
    rate = 5

    # Products follow
    [[products]]
    name = "a"

    [[products]]
    name = "b"
    sku = 2
    """

    defp edit_tables(fun), do: @tables |> Document.parse!() |> fun.() |> Document.to_string()

    test "put/3 on a table keeps unchanged keys as written" do
      new = %{"host" => "localhost", "port" => 8080, "tls" => %{"cert" => "c", "key" => "k"}, "debug" => true}

      assert edit_tables(&Document.put!(&1, ["server"], new)) ==
               String.replace(
                 @tables,
                 ~s(  tls.cert = "c"\n\n[server.limits]\nrate = 5\n),
                 ~s(  tls.cert = "c"\n  tls.key = "k"\n  debug = true\n)
               )
    end

    test "put/3 with an equal value leaves the document unchanged" do
      doc = Document.parse!(@tables)
      assert Document.put(doc, ["server", "port"], 8080) == {:ok, doc}
      assert Document.put(doc, ["server"], Document.get(doc, ["server"])) == {:ok, doc}
    end

    test "put/3 accepts atom keys and structs that encode as tables" do
      assert edit_tables(&Document.put!(&1, ["server", "limits"], %{rate: 5, burst: 10})) =~
               "[server.limits]\nrate = 5\nburst = 10\n"
    end

    test "put/3 on an array of tables updates entries by index" do
      assert edit_tables(&Document.put!(&1, ["products"], [%{"name" => "a"}, %{"name" => "B", "sku" => 2}])) ==
               String.replace(@tables, ~s(name = "b"), ~s(name = "B"))

      assert edit_tables(&Document.put!(&1, ["products"], [%{"name" => "a"}])) ==
               String.replace(@tables, ~s(\n\n[[products]]\nname = "b"\nsku = 2), "")

      assert edit_tables(&Document.put!(&1, ["products", 2], %{"name" => "c"})) ==
               @tables <> ~s(\n[[products]]\nname = "c"\n)
    end

    test "put/3 replaces a table with a value of another kind" do
      assert edit_tables(&Document.put!(&1, ["products"], [])) ==
               @tables
               |> String.replace(~s(title = "demo"\n), ~s(title = "demo"\nproducts = []\n))
               |> String.replace(~s([[products]]\nname = "a"\n\n[[products]]\nname = "b"\nsku = 2\n), "")
    end

    test "delete/2 removes a table with its subtables and dotted keys" do
      assert edit_tables(&Document.delete!(&1, ["server"])) ==
               ~s(title = "demo"\n\n# Server block\n\n# Products follow\n[[products]]\nname = "a"\n\n[[products]]\nname = "b"\nsku = 2\n)

      assert edit_tables(&Document.delete!(&1, ["server", "tls"])) == String.replace(@tables, ~s(  tls.cert = "c"\n), "")
    end

    test "delete/2 removes one array of tables entry" do
      assert edit_tables(&Document.delete!(&1, ["products", 0])) ==
               String.replace(@tables, ~s([[products]]\nname = "a"\n\n), "")
    end

    test "delete/2 keeps a parent table that only its deleted content defined" do
      assert "[a.b]\nx = 1\n" |> Document.parse!() |> Document.delete!(["a", "b"]) |> Document.to_map() == %{"a" => %{}}

      assert "t = { a.b = 1 }\n" |> Document.parse!() |> Document.delete!(["t", "a", "b"]) |> Document.to_map() == %{
               "t" => %{"a" => %{}}
             }

      assert "[[p]]\nx = 1\n" |> Document.parse!() |> Document.delete!(["p", 0]) |> Document.to_string() == "p = []\n"
    end
  end
end
