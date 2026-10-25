# Working in toml_elixir

This is a Mix library for parsing and encoding TOML 1.0.0 and 1.1.0. Work from the repository root. Use `mise x -- mix ...` for Mix commands; `mise.toml` pins the Elixir and Erlang versions. The library supports Elixir `>= 1.18.0`, and CI tests Elixir 1.18–1.20 on OTP 26–29, so avoid APIs newer than Elixir 1.18.

## Where changes belong

- `lib/toml_elixir.ex` exposes `decode/2`, `decode!/2`, `encode/2`, `encode!/2`, `encode_to_iodata/2`, and `encode_to_iodata!/2`. Non-bang calls return `{:ok, value}` or `{:error, exception}`; bang calls raise.
- Parsing flows through `TomlElixir.Parser` (input normalization), `Parser.Document` (syntax), `Parser.State` (binary traversal), `Parser.Builder`/`Table`/`ArrayTable` (result construction), and `Parser.Convert` (post-parse decode options). Keep fixes at the shared parser boundary when possible rather than duplicating them in callers.
- Encoding lives in `lib/toml_elixir/encoder.ex`: the `TomlElixir.Encoder` protocol projects values and structs, and `TomlElixir.Encoder.Serializer` writes sorted TOML output. Prefer `@derive {TomlElixir.Encoder, only: [:public_field]}` for structs: new fields should not become public by accident.
- Keep implementation under `lib/toml_elixir/`; tests live in `test/toml/`. Encoder and derivation cases belong in `test/toml/encode_test.exs` and `test/toml/derive_test.exs`; decode option and error cases belong in the matching `test/toml/decode_*_test.exs`.
- Parser cases use `.toml`/`.json` pairs in `test/toml/valid/` or rejection cases in `test/toml/invalid/`. A fixture only runs when its path is listed in `test/toml/files-toml-1.0.0` and/or `test/toml/files-toml-1.1.0`, so add it to each spec version it applies to. Fixtures mirror upstream toml-test; keep version-specific behavior in those lists rather than in new test files.
- For user-visible changes, add an entry under `## Unreleased` in `CHANGELOG.md`, matching the existing style.
- For parser or serializer performance work, compare before and after with `mise x -- mix run bench/decode.exs` or `mise x -- mix run bench/encode.exs` (Benchee, inputs from `bench/fixtures/*.toml`).

## Working and checking

- Preserve synchronous parser and serializer flow. Follow existing Elixir naming and the Styler configuration in `.formatter.exs`.
- For a local change, run the relevant test or scenario and fix failures caused by the change. Local tests use repository fixtures and do not require a service or production access; do not stop for approval between local test/fix cycles.
- Before committing, run `mise x -- mix format --check-formatted`.
- Before opening a PR, run `mise x -- mix compile --warnings-as-errors`, `mise x -- mix test`, `mise x -- mix credo`, and `mise x -- mix ex_dna`. If a check fails, read its complete output, fix the cause, and rerun the affected check. CI runs these checks plus formatting on pushes and PRs to `master`.
- Install the pinned toolchain with `mise install` and dependencies with `mise x -- mix deps.get` only when needed. Do not edit `mix.lock` manually; use Mix dependency commands.

## Boundaries

- Do not read, print, or commit `.env*`, private keys, tokens, or credentials; `_build/`, `deps/`, and `doc/` are generated output, not source.
- Do not publish the Hex package without explicit authorization or force-push shared branches.
- Use a short imperative commit subject without a prefix. For PRs, describe changes, checks actually run, and fixture updates.
