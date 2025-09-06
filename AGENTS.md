# Repository Guidelines

## Project Structure & Module Organization
- `lua/claudecode/`: Core plugin (server, tools, diff, terminal, config). Example: `lua/claudecode/server/handshake.lua`.
- `plugin/`: Load guard and auto-setup (`plugin/claudecode.lua`).
- `tests/`: Unit/integration specs and helpers (`*_spec.lua`, `*_test.lua`).
- `fixtures/`: Minimal Neovim configs for manual/integration checks.
- `docs/`: Architecture and troubleshooting references.

## Build, Test, and Development Commands
- `make check`: Syntax + `luacheck` over `lua/` and `tests/`.
- `make format`: Format with `nix fmt` or `stylua` fallback.
- `make test`: Run `busted` tests (uses `LUA_PATH` and optional `luacov`).
- Example single test: `LUA_PATH="./lua/?.lua;./lua/?/init.lua;./?.lua;./?/init.lua;;" busted -v tests/unit/config_spec.lua`.
- Helpful: `make help` lists available targets. Nix users may `nix develop` for pinned tools.

## Coding Style & Naming Conventions
- Indentation: 2 spaces; max line length 120.
- Quotes: Prefer double (Stylua `quote_style = AutoPreferDouble`).
- Linting: `luacheck` with `std = luajit+busted`; see `.luacheckrc` for globals.
- Files/modules: snake_case under `lua/claudecode/...` (e.g., `visual_commands.lua`).
- Public APIs: return tables; avoid global state; log meaningful errors.

## Testing Guidelines
- Framework: `busted`; coverage via `luacov` if installed.
- Naming: place tests in `tests/` using `*_spec.lua` or `*_test.lua`.
- Run all: `make test`. Add focused specs near corresponding module (mirror path where possible).
- Headless example: `nvim --headless -u tests/minimal_init.lua -c "lua require('tests.unit.config_spec')"`.

## Commit & Pull Request Guidelines
- Commit style: Conventional Commits (`feat:`, `fix:`, `docs:`, `refactor:`, `chore:`). Keep subject concise; add context in body; reference issues (`#123`).
- PRs: clear description, motivation, before/after behavior, linked issues; include tests, docs updates, and screenshots/log snippets when UI/terminal behavior changes.
- CI: ensure `make check` and `make test` pass locally before opening PR.

## Security & Configuration Tips
- Do not commit tokens or local CLI paths with secrets. Prefer using `opts.terminal_cmd` in user config rather than hardcoding.
- When testing local Claude installs, verify with `which claude` and avoid shell-only aliases that Neovim cannot see.

