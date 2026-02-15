# TomlElixir

[![Build Status](https://github.com/nikolauska/toml_elixir/actions/workflows/elixir.yml/badge.svg)](https://github.com/nikolauska/toml_elixir/actions)
[![Coverage Status](https://coveralls.io/repos/github/nikolauska/toml_elixir/badge.svg?branch=master)](https://coveralls.io/github/nikolauska/toml_elixir?branch=master)
[![Hex version](https://img.shields.io/hexpm/v/toml_elixir.svg)](https://hex.pm/packages/toml_elixir)

**TomlElixir** is a modern, high-performance [TOML](https://github.com/toml-lang/toml) parser and encoder for Elixir. It is designed to be fully compliant with the TOML specification while providing an idiomatic Elixir experience.

## Features

- **Full Specification Support**: Supports both TOML **1.0.0** and **1.1.0** specifications.
- **Native Elixir Types**: Decodes TOML directly into native Elixir types (`DateTime`, `NaiveDateTime`, `Date`, `Time`, `Float`, `Integer`, `Boolean`, `String`, `Map`, `List`).
- **Bidirectional**: Full support for both decoding (TOML to Map) and encoding (Map to TOML).
- **Strict Parsing**: Comprehensive error messages for invalid TOML documents.
- **Spec Selection**: Allows you to choose which TOML version to follow during decoding.
- **Struct Support**: Use the `TomlElixir.Encoder` protocol to encode custom structs via `@derive`.

## Installation

Add `toml_elixir` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:toml_elixir, "~> 3.0.0"}
  ]
end
```

## Usage

### Decoding TOML

Convert a TOML string into an Elixir Map.

```elixir
toml_string = """
title = "TOML Example"

[database]
enabled = true
ports = [ 8000, 8001, 8002 ]
temp_targets = { cpu = 79.5, case = 72.0 }
"""

# Simple decoding
{:ok, data} = TomlElixir.decode(toml_string)
data = TomlElixir.decode!(toml_string)

# Specify TOML version (default is :"1.1.0")
TomlElixir.decode(toml_string, spec: :"1.0.0")
```

### Encoding to TOML

Convert an Elixir Map back into a valid TOML string.

```elixir
data = %{
  "title" => "TOML Example",
  "database" => %{
    "enabled" => true,
    "ports" => [8000, 8001, 8002]
  }
}

{:ok, toml_string} = TomlElixir.encode(data)
toml_string = TomlElixir.encode!(data)
```

### Encoding Structs

You can use the `TomlElixir.Encoder` protocol to allow your structs to be encoded as TOML.

```elixir
defmodule User do
  @derive TomlElixir.Encoder
  defstruct [:name, :age]
end

user = %User{name: "Alice", age: 30}
toml_string = TomlElixir.encode!(%{user: user})
# [user]
# age = 30
# name = "Alice"
```

You can also choose which struct keys are encoded:

```elixir
defmodule User do
  @derive {TomlElixir.Encoder, only: [:name]}
  defstruct [:name, :age, :password]
end

defmodule PublicUser do
  @derive {TomlElixir.Encoder, except: [:password]}
  defstruct [:name, :age, :password]
end
```

Prefer `:only` to avoid leaking new fields added to a struct in the future.

If you do not own the struct module, you can derive the protocol externally:

```elixir
Protocol.derive(TomlElixir.Encoder, NameOfTheStruct, only: [:public_field])
Protocol.derive(TomlElixir.Encoder, NameOfTheStruct, except: [:private_field])
Protocol.derive(TomlElixir.Encoder, NameOfTheStruct)
```

## Type Mapping

| TOML Type | Elixir Type |
| :--- | :--- |
| String | `String.t()` |
| Integer | `Integer.t()` |
| Float | `Float.t()` (plus `:infinity`, `:neg_infinity`, `:nan`) |
| Boolean | `boolean()` |
| Offset Date-Time | `DateTime.t()` |
| Local Date-Time | `NaiveDateTime.t()` |
| Local Date | `Date.t()` |
| Local Time | `Time.t()` |
| Array | `List.t()` |
| Table | `Map.t()` |
| Inline Table | `Map.t()` |

## Contribution

Contributions are welcome! If you find a bug or want to suggest a feature, please open an issue or submit a pull request. Make sure all tests pass before submitting.

```bash
# Run tests
mix test

# Run coverage report
mix coveralls
```

## License

TomlElixir is released under the [MIT License](LICENSE.md).
