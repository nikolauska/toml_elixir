## Unreleased

### Features

* **Error Locations**: `TomlElixir.Parser.Error` now includes `line`, `column`, and `offset` fields, and its message ends with the line and column. Positions are computed only after a failure, so successful decoding does no extra work.
* **Encoding Error Paths**: Encoding failures now return or raise `TomlElixir.Encoder.Error` with a `path` to the failing value, such as `["servers", 1, "port"]`. Previously the underlying exception, such as `RuntimeError` or `Protocol.UndefinedError`, was returned directly; its message is kept in `reason`.

## 3.2.1 (2026-10-07)

### Fixes

* **ESC escape versioning**: Reject `\e` in basic strings and quoted keys under TOML 1.0.0 while retaining TOML 1.1.0 support. The `\u001B` escape remains valid in both versions.
* **Literal U+FEFF**: Accept literal U+FEFF in strings, quoted keys, and comments in both TOML versions, preserving string and key content and restoring value and key encode/decode round trips. Encoder output is unchanged. Strip only one document-leading BOM; invalid U+FEFF placements remain rejected.

## 3.2.0 (2026-09-26)

### Fixes

* **Zero offset**: Fixes zero offset datetime parsing

### Performance

* **Faster Decoding**: Compared with 3.1.0, reduced median decode time for the zero-offset-normalized 5 MB fixture from 2.85 s to 327.38 ms and for `bench/fixtures/example.toml` from 0.99 ms to 124.61 μs. Reduction counts decreased from 99.39 M to 19.87 M and from 99.54 K to 22.44 K, respectively.
* **Lower Decode Allocations**: Compared with 3.1.0, reduced allocations for the zero-offset-normalized 5 MB fixture from 1.31 GB to 93.13 MB and for the example fixture from 1.33 MB to 83.28 KB.
* **Faster Encoding**: Compared with 3.1.0, reduced median encoding time for `bench/fixtures/5mb-mixed.toml` from 452.39 ms to 86.95 ms and allocations from 245.24 MB to 34.36 MB. The example fixture decreased from 186.15 μs to 16.38 μs, with allocations decreasing from 85.28 KB to 27.89 KB.
* **Faster Integer Decoding**: Compared with 3.1.0, reduced median decode time for a 2,000-integer document from 28.92 ms to 3.97 ms and allocations from 17.02 MB to 2.89 MB.

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
