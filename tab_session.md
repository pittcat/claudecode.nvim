# Tab 级 Claude Code Session 完整实现方案

## 一、问题诊断

### 核心问题总结

**主要问题**：当前实现虽然可以为每个 tab 创建独立的终端进程，但 **WebSocket 消息路由使用 broadcast**，导致：
- Tab A 执行 `ClaudeCodeSend` 时，所有 tab 的 Claude session 都会收到消息
- 无法实现真正的 tab 级隔离

**根本原因**：
1. 所有 tab 的 Claude CLI 连接到同一个 WebSocket server
2. `broadcast_at_mention()` 使用 `broadcast()` 发送给所有连接的客户端
3. 缺少 session 标识来区分不同 tab 的连接

**解决方案**：
- 实现 **Session ID 机制**，为每个连接分配 session ID（tab 模式下是 tab number）
- 将 `broadcast()` 改为 `send_to_session()`，实现定向发送
- 在终端启动时通过环境变量传递 session ID

---

### 当前代码存在的问题（详细）

1. **terminal.lua 没有生成和传递 scope_key**
   - `build_config()` 函数只处理了 cwd，完全没有 scope_key 逻辑
   - 导致所有 provider 收到的配置都没有 scope 信息

2. **所有 provider 都使用单例状态**
   - `snacks.lua`: `local terminal = nil` (单例)
   - `native.lua`: `local bufnr/winid/jobid = nil` (单例)
   - 所有 tab 共享同一个终端实例

3. **没有 Tab 关闭监听**
   - 缺少 `TabLeave` 事件处理
   - 关闭 tab 时不会清理对应的终端进程

4. **send 操作不感知 scope**
   - `send_at_mention` 直接 broadcast，没有检查当前 tab 的 session

---

## 二、配置项设计

### 在 terminal.lua 的 defaults 中添加

```lua
---@type ClaudeCodeTerminalConfig
local defaults = {
  split_side = "right",
  split_width_percentage = 0.30,
  provider = "auto",
  show_native_term_exit_tip = true,
  terminal_cmd = nil,
  provider_opts = {
    external_terminal_cmd = nil,
  },
  auto_close = true,
  env = {},
  snacks_win_opts = {},
  cwd = nil,
  git_repo_cwd = false,
  cwd_provider = nil,
  
  -- ✅ 新增：session 隔离级别
  session_scope = "global",  -- "global" | "tab"
}
```

### 在 types.lua 中添加类型定义

```lua
-- Terminal configuration
---@class ClaudeCodeTerminalConfig
---@field split_side ClaudeCodeSplitSide
---@field split_width_percentage number
---@field provider ClaudeCodeTerminalProviderName|ClaudeCodeTerminalProvider
---@field show_native_term_exit_tip boolean
---@field terminal_cmd string?
---@field provider_opts ClaudeCodeTerminalProviderOptions?
---@field auto_close boolean
---@field env table<string, string>
---@field snacks_win_opts snacks.win.Config
---@field cwd string|nil
---@field git_repo_cwd boolean|nil
---@field cwd_provider? ClaudeCodeCwdProvider
---@field session_scope "global"|"tab"  -- ✅ 新增
---@field scope_key? string|number      -- ✅ 新增（内部使用）
```

---

## 三、详细修改步骤

### 步骤 1: 修改 `lua/claudecode/terminal.lua`

#### 1.1 添加 scope_key 生成函数（在文件顶部，defaults 定义之后）

```lua
---Gets the current scope key based on session_scope config
---@return string|number scope_key "global" or current tabpage number
local function get_scope_key()
  if defaults.session_scope == "tab" then
    return vim.api.nvim_get_current_tabpage()
  else
    return "global"
  end
end
```

#### 1.2 修改 `build_config()` 函数（约在第 40-80 行）

**定位代码**：找到 `local function build_config(opts_override)` 函数

**修改前**：
```lua
local function build_config(opts_override)
  local effective_config = vim.deepcopy(defaults)
  if type(opts_override) == "table" then
    -- ... 验证和合并逻辑 ...
  end
  
  -- 解析 cwd 逻辑...
  local cwd_ctx = { ... }
  local resolved_cwd = nil
  -- ... cwd 解析 ...

  return {
    split_side = effective_config.split_side,
    split_width_percentage = effective_config.split_width_percentage,
    auto_close = effective_config.auto_close,
    snacks_win_opts = effective_config.snacks_win_opts,
    cwd = resolved_cwd,
  }
end
```

**修改后**：
```lua
local function build_config(opts_override)
  local effective_config = vim.deepcopy(defaults)
  if type(opts_override) == "table" then
    -- ... 现有的验证和合并逻辑保持不变 ...
  end
  
  -- ✅ 新增：生成 scope_key
  local scope_key = get_scope_key()
  
  -- 解析 cwd 逻辑（保持不变）...
  local cwd_ctx = { ... }
  local resolved_cwd = nil
  -- ... cwd 解析 ...

  return {
    split_side = effective_config.split_side,
    split_width_percentage = effective_config.split_width_percentage,
    auto_close = effective_config.auto_close,
    snacks_win_opts = effective_config.snacks_win_opts,
    cwd = resolved_cwd,
    scope_key = scope_key,  -- ✅ 新增：传递给 provider
  }
end
```

#### 1.3 修改 `setup()` 函数 - 添加配置验证和 Tab 监听（约在第 200-250 行）

**定位代码**：找到 `function M.setup(user_term_config, p_terminal_cmd, p_env)` 函数

**在函数末尾（`get_provider().setup(defaults)` 之后）添加**：

```lua
function M.setup(user_term_config, p_terminal_cmd, p_env)
  -- ... 现有的 setup 逻辑全部保持不变 ...
  
  -- ✅ 新增：验证 session_scope 配置
  if user_term_config and user_term_config.session_scope then
    if user_term_config.session_scope == "global" or user_term_config.session_scope == "tab" then
      defaults.session_scope = user_term_config.session_scope
    else
      vim.notify(
        "claudecode.terminal.setup: Invalid session_scope: " .. tostring(user_term_config.session_scope) 
          .. ". Must be 'global' or 'tab'. Using default 'global'.",
        vim.log.levels.WARN
      )
      defaults.session_scope = "global"
    end
  end
  
  -- Setup providers with config
  get_provider().setup(defaults)
  
  -- ✅ 新增：Tab 关闭监听（仅在 tab 模式下）
  if defaults.session_scope == "tab" then
    local group = vim.api.nvim_create_augroup("ClaudeCodeTabSession", { clear = true })
    
    vim.api.nvim_create_autocmd("TabLeave", {
      group = group,
      callback = function()
        local closing_tab = vim.api.nvim_get_current_tabpage()
        
        -- 延迟 100ms 检查 tab 是否真的关闭了
        vim.defer_fn(function()
          if not vim.api.nvim_tabpage_is_valid(closing_tab) then
            -- Tab 已关闭，通知 provider 清理
            local provider = get_provider()
            if provider._cleanup_scope then
              provider._cleanup_scope(closing_tab)
            end
          end
        end, 100)
      end,
      desc = "Clean up Claude Code session when tab is closed",
    })
    
    -- 添加 VimLeavePre 确保退出时清理所有 session
    vim.api.nvim_create_autocmd("VimLeavePre", {
      group = group,
      callback = function()
        local provider = get_provider()
        if provider._cleanup_all_scopes then
          provider._cleanup_all_scopes()
        end
      end,
      desc = "Clean up all Claude Code sessions on exit",
    })
  end
end
```

---

### 步骤 2: 修改 `lua/claudecode/terminal/snacks.lua`

#### 2.1 修改模块级变量（文件顶部）

**定位代码**：找到 `local terminal = nil` 这行

**修改前**：
```lua
local M = {}

local snacks_available, Snacks = pcall(require, "snacks")
local utils = require("claudecode.utils")
local terminal = nil  -- ❌ 单例
```

**修改后**：
```lua
local M = {}

local snacks_available, Snacks = pcall(require, "snacks")
local utils = require("claudecode.utils")

-- ✅ 改为状态表：key -> terminal instance
local terminals_by_key = {}
```

#### 2.2 添加辅助函数（在 `is_available()` 之后）

```lua
--- @return boolean
local function is_available()
  return snacks_available and Snacks and Snacks.terminal ~= nil
end

-- ✅ 新增：按 scope key 获取终端
---@param scope_key string|number
---@return table|nil
local function get_terminal_for_scope(scope_key)
  return terminals_by_key[scope_key]
end

-- ✅ 新增：按 scope key 设置终端
---@param scope_key string|number
---@param term_instance table|nil
local function set_terminal_for_scope(scope_key, term_instance)
  terminals_by_key[scope_key] = term_instance
end

-- ✅ 新增：按 scope key 清理终端
---@param scope_key string|number
local function clear_terminal_for_scope(scope_key)
  terminals_by_key[scope_key] = nil
end

-- ✅ 新增：获取当前 scope key
---@return string|number
local function get_current_scope_key()
  local terminal_mod = require("claudecode.terminal")
  if terminal_mod.defaults and terminal_mod.defaults.session_scope == "tab" then
    return vim.api.nvim_get_current_tabpage()
  else
    return "global"
  end
end
```

#### 2.3 修改 `setup_terminal_events()` 函数

**定位代码**：找到 `local function setup_terminal_events(term_instance, config)` 函数

**修改前**：
```lua
local function setup_terminal_events(term_instance, config)
  local logger = require("claudecode.logger")

  if config.auto_close then
    term_instance:on("TermClose", function()
      if vim.v.event.status ~= 0 then
        logger.error("terminal", "Claude exited with code " .. vim.v.event.status)
      end

      terminal = nil  -- ❌ 清理单例
      vim.schedule(function()
        term_instance:close({ buf = true })
        vim.cmd.checktime()
      end)
    end, { buf = true })
  end

  term_instance:on("BufWipeout", function()
    logger.debug("terminal", "Terminal buffer wiped")
    terminal = nil  -- ❌ 清理单例
  end, { buf = true })
end
```

**修改后**：
```lua
---Setup event handlers for terminal instance
---@param term_instance table The Snacks terminal instance
---@param config table Configuration options
---@param scope_key string|number The scope key for this terminal  -- ✅ 新增参数
local function setup_terminal_events(term_instance, config, scope_key)
  local logger = require("claudecode.logger")

  if config.auto_close then
    term_instance:on("TermClose", function()
      if vim.v.event.status ~= 0 then
        logger.error("terminal", "Claude exited with code " .. vim.v.event.status)
      end

      -- ✅ 清理对应 scope 的终端
      clear_terminal_for_scope(scope_key)
      vim.schedule(function()
        term_instance:close({ buf = true })
        vim.cmd.checktime()
      end)
    end, { buf = true })
  end

  term_instance:on("BufWipeout", function()
    logger.debug("terminal", "Terminal buffer wiped for scope:", scope_key)
    clear_terminal_for_scope(scope_key)  -- ✅ 清理对应 scope
  end, { buf = true })
end
```

#### 2.4 修改 `M.open()` 函数（核心修改）

**定位代码**：找到 `function M.open(cmd_string, env_table, config, focus)` 函数

**修改前**：
```lua
function M.open(cmd_string, env_table, config, focus)
  if not is_available() then
    vim.notify("Snacks.nvim terminal provider selected but Snacks.terminal not available.", vim.log.levels.ERROR)
    return
  end

  focus = utils.normalize_focus(focus)

  if terminal and terminal:buf_valid() then
    -- 终端已存在，显示/聚焦
    if not terminal.win or not vim.api.nvim_win_is_valid(terminal.win) then
      terminal:toggle()
      if focus then
        terminal:focus()
        -- ...
      end
    else
      if focus then
        terminal:focus()
        -- ...
      end
    end
    return
  end

  -- 创建新终端
  local opts = build_opts(config, env_table, focus)
  local term_instance = Snacks.terminal.open(cmd_string, opts)
  if term_instance and term_instance:buf_valid() then
    setup_terminal_events(term_instance, config)
    terminal = term_instance
  else
    terminal = nil
    -- 错误处理...
  end
end
```

**修改后**：
```lua
function M.open(cmd_string, env_table, config, focus)
  if not is_available() then
    vim.notify("Snacks.nvim terminal provider selected but Snacks.terminal not available.", vim.log.levels.ERROR)
    return
  end

  focus = utils.normalize_focus(focus)
  
  -- ✅ 获取 scope key
  local scope_key = config.scope_key or "global"
  local terminal = get_terminal_for_scope(scope_key)  -- ✅ 按 key 获取

  if terminal and terminal:buf_valid() then
    -- 终端已存在，显示/聚焦
    if not terminal.win or not vim.api.nvim_win_is_valid(terminal.win) then
      terminal:toggle()
      if focus then
        terminal:focus()
        local term_buf_id = terminal.buf
        if term_buf_id and vim.api.nvim_buf_get_option(term_buf_id, "buftype") == "terminal" then
          if terminal.win and vim.api.nvim_win_is_valid(terminal.win) then
            vim.api.nvim_win_call(terminal.win, function()
              vim.cmd("startinsert")
            end)
          end
        end
      end
    else
      if focus then
        terminal:focus()
        local term_buf_id = terminal.buf
        if term_buf_id and vim.api.nvim_buf_get_option(term_buf_id, "buftype") == "terminal" then
          if terminal.win and vim.api.nvim_win_is_valid(terminal.win) then
            vim.api.nvim_win_call(terminal.win, function()
              vim.cmd("startinsert")
            end)
          end
        end
      end
    end
    return
  end

  -- 创建新终端
  local opts = build_opts(config, env_table, focus)
  local term_instance = Snacks.terminal.open(cmd_string, opts)
  
  if term_instance and term_instance:buf_valid() then
    setup_terminal_events(term_instance, config, scope_key)  -- ✅ 传递 scope_key
    set_terminal_for_scope(scope_key, term_instance)  -- ✅ 按 key 保存
  else
    -- 错误处理保持不变...
    local logger = require("claudecode.logger")
    local error_details = {}
    if not term_instance then
      table.insert(error_details, "Snacks.terminal.open() returned nil")
    elseif not term_instance:buf_valid() then
      table.insert(error_details, "terminal instance is invalid")
    end

    local context = string.format("cmd='%s', opts=%s", cmd_string, vim.inspect(opts))
    local error_msg = string.format(
      "Failed to open Claude terminal using Snacks. Details: %s. Context: %s",
      table.concat(error_details, ", "),
      context
    )
    vim.notify(error_msg, vim.log.levels.ERROR)
    logger.debug("terminal", error_msg)
  end
end
```

#### 2.5 修改 `M.close()` 函数

**修改前**：
```lua
function M.close()
  if not is_available() then
    return
  end
  if terminal and terminal:buf_valid() then
    terminal:close()
  end
end
```

**修改后**：
```lua
function M.close()
  if not is_available() then
    return
  end
  
  -- ✅ 获取当前 scope 的终端
  local scope_key = get_current_scope_key()
  local terminal = get_terminal_for_scope(scope_key)
  
  if terminal and terminal:buf_valid() then
    terminal:close()
    clear_terminal_for_scope(scope_key)  -- ✅ 清理
  end
end
```

#### 2.6 修改 `M.simple_toggle()` 函数

**修改前**：
```lua
function M.simple_toggle(cmd_string, env_table, config)
  if not is_available() then
    vim.notify("Snacks.nvim terminal provider selected but Snacks.terminal not available.", vim.log.levels.ERROR)
    return
  end

  local logger = require("claudecode.logger")

  if terminal and terminal:buf_valid() and terminal:win_valid() then
    logger.debug("terminal", "Simple toggle: hiding visible terminal")
    terminal:toggle()
  elseif terminal and terminal:buf_valid() and not terminal:win_valid() then
    logger.debug("terminal", "Simple toggle: showing hidden terminal")
    terminal:toggle()
  else
    logger.debug("terminal", "Simple toggle: creating new terminal")
    M.open(cmd_string, env_table, config)
  end
end
```

**修改后**：
```lua
function M.simple_toggle(cmd_string, env_table, config)
  if not is_available() then
    vim.notify("Snacks.nvim terminal provider selected but Snacks.terminal not available.", vim.log.levels.ERROR)
    return
  end

  local logger = require("claudecode.logger")
  
  -- ✅ 获取当前 scope 的终端
  local scope_key = config.scope_key or "global"
  local terminal = get_terminal_for_scope(scope_key)

  if terminal and terminal:buf_valid() and terminal:win_valid() then
    logger.debug("terminal", "Simple toggle: hiding visible terminal (scope:", scope_key, ")")
    terminal:toggle()
  elseif terminal and terminal:buf_valid() and not terminal:win_valid() then
    logger.debug("terminal", "Simple toggle: showing hidden terminal (scope:", scope_key, ")")
    terminal:toggle()
  else
    logger.debug("terminal", "Simple toggle: creating new terminal (scope:", scope_key, ")")
    M.open(cmd_string, env_table, config)
  end
end
```

#### 2.7 修改 `M.focus_toggle()` 函数

**修改前**：
```lua
function M.focus_toggle(cmd_string, env_table, config)
  if not is_available() then
    vim.notify("Snacks.nvim terminal provider selected but Snacks.terminal not available.", vim.log.levels.ERROR)
    return
  end

  local logger = require("claudecode.logger")

  if terminal and terminal:buf_valid() and not terminal:win_valid() then
    logger.debug("terminal", "Focus toggle: showing hidden terminal")
    terminal:toggle()
  elseif terminal and terminal:buf_valid() and terminal:win_valid() then
    local claude_term_neovim_win_id = terminal.win
    local current_neovim_win_id = vim.api.nvim_get_current_win()

    if claude_term_neovim_win_id == current_neovim_win_id then
      logger.debug("terminal", "Focus toggle: hiding terminal (currently focused)")
      terminal:toggle()
    else
      logger.debug("terminal", "Focus toggle: focusing terminal")
      vim.api.nvim_set_current_win(claude_term_neovim_win_id)
      if terminal.buf and vim.api.nvim_buf_is_valid(terminal.buf) then
        if vim.api.nvim_buf_get_option(terminal.buf, "buftype") == "terminal" then
          vim.api.nvim_win_call(claude_term_neovim_win_id, function()
            vim.cmd("startinsert")
          end)
        end
      end
    end
  else
    logger.debug("terminal", "Focus toggle: creating new terminal")
    M.open(cmd_string, env_table, config)
  end
end
```

**修改后**：
```lua
function M.focus_toggle(cmd_string, env_table, config)
  if not is_available() then
    vim.notify("Snacks.nvim terminal provider selected but Snacks.terminal not available.", vim.log.levels.ERROR)
    return
  end

  local logger = require("claudecode.logger")
  
  -- ✅ 获取当前 scope 的终端
  local scope_key = config.scope_key or "global"
  local terminal = get_terminal_for_scope(scope_key)

  if terminal and terminal:buf_valid() and not terminal:win_valid() then
    logger.debug("terminal", "Focus toggle: showing hidden terminal (scope:", scope_key, ")")
    terminal:toggle()
  elseif terminal and terminal:buf_valid() and terminal:win_valid() then
    local claude_term_neovim_win_id = terminal.win
    local current_neovim_win_id = vim.api.nvim_get_current_win()

    if claude_term_neovim_win_id == current_neovim_win_id then
      logger.debug("terminal", "Focus toggle: hiding terminal (currently focused, scope:", scope_key, ")")
      terminal:toggle()
    else
      logger.debug("terminal", "Focus toggle: focusing terminal (scope:", scope_key, ")")
      vim.api.nvim_set_current_win(claude_term_neovim_win_id)
      if terminal.buf and vim.api.nvim_buf_is_valid(terminal.buf) then
        if vim.api.nvim_buf_get_option(terminal.buf, "buftype") == "terminal" then
          vim.api.nvim_win_call(claude_term_neovim_win_id, function()
            vim.cmd("startinsert")
          end)
        end
      end
    end
  else
    logger.debug("terminal", "Focus toggle: creating new terminal (scope:", scope_key, ")")
    M.open(cmd_string, env_table, config)
  end
end
```

#### 2.8 修改 `M.get_active_bufnr()` 函数

**修改前**：
```lua
function M.get_active_bufnr()
  if terminal and terminal:buf_valid() and terminal.buf then
    if vim.api.nvim_buf_is_valid(terminal.buf) then
      return terminal.buf
    end
  end
  return nil
end
```

**修改后**：
```lua
function M.get_active_bufnr()
  -- ✅ 获取当前 scope 的终端
  local scope_key = get_current_scope_key()
  local terminal = get_terminal_for_scope(scope_key)
  
  if terminal and terminal:buf_valid() and terminal.buf then
    if vim.api.nvim_buf_is_valid(terminal.buf) then
      return terminal.buf
    end
  end
  return nil
end
```

#### 2.9 添加清理函数（供 Tab 关闭时调用）

**在文件末尾 `return M` 之前添加**：

```lua
-- ✅ 新增：清理指定 scope 的终端（供 TabLeave 调用）
---@param scope_key string|number
function M._cleanup_scope(scope_key)
  local terminal = get_terminal_for_scope(scope_key)
  if terminal and terminal:buf_valid() then
    terminal:close()
  end
  clear_terminal_for_scope(scope_key)
  
  local logger = require("claudecode.logger")
  logger.debug("terminal", "Cleaned up scope:", scope_key)
end

-- ✅ 新增：清理所有 scope（供 VimLeavePre 调用）
function M._cleanup_all_scopes()
  for scope_key, terminal in pairs(terminals_by_key) do
    if terminal and terminal:buf_valid() then
      terminal:close()
    end
  end
  terminals_by_key = {}
  
  local logger = require("claudecode.logger")
  logger.debug("terminal", "Cleaned up all scopes")
end

---@type ClaudeCodeTerminalProvider
return M
```

---

### 步骤 3: 修改 `lua/claudecode/terminal/native.lua`（类似 snacks.lua）

#### 3.1 修改模块级变量

**修改前**：
```lua
local bufnr = nil
local winid = nil
local jobid = nil
local tip_shown = false
```

**修改后**：
```lua
-- ✅ 改为状态表
local terminals_by_key = {}
local tip_shown = false
```

#### 3.2 添加辅助函数（在 `config` 定义之后）

```lua
---@type ClaudeCodeTerminalConfig
local config = require("claudecode.terminal").defaults

-- ✅ 新增：按 scope key 获取终端状态
---@param scope_key string|number
---@return table|nil
local function get_terminal_for_scope(scope_key)
  return terminals_by_key[scope_key]
end

-- ✅ 新增：按 scope key 设置终端状态
---@param scope_key string|number
---@param state table Terminal state {bufnr, winid, jobid}
local function set_terminal_for_scope(scope_key, state)
  terminals_by_key[scope_key] = state
end

-- ✅ 新增：按 scope key 清理终端状态
---@param scope_key string|number
local function clear_terminal_for_scope(scope_key)
  terminals_by_key[scope_key] = nil
end

-- ✅ 新增：获取当前 scope key
---@return string|number
local function get_current_scope_key()
  local terminal_mod = require("claudecode.terminal")
  if terminal_mod.defaults and terminal_mod.defaults.session_scope == "tab" then
    return vim.api.nvim_get_current_tabpage()
  else
    return "global"
  end
end
```

#### 3.3 删除原来的 `cleanup_state()` 和 `is_valid()` 函数

**删除这两个函数**（因为现在基于 scope key）：
```lua
-- ❌ 删除
-- local function cleanup_state()
--   bufnr = nil
--   winid = nil
--   jobid = nil
-- end
-- 
-- local function is_valid()
--   ...
-- end
```

**替换为新的基于 scope 的函数**：

```lua
-- ✅ 新增：检查指定 scope 的终端是否有效
---@param scope_key string|number
---@return boolean
local function is_valid_for_scope(scope_key)
  local term_state = get_terminal_for_scope(scope_key)
  if not term_state then
    return false
  end

  -- Check if buffer is valid
  if not term_state.bufnr or not vim.api.nvim_buf_is_valid(term_state.bufnr) then
    clear_terminal_for_scope(scope_key)
    return false
  end

  -- If buffer is valid but window is invalid, try to find a window displaying this buffer
  if not term_state.winid or not vim.api.nvim_win_is_valid(term_state.winid) then
    local windows = vim.api.nvim_list_wins()
    for _, win in ipairs(windows) do
      if vim.api.nvim_win_get_buf(win) == term_state.bufnr then
        term_state.winid = win
        set_terminal_for_scope(scope_key, term_state)  -- Update state
        logger.debug("terminal", "Recovered terminal window ID for scope:", scope_key, "win:", win)
        return true
      end
    end
    -- Buffer exists but no window displays it - this is normal for hidden terminals
    return true
  end

  -- Both buffer and window are valid
  return true
end
```

#### 3.4 修改 `open_terminal()` 函数

**找到 `local function open_terminal(cmd_string, env_table, effective_config, focus)` 函数**

**在函数开头添加 scope key 处理**：

```lua
local function open_terminal(cmd_string, env_table, effective_config, focus)
  focus = utils.normalize_focus(focus)
  
  -- ✅ 获取 scope key
  local scope_key = effective_config.scope_key or "global"

  if is_valid_for_scope(scope_key) then
    -- 终端已存在，处理聚焦逻辑
    local term_state = get_terminal_for_scope(scope_key)
    if focus then
      vim.api.nvim_set_current_win(term_state.winid)
      vim.cmd("startinsert")
    end
    return true
  end

  -- 创建新终端的逻辑...
  local original_win = vim.api.nvim_get_current_win()
  local width = math.floor(vim.o.columns * effective_config.split_width_percentage)
  local full_height = vim.o.lines
  local placement_modifier

  if effective_config.split_side == "left" then
    placement_modifier = "topleft "
  else
    placement_modifier = "botright "
  end

  vim.cmd(placement_modifier .. width .. "vsplit")
  local new_winid = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_height(new_winid, full_height)

  vim.api.nvim_win_call(new_winid, function()
    vim.cmd("enew")
  end)

  local term_cmd_arg
  if cmd_string:find(" ", 1, true) then
    term_cmd_arg = vim.split(cmd_string, " ", { plain = true, trimempty = false })
  else
    term_cmd_arg = { cmd_string }
  end

  local new_jobid = vim.fn.termopen(term_cmd_arg, {
    env = env_table,
    cwd = effective_config.cwd,
    on_exit = function(job_id, _, _)
      vim.schedule(function()
        -- ✅ 只清理匹配的 scope
        local term_state_for_exit = get_terminal_for_scope(scope_key)
        if term_state_for_exit and job_id == term_state_for_exit.jobid then
          logger.debug("terminal", "Terminal process exited for scope:", scope_key)
          
          local current_winid_for_job = term_state_for_exit.winid
          local current_bufnr_for_job = term_state_for_exit.bufnr

          clear_terminal_for_scope(scope_key)

          if not effective_config.auto_close then
            return
          end

          if current_winid_for_job and vim.api.nvim_win_is_valid(current_winid_for_job) then
            if current_bufnr_for_job and vim.api.nvim_buf_is_valid(current_bufnr_for_job) then
              if vim.api.nvim_win_get_buf(current_winid_for_job) == current_bufnr_for_job then
                vim.api.nvim_win_close(current_winid_for_job, true)
              end
            else
              vim.api.nvim_win_close(current_winid_for_job, true)
            end
          end
        end
      end)
    end,
  })

  if not new_jobid or new_jobid == 0 then
    vim.notify("Failed to open native terminal.", vim.log.levels.ERROR)
    vim.api.nvim_win_close(new_winid, true)
    vim.api.nvim_set_current_win(original_win)
    return false
  end

  local new_bufnr = vim.api.nvim_get_current_buf()
  vim.bo[new_bufnr].bufhidden = "hide"

  -- ✅ 保存到对应 scope
  set_terminal_for_scope(scope_key, {
    winid = new_winid,
    bufnr = new_bufnr,
    jobid = new_jobid,
  })

  if focus then
    vim.api.nvim_set_current_win(new_winid)
    vim.cmd("startinsert")
  else
    vim.api.nvim_set_current_win(original_win)
  end

  if config.show_native_term_exit_tip and not tip_shown then
    vim.notify("Native terminal opened. Press Ctrl-\\ Ctrl-N to return to Normal mode.", vim.log.levels.INFO)
    tip_shown = true
  end
  return true
end
```

#### 3.5 修改其他函数（close_terminal, focus_terminal, is_terminal_visible, hide_terminal, show_hidden_terminal）

**所有这些函数都需要改为接受 scope_key 参数，示例**：

```lua
-- ✅ 修改后的 close_terminal
local function close_terminal(scope_key)
  if is_valid_for_scope(scope_key) then
    local term_state = get_terminal_for_scope(scope_key)
    if term_state and term_state.winid and vim.api.nvim_win_is_valid(term_state.winid) then
      vim.api.nvim_win_close(term_state.winid, true)
    end
    clear_terminal_for_scope(scope_key)
  end
end

-- ✅ 修改后的 focus_terminal
local function focus_terminal(scope_key)
  if is_valid_for_scope(scope_key) then
    local term_state = get_terminal_for_scope(scope_key)
    if term_state and term_state.winid and vim.api.nvim_win_is_valid(term_state.winid) then
      vim.api.nvim_set_current_win(term_state.winid)
      vim.cmd("startinsert")
    end
  end
end

-- ✅ 修改后的 is_terminal_visible
local function is_terminal_visible(scope_key)
  local term_state = get_terminal_for_scope(scope_key)
  if not term_state or not term_state.bufnr or not vim.api.nvim_buf_is_valid(term_state.bufnr) then
    return false
  end

  local windows = vim.api.nvim_list_wins()
  for _, win in ipairs(windows) do
    if vim.api.nvim_win_is_valid(win) and vim.api.nvim_win_get_buf(win) == term_state.bufnr then
      term_state.winid = win
      set_terminal_for_scope(scope_key, term_state)
      return true
    end
  end

  term_state.winid = nil
  set_terminal_for_scope(scope_key, term_state)
  return false
end

-- ✅ 修改后的 hide_terminal
local function hide_terminal(scope_key)
  local term_state = get_terminal_for_scope(scope_key)
  if not term_state or not term_state.winid or not vim.api.nvim_win_is_valid(term_state.winid) then
    logger.debug("terminal", "No valid terminal window to hide for scope:", scope_key)
    return
  end

  vim.api.nvim_win_close(term_state.winid, false)
  term_state.winid = nil
  set_terminal_for_scope(scope_key, term_state)
  logger.debug("terminal", "Hidden terminal for scope:", scope_key)
end

-- ✅ 修改后的 show_hidden_terminal
local function show_hidden_terminal(scope_key, effective_config, focus)
  local term_state = get_terminal_for_scope(scope_key)
  if not term_state or not term_state.bufnr or not vim.api.nvim_buf_is_valid(term_state.bufnr) then
    logger.error("terminal", "No valid hidden terminal buffer to show for scope:", scope_key)
    return false
  end

  if is_terminal_visible(scope_key) then
    logger.debug("terminal", "Terminal already visible for scope:", scope_key)
    if focus then
      focus_terminal(scope_key)
    end
    return true
  end

  local original_win = vim.api.nvim_get_current_win()
  local width = math.floor(vim.o.columns * effective_config.split_width_percentage)
  local full_height = vim.o.lines
  local placement_modifier

  if effective_config.split_side == "left" then
    placement_modifier = "topleft "
  else
    placement_modifier = "botright "
  end

  vim.cmd(placement_modifier .. width .. "vsplit")
  local new_winid = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_height(new_winid, full_height)
  vim.api.nvim_win_set_buf(new_winid, term_state.bufnr)

  term_state.winid = new_winid
  set_terminal_for_scope(scope_key, term_state)

  if focus then
    vim.api.nvim_set_current_win(new_winid)
    vim.cmd("startinsert")
  else
    vim.api.nvim_set_current_win(original_win)
  end

  logger.debug("terminal", "Showed hidden terminal for scope:", scope_key)
  return true
end
```

#### 3.6 修改公共 API 函数（M.open, M.close, M.simple_toggle, M.focus_toggle, M.get_active_bufnr）

**所有这些函数都需要获取 scope_key 并传递给内部函数**：

```lua
function M.open(cmd_string, env_table, effective_config, focus)
  focus = utils.normalize_focus(focus)
  local scope_key = effective_config.scope_key or "global"

  if is_valid_for_scope(scope_key) then
    local term_state = get_terminal_for_scope(scope_key)
    if not term_state.winid or not vim.api.nvim_win_is_valid(term_state.winid) then
      show_hidden_terminal(scope_key, effective_config, focus)
    else
      if focus then
        focus_terminal(scope_key)
      end
    end
  else
    if not open_terminal(cmd_string, env_table, effective_config, focus) then
      vim.notify("Failed to open Claude terminal using native fallback.", vim.log.levels.ERROR)
    end
  end
end

function M.close()
  local scope_key = get_current_scope_key()
  close_terminal(scope_key)
end

function M.simple_toggle(cmd_string, env_table, effective_config)
  local scope_key = effective_config.scope_key or "global"
  local has_terminal = get_terminal_for_scope(scope_key) ~= nil
  local is_visible = has_terminal and is_terminal_visible(scope_key)

  if is_visible then
    hide_terminal(scope_key)
  else
    if has_terminal then
      if show_hidden_terminal(scope_key, effective_config, true) then
        logger.debug("terminal", "Showing hidden terminal for scope:", scope_key)
      else
        logger.error("terminal", "Failed to show hidden terminal for scope:", scope_key)
      end
    else
      if not open_terminal(cmd_string, env_table, effective_config) then
        vim.notify("Failed to open Claude terminal using native fallback (simple_toggle).", vim.log.levels.ERROR)
      end
    end
  end
end

function M.focus_toggle(cmd_string, env_table, effective_config)
  local scope_key = effective_config.scope_key or "global"
  local has_terminal = get_terminal_for_scope(scope_key) ~= nil
  local is_visible = has_terminal and is_terminal_visible(scope_key)

  if not is_visible then
    if has_terminal then
      show_hidden_terminal(scope_key, effective_config, true)
    else
      open_terminal(cmd_string, env_table, effective_config, true)
    end
  else
    local term_state = get_terminal_for_scope(scope_key)
    if term_state and term_state.winid then
      local current_win = vim.api.nvim_get_current_win()
      if current_win == term_state.winid then
        hide_terminal(scope_key)
      else
        focus_terminal(scope_key)
      end
    end
  end
end

function M.get_active_bufnr()
  local scope_key = get_current_scope_key()
  if is_valid_for_scope(scope_key) then
    local term_state = get_terminal_for_scope(scope_key)
    return term_state and term_state.bufnr or nil
  end
  return nil
end
```

#### 3.7 添加清理函数

**在文件末尾添加**：

```lua
-- ✅ 新增：清理指定 scope 的终端
function M._cleanup_scope(scope_key)
  close_terminal(scope_key)
  local logger = require("claudecode.logger")
  logger.debug("terminal", "Cleaned up native terminal for scope:", scope_key)
end

-- ✅ 新增：清理所有 scope
function M._cleanup_all_scopes()
  for scope_key, _ in pairs(terminals_by_key) do
    close_terminal(scope_key)
  end
  terminals_by_key = {}
  local logger = require("claudecode.logger")
  logger.debug("terminal", "Cleaned up all native terminals")
end

---@type ClaudeCodeTerminalProvider
return M
```

---

### 步骤 4: 修改 `lua/claudecode/server/init.lua` - 添加 Session ID 支持（重要）

#### 4.1 修改 WebSocket Server 状态管理

**定位代码**：找到 `M.state` 定义（约在文件顶部）

**修改前**：
```lua
M.state = {
  running = false,
  server = nil,
  clients = {},
  -- ...
}
```

**修改后**：
```lua
M.state = {
  running = false,
  server = nil,
  clients = {},
  clients_by_session = {},  -- ✅ 新增：按 session_id 索引客户端
  -- ...
}
```

#### 4.2 修改客户端连接处理

**定位代码**：找到处理客户端消息的地方（`on_message` 回调）

**添加 session ID 提取逻辑**：

```lua
-- 在客户端连接建立后，监听首个消息来获取 session_id
local function handle_client_connection(client)
  -- 设置一个临时标记，等待客户端发送 session_id
  client._session_initialized = false
  
  client:on("message", function(message)
    -- 如果还没初始化 session，尝试从消息中提取
    if not client._session_initialized then
      local ok, decoded = pcall(vim.json.decode, message)
      if ok and decoded.type == "session_init" and decoded.session_id then
        client._session_id = decoded.session_id
        M.state.clients_by_session[decoded.session_id] = client
        client._session_initialized = true
        logger.debug("server", "Client registered with session_id:", decoded.session_id)
        return
      end
    end
    
    -- 正常的消息处理...
    -- ...原有的消息处理逻辑...
  end)
end
```

#### 4.3 添加按 Session ID 发送的函数

**在文件中添加新函数**（在 `broadcast` 函数附近）：

```lua
-- ✅ 新增：向指定 session 的客户端发送消息
---@param session_id string|number Session ID (usually tab number)
---@param message_type string Message type
---@param data table Message data
---@return boolean success
---@return string? error_msg
function M.send_to_session(session_id, message_type, data)
  if not M.state.running then
    return false, "Server is not running"
  end

  local client = M.state.clients_by_session[session_id]
  if not client then
    logger.warn("server", "No client found for session_id:", session_id)
    return false, "No client connected for this session"
  end

  local message = {
    type = message_type,
    data = data,
  }

  local success, json_str = pcall(vim.json.encode, message)
  if not success then
    logger.error("server", "Failed to encode message:", json_str)
    return false, "Failed to encode message"
  end

  local send_ok = pcall(client.send, client, json_str)
  if not send_ok then
    logger.error("server", "Failed to send message to session:", session_id)
    return false, "Failed to send message"
  end

  logger.debug("server", "Sent message to session:", session_id, "type:", message_type)
  return true
end
```

#### 4.4 清理断开连接的客户端

**修改客户端断开处理**（在 `on_close` 回调中）：

```lua
client:on("close", function()
  -- 从 clients 列表中移除
  for i, c in ipairs(M.state.clients) do
    if c == client then
      table.remove(M.state.clients, i)
      break
    end
  end
  
  -- ✅ 新增：从 session 索引中移除
  if client._session_id then
    M.state.clients_by_session[client._session_id] = nil
    logger.debug("server", "Client disconnected, session_id:", client._session_id)
  end
  
  -- ...其他清理逻辑...
end)
```

---

### 步骤 5: 修改 `lua/claudecode/terminal.lua` - 传递 Session ID 到 Claude CLI

#### 5.1 修改环境变量传递

**定位代码**：找到 `M.open()` 函数中调用 provider 的地方

**修改前**：
```lua
function M.open(opts_override)
  local config = build_config(opts_override)
  -- ...
  
  local env = get_env()
  -- ...
  
  local provider = get_provider()
  provider.open(terminal_cmd, env, config)
end
```

**修改后**：
```lua
function M.open(opts_override)
  local config = build_config(opts_override)
  -- ...
  
  local env = get_env()
  
  -- ✅ 新增：如果是 tab 模式，添加 session_id 到环境变量
  if defaults.session_scope == "tab" then
    env.CLAUDE_SESSION_ID = tostring(vim.api.nvim_get_current_tabpage())
  end
  
  local provider = get_provider()
  provider.open(terminal_cmd, env, config)
end
```

---

### 步骤 6: 修改 Claude CLI 启动脚本（可选，取决于 Claude CLI 实现）

#### 6.1 如果你使用自定义脚本启动 Claude CLI

在脚本中检查 `CLAUDE_SESSION_ID` 环境变量，并在连接 WebSocket 时发送初始化消息：

```bash
#!/bin/bash

# 获取 session ID
SESSION_ID="${CLAUDE_SESSION_ID:-global}"

# 启动 Claude CLI
claude --api-key "$ANTHROPIC_API_KEY" \
       --websocket-url "ws://localhost:8765" \
       --session-id "$SESSION_ID"
```

#### 6.2 如果 Claude CLI 不支持 session-id 参数

你需要在 Neovim 侧实现一个 wrapper，在 Claude CLI 连接后立即发送 session_init 消息：

**修改 `lua/claudecode/server/init.lua`，在服务器启动时添加客户端初始化逻辑**：

```lua
-- 在客户端连接建立后，等待一小段时间，然后注入 session_id
local function setup_client_with_session(client, session_id)
  -- 延迟 500ms，等待 Claude CLI 完全连接
  vim.defer_fn(function()
    if client._session_initialized then
      return  -- 已经初始化了
    end
    
    -- 强制设置 session_id
    client._session_id = session_id
    M.state.clients_by_session[session_id] = client
    client._session_initialized = true
    
    logger.debug("server", "Force-registered client with session_id:", session_id)
  end, 500)
end
```

**但更好的方案是：让 Claude CLI 在连接后立即发送 session_init 消息。**

#### 6.3 最简单的方案：基于连接顺序推断 Session ID

**如果无法修改 Claude CLI**，可以这样处理：

```lua
-- 在客户端连接时，根据当前活跃的 tab 推断 session_id
local function handle_client_connection(client)
  -- 获取当前 tab（假设连接来自当前 tab 的终端）
  local current_tab = vim.api.nvim_get_current_tabpage()
  local terminal_mod = require("claudecode.terminal")
  
  -- 检查当前 tab 是否有刚刚启动的终端
  local session_id
  if terminal_mod.defaults and terminal_mod.defaults.session_scope == "tab" then
    session_id = current_tab
  else
    session_id = "global"
  end
  
  client._session_id = session_id
  M.state.clients_by_session[session_id] = client
  client._session_initialized = true
  
  logger.debug("server", "Auto-registered client with session_id:", session_id)
  
  -- ...正常的消息处理...
end
```

---

### 步骤 7: 修改 `lua/claudecode/init.lua` - 使用定向发送

#### 7.1 修改 `_broadcast_at_mention()` 函数

**定位代码**：找到 `M._broadcast_at_mention(file_path, start_line, end_line)` 函数

**修改前**：
```lua
function M._broadcast_at_mention(file_path, start_line, end_line)
  if not M.state.server then
    return false, "Server not running"
  end

  local server_module = require("claudecode.server.init")
  local success = server_module.broadcast("at_mention", {
    file = file_path,
    start_line = start_line,
    end_line = end_line,
  })

  if not success then
    logger.error("broadcast", "Failed to broadcast @ mention")
    return false, "Failed to broadcast @ mention"
  end

  return true
end
```

**修改后**：
```lua
function M._broadcast_at_mention(file_path, start_line, end_line)
  if not M.state.server then
    return false, "Server not running"
  end

  local server_module = require("claudecode.server.init")
  
  -- ✅ 新增：获取当前 tab 的 session_id
  local terminal_mod = require("claudecode.terminal")
  local session_id
  if terminal_mod.defaults and terminal_mod.defaults.session_scope == "tab" then
    session_id = vim.api.nvim_get_current_tabpage()
  else
    session_id = "global"
  end
  
  -- ✅ 改用定向发送而不是 broadcast
  local success, error_msg = server_module.send_to_session(session_id, "at_mention", {
    file = file_path,
    start_line = start_line,
    end_line = end_line,
  })

  if not success then
    logger.error("broadcast", "Failed to send @ mention to session:", session_id, "error:", error_msg)
    return false, error_msg or "Failed to send @ mention"
  end

  logger.debug("broadcast", "Sent @ mention to session:", session_id, "file:", file_path)
  return true
end
```

#### 7.2 修改其他 broadcast 调用（如果有）

**搜索所有 `server_module.broadcast` 调用**，根据需要改为：
- 如果是全局操作（如 server 状态通知），继续用 `broadcast`
- 如果是针对当前 tab 的操作，改为 `send_to_session`

示例：

```lua
-- 针对当前 tab 的操作
local session_id = get_current_session_id()
server_module.send_to_session(session_id, "some_command", data)

-- 全局操作（所有 tab 都需要知道）
server_module.broadcast("server_status", { status = "running" })
```

---

## 四、测试验证方案

### 测试步骤

1. **配置启用 Tab 级 Session**

```lua
require("claudecode").setup({
  terminal = {
    session_scope = "tab",  -- ✅ 启用 tab 级隔离
    provider = "snacks",    -- 或 "native"
  },
})
```

2. **基础隔离测试**

```
1. 打开 Neovim
2. 在 Tab A 执行 :ClaudeCode
   - 应该启动一个 Claude CLI 进程
3. 新建 Tab B (:tabnew)
4. 在 Tab B 执行 :ClaudeCode
   - 应该启动另一个 Claude CLI 进程
5. 切回 Tab A，检查终端内容
   - 应该看到 Tab A 的 Claude session
6. 切到 Tab B，检查终端内容
   - 应该看到 Tab B 的 Claude session
```

3. **Send 操作隔离测试**（重要）

```
1. 在 Tab A 打开文件 foo.lua
2. 执行 :ClaudeCode 启动 Claude session
3. 执行 :ClaudeCodeSend 发送文件到 Claude
4. 检查 Tab A 的 Claude 终端
   - ✅ 应该看到 "@foo.lua" 被发送
5. 新建 Tab B (:tabnew)
6. 打开文件 bar.lua
7. 执行 :ClaudeCode 启动另一个 Claude session
8. 执行 :ClaudeCodeSend 发送 bar.lua
9. 检查 Tab B 的 Claude 终端
   - ✅ 应该看到 "@bar.lua" 被发送
10. 切回 Tab A，检查终端内容
    - ✅ Tab A 的终端应该只有 foo.lua，没有 bar.lua
11. 切到 Tab B，检查终端内容
    - ✅ Tab B 的终端应该只有 bar.lua，没有 foo.lua
```

**预期结果**：
- 每个 tab 的 Claude session 只收到自己 tab 发送的文件
- 不会出现"Tab A 发送文件，Tab B 的 Claude 也收到"的情况

**调试方法**（如果测试失败）：
```lua
-- 启用 debug 日志
require("claudecode").setup({
  log_level = "debug",
  terminal = { session_scope = "tab" },
})
```

然后检查日志：
```vim
:messages
```

关键日志应包含：
- `[server] Client registered with session_id: 1`（Tab A 连接）
- `[server] Client registered with session_id: 2`（Tab B 连接）
- `[broadcast] Sent @ mention to session: 1 file: foo.lua`（发送到 Tab A）
- `[broadcast] Sent @ mention to session: 2 file: bar.lua`（发送到 Tab B）

4. **Tab 关闭清理测试**

```
1. 在 Tab A 启动 Claude (:ClaudeCode)
2. 记录进程 PID: 在终端执行 echo $PPID
3. 关闭 Tab A (:tabclose)
4. 在系统中检查进程: ps aux | grep claude
   - 该 PID 应该已经不存在
```

5. **全局模式回归测试**

```lua
require("claudecode").setup({
  terminal = {
    session_scope = "global",  -- ✅ 使用全局模式
  },
})
```

```
1. 打开 Neovim
2. 在 Tab A 执行 :ClaudeCode
3. 新建 Tab B
4. 在 Tab B 执行 :ClaudeCode
   - 应该看到 Tab A 的 Claude 终端（共享）
5. 关闭 Tab A
   - Claude 进程应该继续运行（因为 Tab B 还在）
```

### 日志调试

**启用 debug 日志**：

```lua
require("claudecode").setup({
  log_level = "debug",  -- ✅ 启用详细日志
  terminal = {
    session_scope = "tab",
  },
})
```

**查看日志**：
```vim
:messages
```

**关键日志输出应该包含**：
- `[terminal] Simple toggle: creating new terminal (scope: 2)`
- `[terminal] Cleaned up scope: 2`
- `[init] Sending @ mention from tab: 1 file: /path/to/file.lua`

---

## 五、注意事项

### 1. 向后兼容性

- 默认 `session_scope = "global"` 保持现有行为
- 用户需要显式配置 `session_scope = "tab"` 才启用

### 2. External Provider 限制

`external` provider 由于进程在外部，无法完全控制：
- 可以支持多个 tab 启动多个外部终端
- 但无法保证 send 操作的 scope 隔离（因为所有外部终端共享同一个 WebSocket）

**建议在文档中说明**：
> `session_scope = "tab"` 主要支持 `snacks` 和 `native` provider。
> 对于 `external` provider，每个 tab 会启动独立的外部终端，
> 但 @ mention 发送可能无法完全隔离（取决于外部终端的实现）。

### 3. WebSocket 连接和消息路由

实现中使用了 **Session ID 机制**来确保消息只发送到目标 tab：

**核心设计**：
- 所有 tab 的 Claude CLI 进程连接到同一个 WebSocket server（共享端口）
- 每个连接在建立后注册自己的 `session_id`（tab 模式下是 tab number）
- Server 维护 `clients_by_session` 映射表：`session_id -> client`
- Send 操作使用 `send_to_session()` 而不是 `broadcast()`，只发送给目标 session

**Session ID 传递方式**（3 种方案，按推荐顺序）：

1. **通过环境变量**（推荐）
   - 启动 Claude CLI 时设置 `CLAUDE_SESSION_ID` 环境变量
   - Claude CLI 连接后发送 `session_init` 消息注册
   - 优点：可靠、明确
   - 缺点：需要 Claude CLI 支持

2. **基于连接顺序推断**（备选方案）
   - Server 在接受连接时，检查当前活跃的 tab
   - 自动为新连接分配对应的 session_id
   - 优点：无需修改 Claude CLI
   - 缺点：可能在多 tab 快速切换时出错

3. **通过首个消息携带**（备选方案）
   - 连接建立后，Neovim 立即通过 WebSocket 发送 session_init
   - Server 提取 session_id 并注册
   - 优点：灵活
   - 缺点：需要额外的消息交互

### 4. 性能考虑

- Tab 级隔离会为每个 tab 启动独立的 Claude CLI 进程
- 如果打开多个 tab，会有多个 Claude 进程同时运行
- 建议在文档中提醒用户注意资源占用

---

## 六、文档更新建议

### README.md 添加配置说明

```markdown
### Terminal Session Scope

By default, all tabs share the same Claude Code session. You can configure per-tab isolation:

```lua
require("claudecode").setup({
  terminal = {
    session_scope = "tab",  -- "global" (default) or "tab"
  },
})
```

**Behavior:**
- `session_scope = "global"`: All tabs share one Claude CLI process (default)
- `session_scope = "tab"`: Each tab has its own independent Claude CLI process

**Notes:**
- When using `"tab"` mode, closing a tab will automatically terminate its Claude process
- The `@` mention sending will be scoped to the current tab's session
- This feature works best with `snacks` and `native` providers
```

---

## 七、实现清单

### 必须修改的文件

- ✅ `lua/claudecode/terminal.lua`
  - 添加 `get_scope_key()` 函数
  - 修改 `build_config()` 生成并传递 `scope_key`
  - 修改 `setup()` 添加配置验证和 Tab 监听
  - 修改 `open()` 添加 `CLAUDE_SESSION_ID` 环境变量

- ✅ `lua/claudecode/terminal/snacks.lua`
  - 改 `terminal` 单例为 `terminals_by_key` 表
  - 添加 scope 辅助函数
  - 修改所有公共函数支持 scope key
  - 添加 `_cleanup_scope()` 和 `_cleanup_all_scopes()`

- ✅ `lua/claudecode/terminal/native.lua`
  - 改单例变量为 `terminals_by_key` 表
  - 添加 scope 辅助函数
  - 修改所有内部和公共函数支持 scope key
  - 添加清理函数

- ✅ `lua/claudecode/server/init.lua` **（重要）**
  - 添加 `clients_by_session` 状态表
  - 实现 `send_to_session()` 函数
  - 修改客户端连接处理，支持 session ID 注册
  - 修改客户端断开处理，清理 session 映射

- ✅ `lua/claudecode/init.lua`
  - 修改 `_broadcast_at_mention()` 改用 `send_to_session()`
  - 添加 session_id 获取逻辑
  - 添加详细的调试日志

- ✅ `lua/claudecode/types.lua`
  - 添加 `session_scope` 和 `scope_key` 类型定义

### 可选修改的文件

- ⚪ `lua/claudecode/terminal/external.lua`
  - 可以添加类似的 scope 支持，但功能有限
  - External provider 由于进程在外部，无法完全控制消息路由

### 不需要修改的文件

- ❌ `lua/claudecode/diff.lua` - Diff 功能独立
- ❌ `lua/claudecode/selection.lua` - Selection 追踪独立

---

## 八、预期效果

实现后应该达到以下效果：

1. **默认行为不变**：`session_scope = "global"` 时，所有 tab 共享一个 Claude session

2. **Tab 级隔离**：`session_scope = "tab"` 时：
   - Tab A 的 `:ClaudeCode` 启动进程 P1
   - Tab B 的 `:ClaudeCode` 启动进程 P2
   - P1 和 P2 完全独立

3. **Send 操作隔离**：
   - Tab A 的 `:ClaudeCodeSend foo.lua` 只发送到 P1
   - Tab B 的 `:ClaudeCodeSend bar.lua` 只发送到 P2

4. **自动清理**：
   - 关闭 Tab A，P1 自动终止
   - 关闭 Tab B，P2 自动终止
   - 退出 Neovim，所有进程终止

5. **可视化验证**：
   - 每个 tab 的 Claude 终端显示不同的内容
   - 切换 tab 时，看到对应 tab 的 Claude session
