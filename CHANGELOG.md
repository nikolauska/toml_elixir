## Unreleased

### Fixes

* **Zero offset**: Fixes zero offset datetime parsing

### Performance

* **Faster Decoding**: Reduced median decode time for `bench/fixtures/5mb-mixed.toml` from 942.47 ms to 571.90 ms and for `bench/fixtures/example.toml` from 437.65 μs to 306.79 μs. Native UTF-8 validation reduced reductions from 32.87 M to 22.02 M and from 31.37 K to 23.08 K, respectively.
* **Lower Memory Usage**: Reduced measured decode allocations for `bench/fixtures/5mb-mixed.toml` from 288.90 MB to 173.70 MB and for `bench/fixtures/example.toml` from 322.03 KB to 195.65 KB.

## 3.1.0 (2026-02-15)

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
