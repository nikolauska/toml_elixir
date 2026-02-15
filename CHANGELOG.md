## 3.1.0 (TBD)

### Features

* **Encoder Protocol**: Added `TomlElixir.Encoder` protocol to support encoding custom structs via `@derive`.
* **Derive Key Filtering**: Added JSON-style struct field filtering for `TomlElixir.Encoder` via `@derive {TomlElixir.Encoder, only: [...]}` and `@derive {TomlElixir.Encoder, except: [...]}`.

## 3.0.0 (2026-01-10)

### Breaking Changes

* **Renamed API**: `parse/2` and `parse!/2` have been renamed to `decode/2` and `decode!/2` for consistency with other Elixir data libraries.
* **Removed `parse_file`**: `parse_file/2` and `parse_file!/2` were removed. Use `File.read!/1` with `decode/2` instead.

### Features

* **TOML 1.0.0 and 1.1.0 Support**: Added full support for both TOML 1.0.0 and 1.1.0 specifications.
* **Encoding Support**: Added `encode/2` and `encode!/2` to convert Elixir maps back into valid TOML strings.
* **Specification Versioning**: Added `:spec` option to `decode/2` to allow choosing between `:"1.0.0"` and `:"1.1.0"` (default) compliance.
* **Improved Performance**: Internal refactoring for faster parsing.
* **Strict Validation**: Improved error reporting for invalid TOML documents.

## 2.0.1

* Fixed inline table parsing

## 2.0.0

* Full support for TOML 0.4.0 spec
* **to_map** option was removed due to need for map for validation

## 1.1.0

* Added parse_file/2 and parse_file!/2 functions
* More documentation to help using toml tuple list
* **Changed no_parse option to to_map**
  * no_parse option will be removed on 1.2 update

## 1.0.0

First release
