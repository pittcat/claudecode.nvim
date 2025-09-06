# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

claudecode.nvim - A Neovim plugin that implements the same WebSocket-based MCP protocol as Anthropic's official IDE extensions. Built with pure Lua and zero dependencies.

## Common Development Commands

### Before Committing
- `make` - **ALWAYS RUN BEFORE COMMITTING**: Runs format, check, and test
- `make check` - Check Lua syntax and run luacheck (must have 0 warnings)
- `make format` - Format code with stylua or nix fmt
- `make clean` - Remove generated test files (luacov reports)

### Testing
- `make test` - Run all tests using busted with coverage (320+ tests)
- `busted tests/unit/specific_spec.lua` - Run specific test file
- `busted --coverage -v` - Run tests with verbose output and coverage

**Running specific tests**:
```bash
# Set proper LUA_PATH for test modules
export LUA_PATH="./lua/?.lua;./lua/?/init.lua;./?.lua;./?/init.lua;$LUA_PATH"
busted tests/unit/tools/specific_tool_spec.lua --verbose
```

### Development with Nix
- `nix develop` - Enter development shell with all dependencies
- `nix develop .#ci -c make test` - Run tests in CI environment
- `nix fmt` - Format all files using nix formatter

### Integration Testing with Fixtures

The `fixtures/` directory contains test Neovim configurations:

```bash
source fixtures/nvim-aliases.sh
vv oil        # Test with oil.nvim file explorer
vv nvim-tree  # Test with nvim-tree.lua
vv mini-files # Test with mini.files
vve oil       # Edit mode for debugging
list-configs  # Show available configurations
```

## Architecture Overview

### Core Components

1. **WebSocket Server** (`lua/claudecode/server/`)
   - Pure Lua RFC 6455 implementation using vim.loop
   - Authentication via UUID v4 tokens in lock files
   - TCP server binds to localhost only (127.0.0.1)

2. **MCP Tool System** (`lua/claudecode/tools/`)
   - 10 VS Code-compatible tools (openFile, openDiff, getCurrentSelection, etc.)
   - All tools return MCP format: `{content: [{type: "text", text: "JSON-string"}]}`
   - JSON schemas for tool validation

3. **Lock File System** (`lua/claudecode/lockfile.lua`)
   - Creates discovery files at `~/.claude/ide/[port].lock`
   - Contains authToken, port, workspace info
   - Cleaned up automatically on exit

4. **Session Management** (`lua/claudecode/session_manager.lua`)
   - Parses Claude CLI sessions from `~/.claude/projects/`
   - Path conversion: `/path/to/project` → `-path-to-project`
   - Empty session detection and blocking
   - Resume with `--ide` parameter

5. **Terminal Integration** (`lua/claudecode/terminal.lua`)
   - Providers: snacks (preferred), native, external
   - Multiple command support (switch between Claude implementations)
   - CWD control: git_repo_cwd, cwd, cwd_provider

6. **Diff System** (`lua/claudecode/diff.lua`)
   - Native Neovim diff views
   - Accept/reject with `:w`/`:q` or commands
   - Configuration: keep_terminal_focus, open_in_new_tab

### Branch-Specific Features (add-unsafe-command)

This branch includes experimental features:
- **Monitoring System** (`lua/claudecode/monitoring/`) - WebSocket/terminal/tool call monitoring
- **Notification System** (`lua/claudecode/utils/notification.lua`) - macOS notifications for task completion  
- **Anti-Flicker Core** (`lua/claudecode/anti_flicker.lua`) - Terminal display optimization
- **Multiple Commands** - Switch between different Claude implementations
- **Special Commands** - ClaudeCodeUnsafe, ClaudeCodeContinue

## Key File Locations

- `lua/claudecode/init.lua` - Main entry point, version management
- `lua/claudecode/config.lua` - Configuration and defaults
- `lua/claudecode/tools/init.lua` - MCP tool registry and handlers
- `tests/busted_setup.lua` - Custom JSON decoder for tests
- `scripts/claude_interactive.sh` - WebSocket client for testing
- `scripts/lib_claude.sh` - Shared test utilities
- `.luacheckrc` - Luacheck configuration
- `.stylua.toml` - Stylua formatting configuration

## MCP Protocol Implementation

All tools follow VS Code extension compatibility:

- **Input**: JSON-RPC 2.0 messages with tool parameters
- **Output**: MCP format with JSON-stringified content
- **Authentication**: WebSocket header `x-claude-code-ide-authorization`
- **Error Format**: JSON-RPC error codes (-32602 for invalid params)

Example tool implementation pattern:
```lua
M.handlers.openFile = function(params)
  -- Validation
  if not params.filePath then
    error({code = -32602, message = "filePath is required"})
  end
  
  -- Implementation
  vim.cmd("edit " .. params.filePath)
  
  -- Return MCP format
  return {
    content = {{
      type = "text",
      text = vim.json.encode({success = true})
    }}
  }
end
```

## Code Style and Conventions

### Lua Formatting
- Use stylua with project configuration (column_width=120, indent=2 spaces)
- Quote style: AutoPreferDouble
- Call parentheses: Always
- Sort requires: Enabled

### Luacheck Rules
- Standard: luajit+busted
- Max line length: 120
- Globals: vim, expect, assert_contains, assert_not_contains, spy

### Module Pattern
```lua
local M = {}
-- module implementation
return M
```

## Testing Requirements

### Before Committing

1. **Always run `make`** - This ensures format, lint, and all tests pass
2. **Check test coverage** - Currently 320+ tests with 100% pass rate
3. **Verify MCP compliance** - Tools must return proper format

### Session Management Testing

When modifying session-related code, test:
- Path conversion (dots, hidden dirs, special chars)
- Empty session detection and blocking
- `--ide` parameter inclusion in resume
- Both fzf-lua and vim.ui.select interfaces

### Manual Testing Checklist

- [ ] `:ClaudeCodeStart` starts server successfully
- [ ] `:ClaudeCodeStatus` shows running status
- [ ] `:ClaudeCodeSelectSession` lists sessions correctly
- [ ] Lock file created at `~/.claude/ide/`
- [ ] Authentication token in lock file is valid UUID

## Development Workflow

1. **Make changes** following existing patterns
2. **Run specific tests** for modified components
3. **Run `make`** for complete validation
4. **Update version** in all required files (see Version Updates)
5. **Update CHANGELOG.md** with changes

## Version Updates

When updating version, modify ALL these files:
- `lua/claudecode/init.lua` - M.version table
- `scripts/claude_interactive.sh` - Lines ~52, ~223, ~309
- `scripts/lib_claude.sh` - Line ~120
- `CHANGELOG.md` - Add release notes

## Debug Logging

Enable detailed logging:
```lua
require("claudecode").setup({
  log_level = "debug",  -- or "trace" for maximum verbosity
})
```

Check logs for:
- Authentication token generation/validation
- WebSocket handshake processing
- Tool execution and responses
- Session discovery and parsing