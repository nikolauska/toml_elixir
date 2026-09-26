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
