# Repository Guidelines

## Project Structure & Module Organization

- `lib/` contains the Elixir API and core modules (entry point in `lib/toml_elixir.ex`).
- `test/` contains ExUnit tests and TOML fixtures under `test/toml/` (`valid/`, `invalid/`, and versioned fixture sets).
- Metadata and tooling live in `mix.exs`, `mix.lock`

## Build, Test, and Development Commands

- Use `mise` to install the toolchain defined in `mise.toml` (e.g., `mise install`).
- Run `mix` commands via `mise` (e.g., `mise x -- mix deps.get`).
- `mise x -- mix compile` — compile Elixir/Erlang sources.
- `mise x -- mix test` — run ExUnit tests.
- `mise x -- mix coveralls` — run coverage via ExCoveralls (configured in `mix.exs`).

## Coding Style & Naming Conventions

- Indentation: 2 spaces, no tabs (Elixir and Erlang).
- Elixir modules use `CamelCase` under `TomlElixir.*`; functions use `snake_case`.
- Erlang modules are lowercase (e.g., `toml_lexer`, `toml_parser`).
- Prefer small, focused functions and keep public API in `lib/`.

## Testing Guidelines

- Tests use ExUnit; place new tests in `test/` and name files `*_test.exs`.
- Add TOML fixture cases under `test/toml/valid` or `test/toml/invalid` when expanding parser behavior.
- Run `mix test` before submitting changes; use `mix coveralls` if coverage is relevant.

## Commit & Pull Request Guidelines

- Commit messages are short, imperative summaries (e.g., “Update version to 2.0.1”); avoid prefixes.
- PRs should include a concise description, testing performed (`mix test`, `mix coveralls`, etc.), and note any fixture updates.

## Notes for Contributors

- Keep changes compatible with Elixir `>= 1.18.0` as defined in `mix.exs`.
- If updating lexer/parser sources (`.xrl`/`.yrl`), ensure generated `.erl` files are kept in sync.
