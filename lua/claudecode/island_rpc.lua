---@brief [[
--- ClaudeIsland RPC handler for claudecode.nvim
--- Handles incoming RPC requests from ClaudeIsland via nvim --server --remote-expr
--- Enables the control plane: ClaudeIsland -> Neovim -> Claude terminal injection
---@brief ]]
---@module 'claudecode.island_rpc'

local M = {}

local logger = require("claudecode.logger")

-- Cache for terminal provider access
local terminal_module = nil

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
---@return number|nil jobid The terminal job channel ID
local function get_terminal_job_channel()
  local term = get_terminal_module()
  if not term then
    return nil
  end

  local provider = term._get_provider and term._get_provider()
  if not provider then
    return nil
  end

  -- Try to get jobid from native provider's internal state
  if provider.get_job_channel then
    local job_channel = provider.get_job_channel()
    if job_channel then
      return job_channel
    end
  end

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

  return nil
end

---Inject text into the Claude terminal
---@param text string The text to inject
---@param append_enter boolean Whether to append newline
---@return boolean success
---@return number|nil injected_bytes
---@return string|nil error
local function inject_to_terminal(text, append_enter)
  local job_channel = get_terminal_job_channel()
  if not job_channel then
    return false, nil, "NO_CLAUDE_TERMINAL"
  end

  -- Prepare the text to send
  local send_text = text
  if append_enter then
    send_text = text .. "\n"
  end

  -- Send the text to the terminal job
  local ok, result = pcall(vim.fn.chansend, job_channel, send_text)
  if not ok then
    return false, nil, "INJECT_FAILED: " .. tostring(result)
  end

  local bytes_sent = #send_text
  return true, bytes_sent, nil
end

---Get the status of the Claude terminal
---@return table status
local function get_terminal_status()
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
  local job_channel = get_terminal_job_channel()

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
function M.handle_rpc(payload_json)
  local trace_id = "unknown"
  local action = "unknown"

  -- Parse the JSON payload
  local ok, payload = pcall(vim.json.decode, payload_json)
  if not ok or type(payload) ~= "table" then
    return vim.json.encode({
      trace_id = trace_id,
      ok = false,
      error = "INVALID_JSON",
      data = nil
    })
  end

  trace_id = payload.trace_id or "no_trace"
  action = payload.action or "unknown"

  -- Dispatch based on action
  if action == "ping" then
    return vim.json.encode({
      trace_id = trace_id,
      ok = true,
      error = nil,
      data = {
        nvim_pid = vim.fn.getpid(),
        pong = true,
      }
    })

  elseif action == "status" then
    local status = get_terminal_status()
    return vim.json.encode({
      trace_id = trace_id,
      ok = true,
      error = nil,
      data = status
    })

  elseif action == "send_text" then
    local text_payload = payload.payload or {}
    local text = text_payload.text or ""
    local mode = text_payload.mode or "append_and_enter"
    local ensure_terminal = text_payload.ensure_terminal or false

    if text == "" then
      return vim.json.encode({
        trace_id = trace_id,
        ok = false,
        error = "EMPTY_TEXT",
        data = nil
      })
    end

    -- Ensure terminal is visible if requested
    if ensure_terminal then
      local term = get_terminal_module()
      if term and term.ensure_visible then
        term.ensure_visible()
        -- Give a small delay for terminal to become ready
        vim.cmd("sleep 50m")
      end
    end

    local append_enter = (mode == "append_and_enter")
    local success, injected_bytes, error_msg = inject_to_terminal(text, append_enter)

    return vim.json.encode({
      trace_id = trace_id,
      ok = success,
      error = error_msg,
      data = {
        nvim_pid = vim.fn.getpid(),
        terminal_ready = success,
        injected_bytes = injected_bytes,
      }
    })

  elseif action == "focus_terminal" then
    local term = get_terminal_module()
    if term and term.open then
      term.open()
      return vim.json.encode({
        trace_id = trace_id,
        ok = true,
        error = nil,
        data = {
          nvim_pid = vim.fn.getpid(),
          focused = true,
        }
      })
    else
      return vim.json.encode({
        trace_id = trace_id,
        ok = false,
        error = "TERMINAL_MODULE_NOT_AVAILABLE",
        data = nil
      })
    end

  else
    logger.warn("island_rpc", string.format("[%s] Unknown action: %s", trace_id, action))
    return vim.json.encode({
      trace_id = trace_id,
      ok = false,
      error = "UNKNOWN_ACTION",
      data = nil
    })
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
    logger.warn("island_rpc", "No listen address available, skipping registry write")
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
    else
      logger.error("island_rpc", "Failed to open registry file for writing: " .. registry_path)
    end
  else
    logger.error("island_rpc", "Failed to encode registry JSON")
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

return M
