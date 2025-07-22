# Gemini Project Overview: claudecode.nvim

This document provides a summary of the `claudecode.nvim` project, a Neovim plugin for integrating with the Claude Code AI assistant.

## Project Purpose

`claudecode.nvim` is a Neovim plugin that provides IDE integration for Anthropic's Claude Code. It allows Neovim users to interact with the Claude Code AI assistant directly within the editor. The plugin implements the same WebSocket-based MCP (Model Context Protocol) as the official VS Code and JetBrains extensions.

The project is written in pure Lua and has zero external dependencies, using `vim.loop` for asynchronous operations.

## Project Structure

The project is structured as a standard Neovim plugin:

- `plugin/claudecode.lua`: The main entry point for the plugin.
- `lua/claudecode/`: The core Lua modules for the plugin.
  - `init.lua`: Main plugin logic and setup.
  - `config.lua`: Handles user configuration.
  - `server/`: Implements the WebSocket server for communication with the Claude Code CLI.
  - `tools/`: Implements the MCP tools that Claude can invoke (e.g., `openFile`, `openDiff`).
  - `diff.lua`: Handles the diff view integration.
  - `terminal.lua`: Manages the integrated terminal running the Claude Code CLI.
- `tests/`: Contains the test suite.
  - `unit/`: Unit tests for individual modules.
  - `integration/`: Integration tests for the plugin's features.
  - `busted_setup.lua`: Setup for the `busted` test framework.
- `Makefile`: Contains helper scripts for development tasks like testing, linting, and formatting.

## Key Technologies

- **Language:** Lua
- **Framework:** Neovim Plugin API
- **Testing:** `busted`
- **Linting:** `luacheck`
- **Formatting:** `stylua` (via `nix fmt`)

## Development Commands

The `Makefile` provides several commands for development:

- **Run all tests:**
  ```bash
  make test
  ```
- **Run linter:**
  ```bash
  make check
  ```
- **Format code:**
  ```bash
  make format
  ```

## How to Run a Single Test File

To run a specific test file, use the following command pattern:

```bash
nvim --headless -u tests/minimal_init.lua -c "lua require('tests.unit.config_spec')"
```
