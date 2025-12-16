---@brief [[
--- ClaudeIsland RPC handler for claudecode.nvim
--- Handles incoming RPC requests from ClaudeIsland via nvim --server --remote-expr
--- Enables the control plane: ClaudeIsland -> Neovim -> Claude terminal injection
---@brief ]]
---@module 'claudecode.island_rpc'

local M = {}

-- Cache for terminal provider access
local terminal_module = nil

--- File logging function
---@param level string Log level (INFO, WARNING, ERROR)
---@param trace_id string Trace ID
---@param message string Log message
local function file_log(level, trace_id, message)
  local timestamp = os.date("%Y-%m-%d %H:%M:%S")
  local log_msg = string.format("[%s] [%s] [%s] %s", level, timestamp, trace_id, message)

  -- Write to log file only - DO NOT use vim.notify to avoid polluting RPC response
  local log_path = os.getenv("HOME") .. "/.claude-island-rpc.log"
  local file = io.open(log_path, "a")
  if file then
    file:write(log_msg .. "\n")
    file:flush()
    file:close()
  end
end

---Get the terminal module lazily
---@return table|nil
local function get_terminal_module()
  if not terminal_module then
    local ok, mod = pcall(require, "claudecode.terminal")
    if ok then
      terminal_module = mod
    end
  end
  return terminal_module
end

---Get native terminal provider's job channel
---@param trace_id string Trace ID for logging
---@return number|nil jobid The terminal job channel ID
local function get_terminal_job_channel(trace_id)
  local term = get_terminal_module()

  if not term then
    return nil
  end

  local provider = term._get_provider and term._get_provider()

  if not provider then
    -- Fallback: search for the terminal buffer and get its job
    local bufnr = term.get_active_terminal_bufnr and term.get_active_terminal_bufnr()

    if bufnr and vim.api.nvim_buf_is_valid(bufnr) then
      -- Get the terminal job channel from the buffer
      local ok, channel = pcall(vim.api.nvim_buf_get_var, bufnr, "terminal_job_id")
      if ok and channel then
        return channel
      end
      -- Try alternative method
      local job_id = vim.b[bufnr].terminal_job_id
      if job_id then
        return job_id
      end
    end
  else
    -- Try to get jobid from native provider's internal state
    if provider.get_job_channel then
      local job_channel = provider.get_job_channel()
      if job_channel then
        return job_channel
      end
    end
  end

  return nil
end

---Check if terminal buffer is in terminal mode
---@param bufnr number Buffer number
---@return boolean
local function is_terminal_mode(bufnr)
  -- Check buffer options that indicate terminal mode
  local ok, term_mode = pcall(vim.api.nvim_buf_get_option, bufnr, "buftype")
  if ok and term_mode == "terminal" then
    return true
  end

  -- Check if buffer has terminal-specific variables
  local ok2, job_id = pcall(vim.api.nvim_buf_get_var, bufnr, "terminal_job_id")
  if ok2 and job_id then
    return true
  end

  return false
end

---Inject text into the Claude terminal
---@param text string The text to inject
---@param append_enter boolean Whether to append newline
---@param trace_id string Trace ID for logging
---@param bufnr number|nil Buffer number (optional, for optimization)
---@return boolean success
---@return number|nil injected_bytes
---@return string|nil error
local function inject_to_terminal(text, append_enter, trace_id, bufnr)
  -- Get job channel - either from parameter or from terminal module
  local job_channel = nil
  if bufnr then
    -- Try to get job channel from buffer variable directly (faster)
    local ok, channel = pcall(vim.api.nvim_buf_get_var, bufnr, "terminal_job_id")
    if ok and channel then
      job_channel = channel
    end
  end

  -- Fallback to full search if not found
  if not job_channel then
    job_channel = get_terminal_job_channel(trace_id)
  end

  if not job_channel then
    return false, nil, "NO_CLAUDE_TERMINAL"
  end

  -- Send text to terminal (without \n for Claude Code)
  local send_text = text

  -- CRITICAL: Ensure we are in the terminal window before sending
  local saved_win = vim.api.nvim_get_current_win()
  local term = get_terminal_module()
  if term then
    if not bufnr then
      bufnr = term.get_active_terminal_bufnr and term.get_active_terminal_bufnr()
    end
    if bufnr then
      local wins = vim.fn.win_findbuf(bufnr)
      if wins and #wins > 0 then
        vim.api.nvim_set_current_win(wins[1])
        vim.cmd("startinsert")
        vim.cmd("sleep 10m")
      end
    end
  end

  -- Send the text to the terminal job
  local ok, result = pcall(vim.fn.chansend, job_channel, send_text)
  if not ok then
    return false, nil, "INJECT_FAILED: " .. tostring(result)
  end

  local bytes_sent = #send_text

  -- If append_enter, send Enter key via feedkeys in terminal mode
  -- Claude Code requires Enter to be sent via feedkeys, not \n in chansend
  if append_enter then
    local term = get_terminal_module()
    if term then
      if not bufnr then
        bufnr = term.get_active_terminal_bufnr and term.get_active_terminal_bufnr()
      end
      if bufnr and vim.api.nvim_buf_is_valid(bufnr) then
        local wins = vim.fn.win_findbuf(bufnr)
        if wins and #wins > 0 then
          local saved_win = vim.api.nvim_get_current_win()
          vim.api.nvim_set_current_win(wins[1])
          vim.cmd("startinsert")
          vim.cmd("sleep 20m")

          -- Wait for text to be processed
          vim.cmd("sleep 100m")

          -- Send Enter via feedkeys in terminal mode
          pcall(vim.api.nvim_feedkeys, "\r", "t", false)

          -- Wait for Enter to be processed
          vim.cmd("sleep 50m")

          vim.api.nvim_set_current_win(saved_win)
        end
      end
    end
  end

  return true, bytes_sent, nil
end

---Get the status of the Claude terminal
---@param trace_id string Trace ID for logging
---@return table status
local function get_terminal_status(trace_id)
  local term = get_terminal_module()
  if not term then
    return {
      terminal_ready = false,
      bufnr = nil,
      job_channel = nil,
      error = "TERMINAL_MODULE_NOT_LOADED"
    }
  end

  local bufnr = term.get_active_terminal_bufnr and term.get_active_terminal_bufnr()
  local job_channel = get_terminal_job_channel(trace_id)

  return {
    terminal_ready = (bufnr ~= nil and job_channel ~= nil),
    bufnr = bufnr,
    job_channel = job_channel,
    nvim_pid = vim.fn.getpid(),
    nvim_listen_address = vim.v.servername or os.getenv("NVIM_LISTEN_ADDRESS"),
  }
end

---Handle RPC request from ClaudeIsland
---@param payload_json string JSON payload from ClaudeIsland
---@return string response_json JSON response
function M.handle_rpc(payload)
  local trace_id = "unknown"
  local action = "unknown"

  -- Parse the payload (now received as table via msgpack-rpc)
  if type(payload) ~= "table" then
    return {
      trace_id = trace_id,
      ok = false,
      error = "INVALID_PAYLOAD_TYPE",
      data = nil
    }
  end

  trace_id = payload.trace_id or "no_trace"
  action = payload.action or "unknown"

  -- Dispatch based on action
  if action == "ping" then
    return {
      trace_id = trace_id,
      ok = true,
      error = nil,
      data = {
        nvim_pid = vim.fn.getpid(),
        pong = true,
      }
    }

  elseif action == "status" then
    local status = get_terminal_status(trace_id)
    return {
      trace_id = trace_id,
      ok = true,
      error = nil,
      data = status
    }

  elseif action == "send_text" then
    local text_payload = payload.payload or {}
    local text = text_payload.text or ""
    local mode = text_payload.mode or "append_and_enter"
    local ensure_terminal = text_payload.ensure_terminal or false

    if text == "" then
      return {
        trace_id = trace_id,
        ok = false,
        error = "EMPTY_TEXT",
        data = nil
      }
    end

    -- Ensure terminal is visible if requested
    if ensure_terminal then
      local term = get_terminal_module()
      if term and term.ensure_visible then
        term.ensure_visible()
        vim.cmd("sleep 50m")
      end
    end

    -- Get terminal info
    local term = get_terminal_module()
    if not term then
      return {
        trace_id = trace_id,
        ok = false,
        error = "Terminal module not found",
        data = nil
      }
    end

    local bufnr = term.get_active_terminal_bufnr and term.get_active_terminal_bufnr()
    if not bufnr then
      return {
        trace_id = trace_id,
        ok = false,
        error = "No active terminal buffer",
        data = nil
      }
    end

    if not vim.api.nvim_buf_is_valid(bufnr) then
      return {
        trace_id = trace_id,
        ok = false,
        error = "Invalid terminal buffer",
        data = nil
      }
    end

    -- Verify terminal mode
    local is_term = is_terminal_mode(bufnr)

    local append_enter = (mode == "append_and_enter")

    -- Inject text - pass bufnr to avoid duplicate get_terminal_job_channel calls
    local success, injected_bytes, error_msg = inject_to_terminal(text, append_enter, trace_id, bufnr)

    return {
      trace_id = trace_id,
      ok = success,
      error = error_msg,
      data = {
        nvim_pid = vim.fn.getpid(),
        terminal_ready = success,
        injected_bytes = injected_bytes,
      }
    }

  elseif action == "focus_terminal" then
    local term = get_terminal_module()
    if term and term.open then
      term.open()
      return {
        trace_id = trace_id,
        ok = true,
        error = nil,
        data = {
          nvim_pid = vim.fn.getpid(),
          focused = true,
        }
      }
    else
      return {
        trace_id = trace_id,
        ok = false,
        error = "TERMINAL_MODULE_NOT_AVAILABLE",
        data = nil
      }
    end

  else
    return {
      trace_id = trace_id,
      ok = false,
      error = "UNKNOWN_ACTION",
      data = nil
    }
  end
end

---Get the registry file path
---@return string
local function get_registry_path()
  local xdg_runtime = os.getenv("XDG_RUNTIME_DIR") or "/tmp"
  return xdg_runtime .. "/claude-island-nvim-registry.json"
end

---Write this Neovim instance to the registry
local function write_to_registry()
  local listen_addr = vim.v.servername
  if not listen_addr or listen_addr == "" then
    listen_addr = os.getenv("NVIM_LISTEN_ADDRESS")
  end

  if not listen_addr or listen_addr == "" then
    return
  end

  local registry_path = get_registry_path()
  local nvim_pid = vim.fn.getpid()
  local cwd = vim.fn.getcwd()

  -- Read existing registry
  local registry = { instances = {} }
  local file = io.open(registry_path, "r")
  if file then
    local content = file:read("*all")
    file:close()
    if content and content ~= "" then
      local ok, decoded = pcall(vim.json.decode, content)
      if ok and type(decoded) == "table" then
        registry = decoded
      end
    end
  end

  -- Remove stale entries for this PID (in case of restart)
  local new_instances = {}
  for _, inst in ipairs(registry.instances or {}) do
    if inst.pid ~= nvim_pid then
      table.insert(new_instances, inst)
    end
  end

  -- Add this instance
  table.insert(new_instances, {
    pid = nvim_pid,
    listenAddress = listen_addr,
    cwd = cwd,
    registeredAt = os.date("!%Y-%m-%dT%H:%M:%SZ"),
  })

  registry.instances = new_instances

  -- Write back
  local ok, json = pcall(vim.json.encode, registry)
  if ok then
    file = io.open(registry_path, "w")
    if file then
      file:write(json)
      file:close()
    end
  end
end

---Remove this Neovim instance from the registry
local function remove_from_registry()
  local registry_path = get_registry_path()
  local nvim_pid = vim.fn.getpid()

  local file = io.open(registry_path, "r")
  if not file then
    return
  end

  local content = file:read("*all")
  file:close()

  if not content or content == "" then
    return
  end

  local ok, registry = pcall(vim.json.decode, content)
  if not ok or type(registry) ~= "table" then
    return
  end

  -- Remove this instance
  local new_instances = {}
  for _, inst in ipairs(registry.instances or {}) do
    if inst.pid ~= nvim_pid then
      table.insert(new_instances, inst)
    end
  end

  registry.instances = new_instances

  -- Write back
  local encode_ok, json = pcall(vim.json.encode, registry)
  if encode_ok then
    file = io.open(registry_path, "w")
    if file then
      file:write(json)
      file:close()
    end
  end
end

---Setup the global RPC entry function
function M.setup()
  -- Register the global function for nvim --remote-expr access
  _G.claudecode_island_rpc = function(payload_json)
    return M.handle_rpc(payload_json)
  end

  -- Write to registry on startup
  write_to_registry()

  -- Setup autocmd to remove from registry on exit
  vim.api.nvim_create_autocmd("VimLeavePre", {
    group = vim.api.nvim_create_augroup("ClaudeIslandRPCCleanup", { clear = true }),
    callback = function()
      remove_from_registry()
    end,
    desc = "Remove from ClaudeIsland nvim registry on exit",
  })
end

-- 自动初始化：即使claudecode.setup()没有被调用，也要确保RPC功能可用
vim.defer_fn(function()
  -- 检查全局函数是否已定义
  if type(_G.claudecode_island_rpc) ~= "function" then
    M.setup()
  end
end, 100)

return M
