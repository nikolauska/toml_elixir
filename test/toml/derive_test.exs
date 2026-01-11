defmodule TomlElixir.DeriveTest do
  use ExUnit.Case, async: true

  defmodule User do
    @moduledoc false
    @derive TomlElixir.Encoder
    defstruct [:name, :age]
  end

  test "can derive encoder" do
    user = %User{name: "Alice", age: 30}
    assert {:ok, toml} = TomlElixir.encode(%{user: user})
    assert toml =~ "[user]"
    assert toml =~ "name = \"Alice\""
    assert toml =~ "age = 30"
  end

  defmodule Other do
    @moduledoc false
    defstruct [:foo]
  end

  test "works for non-derived struct due to Any fallback" do
    other = %Other{foo: "bar"}
    assert {:ok, toml} = TomlElixir.encode(%{other: other})
    assert toml =~ "[other]"
    assert toml =~ "foo = \"bar\""
  end

  defmodule Nested.Complex.ModuleName do
    @moduledoc false
    @derive TomlElixir.Encoder
    defstruct [:field]
  end

  test "can derive encoder with complex module name" do
    nested = %Nested.Complex.ModuleName{field: "value"}
    assert {:ok, toml} = TomlElixir.encode(%{nested: nested})
    assert toml =~ "[nested]"
    assert toml =~ "field = \"value\""
  end
end
