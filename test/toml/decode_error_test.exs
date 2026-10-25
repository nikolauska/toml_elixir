defmodule TomlElixir.DecodeErrorTest do
  use ExUnit.Case, async: true

  alias TomlElixir.Parser.Error

  defp location(toml) do
    assert {:error, %Error{} = error} = TomlElixir.decode(toml)
    {error.reason, error.line, error.column, error.offset}
  end

  test "reports the position of an invalid scalar" do
    assert location("a = 1\nb = nope") == {"Invalid value nope", 2, 5, 10}
  end

  test "reports the statement start for builder errors" do
    assert location("port = 1\nport = 2") == {"Duplicate key port", 2, 1, 9}
    assert location("a = 1\n[a]") == {"Table a conflicts with existing value", 2, 1, 6}
    assert location("t = {a = 1, a = 2}") == {"Duplicate key a", 1, 13, 12}
  end

  test "reports end of input for unterminated arrays" do
    assert location("a = [1,") == {"Invalid value", 1, 8, 7}
  end

  test "counts CRLF as one line break" do
    assert location("a = 1\r\nb = nope") == {"Invalid value nope", 2, 5, 11}
  end

  test "counts columns in codepoints and offsets in bytes" do
    assert location(~s(k = "äö\\q")) == {"Invalid escape sequence", 1, 8, 9}
  end

  test "includes a leading BOM in the offset but not in the column" do
    assert location(<<0xEF, 0xBB, 0xBF>> <> "a = nope") == {"Invalid value nope", 1, 5, 7}
  end

  test "reports the first invalid UTF-8 byte" do
    assert location(<<"a = 1\ns = \"ab", 0xFF, "\"">>) == {"Invalid UTF-8", 2, 8, 13}
  end

  test "includes the location in the message" do
    assert {:error, error} = TomlElixir.decode("a = 1\nb = nope")
    assert Exception.message(error) == "Invalid value nope at line 2, column 5"
    assert_raise Error, "Invalid value nope at line 2, column 5", fn -> TomlElixir.decode!("a = 1\nb = nope") end
  end

  test "keeps the plain reason for errors built without a location" do
    assert Exception.message(Error.exception("Invalid value")) == "Invalid value"
  end
end
