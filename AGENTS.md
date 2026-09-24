# Working in toml_elixir

This is a Mix library for parsing and encoding TOML 1.0.0 and 1.1.0. Work from the repository root. Use `mise x -- mix ...` for Mix commands; `mise.toml` pins Elixir 1.20.2 and Erlang 29.0.2. The library supports Elixir `>= 1.18.0`.

## Where changes belong

- `lib/toml_elixir.ex` exposes `decode/2`, `decode!/2`, `encode/2`, and `encode!/2`. Non-bang calls return `{:ok, value}` or `{:error, exception}`; bang calls raise.
- Parsing flows through `TomlElixir.Parser` (input normalization), `Parser.Document` (syntax), `Parser.State` (binary traversal), and `Parser.Builder`/`Table`/`ArrayTable` (result construction). Keep fixes at the shared parser boundary when possible rather than duplicating them in callers.
- Encoding uses the `TomlElixir.Encoder` protocol for value and struct projection and `TomlElixir.Encoder.Serializer` for sorted TOML output. Prefer `@derive {TomlElixir.Encoder, only: [:public_field]}` for structs: new fields should not become public by accident.
- Keep implementation under `lib/toml_elixir/`; tests live in `test/toml/`. Parser cases use `.toml`/`.json` pairs in `test/toml/valid/` or rejection cases in `test/toml/invalid/`; keep version-specific behavior in the existing 1.0.0 and 1.1.0 spec tests and fixtures. Encoder and derivation cases belong in `test/toml/encode_test.exs` and `test/toml/derive_test.exs`.

## Working and checking

- Preserve synchronous parser and serializer flow. Follow existing Elixir naming and the Styler configuration in `.formatter.exs`.
- For a local change, run the relevant test or scenario and fix failures caused by the change. Local tests use repository fixtures and do not require a service or production access; do not stop for approval between local test/fix cycles.
- Before committing, run `mise x -- mix format --check-formatted`.
- Before opening a PR, run `mise x -- mix compile --warnings-as-errors`, `mise x -- mix test`, `mise x -- mix credo`, and `mise x -- mix ex_dna`. If a check fails, read its complete output, fix the cause, and rerun the affected check. CI runs these checks plus formatting on `main` and `master`.
- Install the pinned toolchain with `mise install` and dependencies with `mise x -- mix deps.get` only when needed. Do not edit `mix.lock` manually; use Mix dependency commands.

## Boundaries

- Do not read, print, or commit `.env*`, private keys, tokens, or credentials; `_build/` and `deps/` are generated output, not source.
- Do not publish the Hex package without explicit authorization or force-push shared branches.
- Use a short imperative commit subject without a prefix. For PRs, describe changes, checks actually run, and fixture updates.
