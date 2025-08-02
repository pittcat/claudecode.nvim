# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

claudecode.nvim - A Neovim plugin that implements the same WebSocket-based MCP protocol as Anthropic's official IDE extensions. Built with pure Lua and zero dependencies.

## Tooling for shell interactions (Install if missing)

Is it about finding FILES? use 'fd'

Is it about finding TEXT/strings? use 'rg'

Is it about finding CODE STRUCTURE? use 'ast-grep',You run in an environment where `ast-grep` is available; whenever a search requires syntax-aware or structural matching, default to `ast-grep --lang lua -p '<pattern>'` (or set `--lang` appropriately) and avoid falling back to text-only tools like `rg` or `grep` unless I explicitly request a plain-text search.

Is it about SELECTING from multiple results? pipe to 'fzf'

Is it about interacting with JSON? use 'jq'

Is it about interacting with YAML or XML? use 'yq'

Is it about analyzing LOG PATTERNS? use 'angle-grinder'

Is it about working with CSV/TSV? use 'xsv'

Is it about viewing CODE with syntax? use 'bat'

## Common Development Commands

### Testing

- `make test` - Run all tests using busted with coverage
- `busted tests/unit/specific_spec.lua` - Run specific test file
- `busted --coverage -v` - Run tests with coverage

### Code Quality

- `make check` - Check Lua syntax and run luacheck
- `make format` - Format code with stylua (or nix fmt if available)
- `luacheck lua/ tests/ --no-unused-args --no-max-line-length` - Direct linting

### Build Commands

- `make` - **RECOMMENDED**: Run formatting, linting, and testing (complete validation)
- `make all` - Run check and format (default target)
- `make test` - Run all tests using busted with coverage
- `make check` - Check Lua syntax and run luacheck
- `make format` - Format code with stylua (or nix fmt if available)
- `make clean` - Remove generated test files
- `make help` - Show available commands

**Best Practice**: Always use `make` at the end of editing sessions for complete validation.

### Development with Nix

- `nix develop` - Enter development shell with all dependencies
- `nix fmt` - Format all files using nix formatter

## Architecture Overview

### Core Components

1. **WebSocket Server** (`lua/claudecode/server/`) - Pure Neovim implementation using vim.loop, RFC 6455 compliant
2. **MCP Tool System** (`lua/claudecode/tools/`) - Implements tools that Claude can execute (openFile, getCurrentSelection, etc.)
3. **Lock File System** (`lua/claudecode/lockfile.lua`) - Creates discovery files for Claude CLI at `~/.claude/ide/`
4. **Selection Tracking** (`lua/claudecode/selection.lua`) - Monitors text selections and sends updates to Claude
5. **Diff Integration** (`lua/claudecode/diff.lua`) - Native Neovim diff support for Claude's file comparisons
6. **Terminal Integration** (`lua/claudecode/terminal.lua`) - Manages Claude CLI terminal sessions
7. **Session Management** (`lua/claudecode/session_manager.lua`) - Parses and manages Claude CLI session files for resume functionality

### WebSocket Server Implementation

- **TCP Server**: `server/tcp.lua` handles port binding and connections
- **Handshake**: `server/handshake.lua` processes HTTP upgrade requests with authentication
- **Frame Processing**: `server/frame.lua` implements RFC 6455 WebSocket frames
- **Client Management**: `server/client.lua` manages individual connections
- **Utils**: `server/utils.lua` provides base64, SHA-1, XOR operations in pure Lua

#### Authentication System

The WebSocket server implements secure authentication using:

- **UUID v4 Tokens**: Generated per session with enhanced entropy
- **Header-based Auth**: Uses `x-claude-code-ide-authorization` header
- **Lock File Discovery**: Tokens stored in `~/.claude/ide/[port].lock` for Claude CLI
- **MCP Compliance**: Follows official Claude Code IDE authentication protocol

### MCP Tools Architecture (✅ FULLY COMPLIANT)

**Complete VS Code Extension Compatibility**: All tools now implement identical behavior and output formats as the official VS Code extension.

**MCP-Exposed Tools** (with JSON schemas):

- `openFile` - Opens files with optional line/text selection (startLine/endLine), preview mode, text pattern matching, and makeFrontmost flag
- `getCurrentSelection` - Gets current text selection from active editor
- `getLatestSelection` - Gets most recent text selection (even from inactive editors)
- `getOpenEditors` - Lists currently open files with VS Code-compatible `tabs` structure
- `openDiff` - Opens native Neovim diff views
- `checkDocumentDirty` - Checks if document has unsaved changes
- `saveDocument` - Saves document with detailed success/failure reporting
- `getWorkspaceFolders` - Gets workspace folder information
- `closeAllDiffTabs` - Closes all diff-related tabs and windows
- `getDiagnostics` - Gets language diagnostics (errors, warnings) from the editor

**Internal Tools** (not exposed via MCP):

- `close_tab` - Internal-only tool for tab management (hardcoded in Claude Code)

**Format Compliance**: All tools return MCP-compliant format: `{content: [{type: "text", text: "JSON-stringified-data"}]}`

### Session Management System

**Claude CLI Session Integration**: claudecode.nvim provides seamless integration with Claude CLI's session storage system.

**Key Features**:
- **Session Discovery**: Automatically finds Claude CLI sessions for the current project directory
- **Visual Selection Interface**: Provides both vim.ui.select and fzf-lua interfaces for session selection
- **Rich Metadata Display**: Shows Modified time, Created time, Message count, Git branch, and Session summary
- **Path Conversion**: Handles directory name mapping between file system and Claude's project storage format
- **Fallback Summary**: Extracts meaningful summaries from sessions without dedicated summary lines

**Session Storage Format**:
- Sessions stored in `~/.claude/projects/[project-path]/` as `.jsonl` files
- Each session contains JSONL lines with message history and metadata
- Project paths converted from `/path/to/project` to `-path-to-project` format
- Handles special cases like `.hidden` directories (`-.hidden` becomes `--hidden`)

**UI Interface**:
- **fzf-lua Integration**: Preferred interface when available, provides fuzzy searching and better UX
- **vim.ui.select Fallback**: Standard Neovim selection interface when fzf-lua not available
- **Relative Time Display**: Shows human-readable time formats ("2h ago", "3 days ago")
- **Structured Layout**: Organized columns matching Claude CLI's native session picker

**Usage**:
```vim
:ClaudeCodeSelectSession  " Opens session selection interface
<leader>ax               " Default key mapping for session selection
```

### Key File Locations

- `lua/claudecode/init.lua` - Main entry point and setup
- `lua/claudecode/config.lua` - Configuration management
- `lua/claudecode/session_manager.lua` - Claude CLI session parsing and management
- `plugin/claudecode.lua` - Plugin loader with version checks
- `tests/` - Comprehensive test suite with unit, component, and integration tests

## MCP Protocol Compliance

### Protocol Implementation Status

- ✅ **WebSocket Server**: RFC 6455 compliant with MCP message format
- ✅ **Tool Registration**: JSON Schema-based tool definitions
- ✅ **Authentication**: UUID v4 token-based secure handshake
- ✅ **Message Format**: JSON-RPC 2.0 with MCP content structure
- ✅ **Error Handling**: Comprehensive JSON-RPC error responses

### VS Code Extension Compatibility

claudecode.nvim implements **100% feature parity** with Anthropic's official VS Code extension:

- **Identical Tool Set**: All 10 VS Code tools implemented
- **Compatible Formats**: Output structures match VS Code extension exactly
- **Behavioral Consistency**: Same parameter handling and response patterns
- **Error Compatibility**: Matching error codes and messages

### Protocol Validation

Run `make test` to verify MCP compliance:

- **Tool Format Validation**: All tools return proper MCP structure
- **Schema Compliance**: JSON schemas validated against VS Code specs
- **Integration Testing**: End-to-end MCP message flow verification

## Testing Architecture

Tests are organized in three layers:

- **Unit tests** (`tests/unit/`) - Test individual functions in isolation
- **Component tests** (`tests/component/`) - Test subsystems with controlled environment
- **Integration tests** (`tests/integration/`) - End-to-end functionality with mock Claude client

Test files follow the pattern `*_spec.lua` or `*_test.lua` and use the busted framework.

### Test Infrastructure

**JSON Handling**: Custom JSON encoder/decoder with support for:

- Nested objects and arrays
- Special Lua keywords as object keys (`["end"]`)
- MCP message format validation
- VS Code extension output compatibility

**Test Pattern**: Run specific test files during development:

```bash
# Run specific tool tests with proper LUA_PATH
export LUA_PATH="./lua/?.lua;./lua/?/init.lua;./?.lua;./?/init.lua;$LUA_PATH"
busted tests/unit/tools/specific_tool_spec.lua --verbose

# Or use make for full validation
make test  # Recommended for complete validation
```

**Coverage Metrics**:

- **320+ tests** covering all MCP tools and core functionality
- **Unit Tests**: Individual tool behavior and error cases
- **Integration Tests**: End-to-end MCP protocol flow
- **Format Tests**: MCP compliance and VS Code compatibility

### Test Organization Principles

- **Isolation**: Each test should be independent and not rely on external state
- **Mocking**: Use comprehensive mocking for vim APIs and external dependencies
- **Coverage**: Aim for both positive and negative test cases, edge cases included
- **Performance**: Tests should run quickly to encourage frequent execution
- **Clarity**: Test names should clearly describe what behavior is being verified

## Authentication Testing

The plugin implements authentication using UUID v4 tokens that are generated for each server session and stored in lock files. This ensures secure connections between Claude CLI and the Neovim WebSocket server.

### Testing Authentication Features

**Lock File Authentication Tests** (`tests/lockfile_test.lua`):

- Auth token generation and uniqueness validation
- Lock file creation with authentication tokens
- Reading auth tokens from existing lock files
- Error handling for missing or invalid tokens

**WebSocket Handshake Authentication Tests** (`tests/unit/server/handshake_spec.lua`):

- Valid authentication token acceptance
- Invalid/missing token rejection
- Edge cases (empty tokens, malformed headers, length limits)
- Case-insensitive header handling

**Server Integration Tests** (`tests/unit/server_spec.lua`):

- Server startup with authentication tokens
- Auth token state management during server lifecycle
- Token validation throughout server operations

**End-to-End Authentication Tests** (`tests/integration/mcp_tools_spec.lua`):

- Complete authentication flow from server start to tool execution
- Authentication state persistence across operations
- Concurrent operations with authentication enabled

### Manual Authentication Testing

**Test Script Authentication Support**:

```bash
# Test scripts automatically detect and use authentication tokens
cd scripts/
./claude_interactive.sh  # Automatically reads auth token from lock file
```

**Authentication Flow Testing**:

1. Start the plugin: `:ClaudeCodeStart`
2. Check lock file contains `authToken`: `cat ~/.claude/ide/*.lock | jq .authToken`
3. Test WebSocket connection with auth: Use test scripts in `scripts/` directory
4. Verify authentication in logs: Set `log_level = "debug"` in config

**Testing Authentication Failures**:

```bash
# Test invalid auth token (should fail)
websocat ws://localhost:PORT --header "x-claude-code-ide-authorization: invalid-token"

# Test missing auth header (should fail)
websocat ws://localhost:PORT

# Test valid auth token (should succeed)
websocat ws://localhost:PORT --header "x-claude-code-ide-authorization: $(cat ~/.claude/ide/*.lock | jq -r .authToken)"
```

### Authentication Logging

Enable detailed authentication logging by setting:

```lua
require("claudecode").setup({
  log_level = "debug"  -- Shows auth token generation, validation, and failures
})
```

Log levels for authentication events:

- **DEBUG**: Server startup authentication state, client connections, handshake processing, auth token details
- **WARN**: Authentication failures during handshake
- **ERROR**: Auth token generation failures, handshake response errors

### Logging Best Practices

- **Connection Events**: Use DEBUG level for routine connection establishment/teardown
- **Authentication Flow**: Use DEBUG for successful auth, WARN for failures
- **User-Facing Events**: Use INFO sparingly for events users need to know about
- **System Errors**: Use ERROR for failures that require user attention

## Development Notes

### Technical Requirements

- Plugin requires Neovim >= 0.8.0
- Uses only Neovim built-ins for WebSocket implementation (vim.loop, vim.json, vim.schedule)
- Zero external dependencies for core functionality
- Optional dependency: folke/snacks.nvim for enhanced terminal support

### Key User Commands

- `:ClaudeCode` - Toggle the Claude Code terminal window
- `:ClaudeCodeFocus` - Smart focus/toggle Claude terminal  
- `:ClaudeCodeSend` - Send current visual selection to Claude
- `:ClaudeCodeAdd <file-path> [start-line] [end-line]` - Add specific file to Claude context
- `:ClaudeCodeStatus` - Check server status and connection info
- `:ClaudeCodeSelectSession` - Open session selection interface to resume from specific Claude CLI session
- `:ClaudeCodeDiffAccept` - Accept diff changes
- `:ClaudeCodeDiffDeny` - Reject diff changes

### Configuration Options

Key configuration options available in `require("claudecode").setup({})`:

- `port_range` - WebSocket server port range (default: {min=10000, max=65535})
- `log_level` - Logging verbosity ("trace", "debug", "info", "warn", "error")
- `terminal.split_side` - Terminal split direction ("left" or "right")
- `terminal.provider` - Terminal provider ("auto", "snacks", or "native")
- `terminal.auto_insert_mode` - Auto enter insert mode when switching to terminal
- `track_selection` - Enable real-time selection tracking (default: true)
- `diff_opts.vertical_split` - Use vertical split for diffs (default: true)

### Security Considerations

- WebSocket server only accepts local connections (127.0.0.1) for security
- Authentication tokens are UUID v4 with enhanced entropy
- Lock files created at `~/.claude/ide/[port].lock` for Claude CLI discovery
- All authentication events are logged for security auditing

### Performance Optimizations

- Selection tracking is debounced to reduce overhead
- WebSocket frame processing optimized for JSON-RPC payload sizes
- Connection pooling and cleanup to prevent resource leaks

### Integration Support

- Terminal integration supports both snacks.nvim and native Neovim terminal
- Compatible with popular file explorers (nvim-tree, oil.nvim, neo-tree)
- Visual selection tracking across different selection modes

### Common Troubleshooting

- **Claude not connecting?** Check `:ClaudeCodeStatus` and verify lock file exists in `~/.claude/ide/` 
- **Authentication issues?** Enable debug logging with `log_level = "debug"` to see token validation
- **Terminal not opening?** Try switching terminal provider with `terminal.provider = "native"`
- **Lock file location?** Check both `~/.claude/ide/` and `$CLAUDE_CONFIG_DIR/ide/` if `CLAUDE_CONFIG_DIR` is set
- **Port conflicts?** Adjust `port_range` in configuration if default ports are occupied

## Release Process

### Version Updates

When updating the version number for a new release, you must update **ALL** of these files:

1. **`lua/claudecode/init.lua`** - Main version table:

   ```lua
   M.version = {
     major = 0,
     minor = 2,  -- Update this
     patch = 0,  -- Update this
     prerelease = nil,  -- Remove for stable releases
   }
   ```

2. **`scripts/claude_interactive.sh`** - Multiple client version references:

   - Line ~52: `"version": "0.2.0"` (handshake)
   - Line ~223: `"version": "0.2.0"` (initialize)
   - Line ~309: `"version": "0.2.0"` (reconnect)

3. **`scripts/lib_claude.sh`** - ClaudeCodeNvim version:

   - Line ~120: `"version": "0.2.0"` (init message)

4. **`CHANGELOG.md`** - Add new release section with:
   - Release date
   - Features with PR references
   - Bug fixes with PR references
   - Development improvements

### Release Commands

```bash
# Get merged PRs since last version
gh pr list --state merged --base main --json number,title,mergedAt,url --jq 'sort_by(.mergedAt) | reverse'

# Get commit history
git log --oneline v0.1.0..HEAD

# Always run before committing
make

# Verify no old version references remain
rg "0\.1\.0" .  # Should only show CHANGELOG.md historical entries
```

## Development Workflow

### Pre-commit Requirements

**ALWAYS run `make` before committing any changes.** This runs code quality checks and formatting that must pass for CI to succeed. Never skip this step - many PRs fail CI because contributors don't run the build commands before committing.

### Recommended Development Flow

1. **Start Development**: Use existing tests and documentation to understand the system
2. **Make Changes**: Follow existing patterns and conventions in the codebase
3. **Validate Work**: Run `make` to ensure formatting, linting, and tests pass
4. **Document Changes**: Update relevant documentation (this file, PROTOCOL.md, etc.)
5. **Commit**: Only commit after successful `make` execution

### MCP Tool Development Guidelines

**Adding New Tools**:

1. **Study Existing Patterns**: Review `lua/claudecode/tools/` for consistent structure
2. **Implement Handler**: Return MCP format: `{content: [{type: "text", text: JSON}]}`
3. **Add JSON Schema**: Define parameters and expose via MCP (if needed)
4. **Create Tests**: Both unit tests and integration tests required
5. **Update Documentation**: Add to this file's MCP tools list

**Tool Testing Pattern**:

```lua
-- All tools should return MCP-compliant format
local result = tool_handler(params)
expect(result).to_be_table()
expect(result.content).to_be_table()
expect(result.content[1].type).to_be("text")
local parsed = json_decode(result.content[1].text)
-- Validate parsed structure matches VS Code extension
```

**Error Handling Standard**:

```lua
-- Use consistent JSON-RPC error format
error({
  code = -32602,  -- Invalid params
  message = "Description of the issue",
  data = "Additional context"
})
```

### Code Quality Standards

- **Test Coverage**: Maintain comprehensive test coverage (currently **320+ tests**, 100% success rate)
- **Zero Warnings**: All code must pass luacheck with 0 warnings/errors
- **MCP Compliance**: All tools must return proper MCP format with JSON-stringified content
- **VS Code Compatibility**: New tools must match VS Code extension behavior exactly
- **Consistent Formatting**: Use `nix fmt` or `stylua` for consistent code style
- **Documentation**: Update CLAUDE.md for architectural changes, PROTOCOL.md for protocol changes

### Development Quality Gates

1. **`make check`** - Syntax and linting (0 warnings required)
2. **`make test`** - All tests passing (320/320 success rate required)
3. **`make format`** - Consistent code formatting
4. **MCP Validation** - Tools return proper format structure
5. **Integration Test** - End-to-end protocol flow verification

## Branch-Specific Features Protection

### add-unsafe-command Branch Features

**IMPORTANT**: When merging from main branch, the following features MUST be preserved:

1. **Monitoring System** - All `ClaudeCodeMonitoring*` commands and related modules
2. **Notification System** - macOS notification support with `notification` config
3. **Anti-Flicker Optimizations** - `fix_display_corruption` and related terminal settings
4. **Special Commands** - `ClaudeCodeUnsafe` and `ClaudeCodeContinue` commands
5. **Buffer Refresh** - `utils.refresh_buffers` in save_document tool

**Merge Strategy**: Always use `git merge --no-commit main` and manually resolve conflicts to preserve all existing functionality. See `BRANCH_FEATURES.md` for detailed merge instructions.

## Development Troubleshooting

### Common Issues

**Test Failures with LUA_PATH**:

```bash
# Tests can't find modules - use proper LUA_PATH
export LUA_PATH="./lua/?.lua;./lua/?/init.lua;./?.lua;./?/init.lua;$LUA_PATH"
busted tests/unit/specific_test.lua
```

**JSON Format Issues**:

- Ensure all tools return: `{content: [{type: "text", text: "JSON-string"}]}`
- Use `vim.json.encode()` for proper JSON stringification
- Test JSON parsing with custom test decoder in `tests/busted_setup.lua`

**MCP Tool Registration**:

- Tools with `schema = nil` are internal-only
- Tools with schema are exposed via MCP
- Check `lua/claudecode/tools/init.lua` for registration patterns

**Authentication Testing**:

```bash
# Verify auth token generation
cat ~/.claude/ide/*.lock | jq .authToken

# Test WebSocket connection
websocat ws://localhost:PORT --header "x-claude-code-ide-authorization: $(cat ~/.claude/ide/*.lock | jq -r .authToken)"
```
