# AGENTS.md
<!-- agents-md-version: 1 -->

## CRITICAL

- MUST: Run Mix through `mise x -- mix`; `mise.toml` pins Elixir 1.20.2 and Erlang 29.0.2.
- MUST: Run `mise x -- mix format --check-formatted` before commit.
- MUST: Run `mise x -- mix compile --warnings-as-errors`, `mise x -- mix test`, `mise x -- mix credo`, and `mise x -- mix ex_dna` before PR.
- NEVER: Edit `mix.lock` manually; use Mix dependency commands.
- NEVER: Force-push shared branches.
- NEVER: Publish the Hex package without explicit user authorization.
- NEVER: Read, print, or commit `.env*`, private keys, tokens, or credentials.
- PREFER: The smallest change at the shared parser/encoder boundary over duplicated caller-specific fixes.
- ON FAIL: Read the complete error output before retrying; use the command-specific recovery below.

## Domain & Context

- Goal: Parse and encode TOML 1.0.0 and 1.1.0 using native Elixir types and protocol-based struct projection.
- Type: Library; single Mix package with no application runtime or deployment target.
- License: MIT.
- Public API: `TomlElixir.decode/2`, `decode!/2`, `encode/2`, and `encode!/2` in `lib/toml_elixir.ex`.

## Execution Context

- Run on: Host via the toolchain pinned in `mise.toml`.
- Prefix: `mise x --` for Mix commands.
- Supported runtime: Elixir `>= 1.18.0`; CI covers Elixir 1.18/1.19/1.20 with OTP 27/28/29.

## Commands

```bash
# install toolchain
mise install                                      # ON FAIL: run `mise doctor` and resolve the reported toolchain issue
# install dependencies
mise x -- mix deps.get                            # ON FAIL: run `mise x -- mix deps.tree` and inspect the dependency conflict
# lint/format check
mise x -- mix format --check-formatted            # ON FAIL: run `mise x -- mix format`, then re-run this check
# static analysis
mise x -- mix credo                               # ON FAIL: fix the reported issues, then re-run this check
# duplicate-code analysis
mise x -- mix ex_dna                              # ON FAIL: remove or justify the reported duplication, then re-run this check
# build
mise x -- mix compile --warnings-as-errors        # ON FAIL: fix the first compiler warning, then re-run this command
# test
mise x -- mix test                                # ON FAIL: run `mise x -- mix test --failed`; isolate with a specific `*_test.exs` file
# coverage
mise x -- mix coveralls                           # ON FAIL: run `mise x -- mix test` to separate test failures from coverage setup
```

## Structure

```text
lib/toml_elixir.ex          # public API facade
lib/toml_elixir/            # parser and encoder
lib/toml_elixir/parser/     # recursive parser internals
test/support/               # shared test helpers
test/toml/                  # ExUnit tests and fixtures
test/toml/valid/            # accepted TOML fixtures
test/toml/invalid/          # rejected TOML fixtures
_build/                     # Mix build output (generated -- do not edit)
deps/                       # Mix dependencies (generated -- do not edit)
```

## Patterns

- **Modules:** Use `TomlElixir.*`; keep the four public operations in `TomlElixir` and implementation details below it.
- **Control flow:** Use synchronous functions, pipelines, pattern matching, and recursion; do not add async abstractions to parser or serializer paths.
- **Naming:** Use `snake_case.ex` files, `CamelCase` modules, and `snake_case` functions.
- **Parser:** `TomlElixir.Parser` normalizes input, `Document` performs recursive syntax parsing, `State` traverses binaries, and `Builder`/`Table`/`ArrayTable` construct results. Preserve these boundaries.
- **Encoder:** Extend `TomlElixir.Encoder` for new projections; `TomlElixir.Encoder.Serializer` emits sorted TOML iodata.
- **Errors:** Non-bang public APIs return `{:ok, value} | {:error, exception}`; bang variants raise.
- **Formatting:** `.formatter.exs` applies Styler to Elixir source and tests with 2-space indentation.

## Search

- Code and literals: `rg "Unexpected trailing content" lib/`; files: `rg --files`.

## Testing Strategy

- Runner: ExUnit, started by `test/test_helper.exs`.
- Tests: `test/toml/*_test.exs`; support modules compile from `test/support/` only in the test environment.
- Fixtures: paired `.toml`/`.json` cases under `test/toml/valid/`; invalid TOML under `test/toml/invalid/`.
- Spec coverage: keep TOML 1.0.0 and 1.1.0 behavior separated in their existing spec tests and versioned fixture directories.
- Parser changes: add the smallest valid or invalid fixture that reproduces the behavior.
- Encoder/protocol changes: add focused cases to `encode_test.exs` or `derive_test.exs`.
- Coverage: ExCoveralls via `mix coveralls`; no repository threshold is configured.

## Security

- Struct projection can expose fields: prefer `@derive {TomlElixir.Encoder, only: [:name]}` for allowlisting public fields.
- Do not read or commit secret-bearing files such as `.env*`, `*.pem`, or `*.key`.

## Env

- Toolchain: Elixir 1.20.2 and Erlang 29.0.2 from `mise.toml`.
- Compatibility floor: Elixir 1.18.0 from `mix.exs`.
- No environment variables or external services are required.

## Git

- Commit: short imperative subject without a prefix, matching repository history.
- PR: include a concise description, commands run, and any fixture updates.
- Branches checked by CI: `main` and `master`.

## CI

- Workflow: `.github/workflows/elixir.yml` on pushes and PRs to `main`/`master`.
- Matrix: Elixir 1.18/1.19 and OTP 27/28.
- Checks: dependency install, format, warnings-as-errors compile, Credo, ex_dna, and ExUnit tests.

## Tool Preferences

| Task | Prefer | Avoid |
|------|--------|-------|
| Code discovery | focused `rg` searches | broad filesystem searches |
| Elixir commands | `mise x -- mix ...` | unpinned direct `mix ...` |
| File edits | focused patches | bulk rewrites |
