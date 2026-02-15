defmodule TomlElixir.DeriveTest do
  use ExUnit.Case, async: true

  alias TomlElixir.TestStructs.UserOnly

  test "can derive encoder" do
    user = %TomlElixir.TestStructs.User{name: "Alice", age: 30}
    assert {:ok, toml} = TomlElixir.encode(%{user: user})
    assert toml =~ "[user]"
    assert toml =~ "name = \"Alice\""
    assert toml =~ "age = 30"
  end

  test "supports deriving with only option" do
    user = %UserOnly{name: "Alice", age: 30, password: "secret"}
    assert {:ok, toml} = TomlElixir.encode(%{user: user})

    assert toml =~ "[user]"
    assert toml =~ "name = \"Alice\""
    refute toml =~ "age = 30"
    refute toml =~ "password"
  end

  test "supports deriving with except option" do
    user = %TomlElixir.TestStructs.UserExcept{name: "Alice", age: 30, password: "secret"}
    assert {:ok, toml} = TomlElixir.encode(%{user: user})

    assert toml =~ "[user]"
    assert toml =~ "name = \"Alice\""
    assert toml =~ "age = 30"
    refute toml =~ "password"
  end

  test "only takes precedence over except when both options are present" do
    user = %TomlElixir.TestStructs.UserOnlyWins{name: "Alice", age: 30, password: "secret"}
    assert {:ok, toml} = TomlElixir.encode(%{user: user})

    assert toml =~ "[user]"
    assert toml =~ "name = \"Alice\""
    assert toml =~ "age = 30"
    refute toml =~ "password"
  end

  test "applies derived filtering for arrays of structs" do
    users = [
      %UserOnly{name: "Alice", age: 30, password: "a"},
      %UserOnly{name: "Bob", age: 31, password: "b"}
    ]

    assert {:ok, toml} = TomlElixir.encode(%{users: users})

    assert toml =~ "[[users]]"
    assert toml =~ "name = \"Alice\""
    assert toml =~ "name = \"Bob\""
    refute toml =~ "age ="
    refute toml =~ "password"
  end

  test "works for non-derived struct due to Any fallback" do
    other = %TomlElixir.TestStructs.Other{foo: "bar"}
    assert {:ok, toml} = TomlElixir.encode(%{other: other})
    assert toml =~ "[other]"
    assert toml =~ "foo = \"bar\""
  end

  test "supports Protocol.derive/3 for external structs" do
    user = %TomlElixir.TestStructs.ProtocolDerived{name: "Alice", age: 30, password: "secret"}
    assert {:ok, toml} = TomlElixir.encode(%{user: user})

    assert toml =~ "[user]"
    assert toml =~ "name = \"Alice\""
    refute toml =~ "age = 30"
    refute toml =~ "password"
  end

  test "can derive encoder with complex module name" do
    nested = %TomlElixir.TestStructs.Nested.Complex.ModuleName{field: "value"}
    assert {:ok, toml} = TomlElixir.encode(%{nested: nested})
    assert toml =~ "[nested]"
    assert toml =~ "field = \"value\""
  end

  test "raises on unknown fields in only option" do
    module = unique_temp_module()

    quoted =
      quote do
        defmodule unquote(module) do
          @derive {TomlElixir.Encoder, only: [:missing]}
          defstruct [:name]
        end
      end

    assert_raise ArgumentError,
                 ~r/unknown struct fields \[:missing\] specified in :only. Expected one of: \[:name\]/,
                 fn -> Code.eval_quoted(quoted) end
  end

  test "raises on unknown fields in except option" do
    module = unique_temp_module()

    quoted =
      quote do
        defmodule unquote(module) do
          @derive {TomlElixir.Encoder, except: [:missing]}
          defstruct [:name]
        end
      end

    assert_raise ArgumentError,
                 ~r/unknown struct fields \[:missing\] specified in :except. Expected one of: \[:name\]/,
                 fn -> Code.eval_quoted(quoted) end
  end

  defp unique_temp_module do
    Module.concat([TomlElixir.DeriveTest, :"Tmp#{System.unique_integer([:positive])}"])
  end
end
