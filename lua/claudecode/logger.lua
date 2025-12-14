---@brief Centralized logger for Claude Code Neovim integration.
-- Provides level-based logging.
---@module 'claudecode.logger'
local M = {}

M.levels = {
  ERROR = 1,
  WARN = 2,
  INFO = 3,
  DEBUG = 4,
  TRACE = 5,
}

local level_values = {
  error = M.levels.ERROR,
  warn = M.levels.WARN,
  info = M.levels.INFO,
  debug = M.levels.DEBUG,
  trace = M.levels.TRACE,
}

local current_log_level_value = M.levels.INFO

---Setup the logger module
---@param plugin_config ClaudeCodeConfig The configuration table (e.g., from claudecode.init.state.config).
function M.setup(plugin_config)
  local conf = plugin_config

  if conf and conf.log_level and level_values[conf.log_level] then
    current_log_level_value = level_values[conf.log_level]
  else
    vim.notify(
      "ClaudeCode Logger: Invalid or missing log_level in configuration (received: "
        .. tostring(conf and conf.log_level)
        .. "). Defaulting to INFO.",
      vim.log.levels.WARN
    )
    current_log_level_value = M.levels.INFO
  end
end

local function log(level, component, message_parts)
  if level > current_log_level_value then
    return
  end

  local prefix = "[ClaudeCode]"
  if component then
    prefix = prefix .. " [" .. component .. "]"
  end

  local level_name = "UNKNOWN"
  for name, val in pairs(M.levels) do
    if val == level then
      level_name = name
      break
    end
  end
  prefix = prefix .. " [" .. level_name .. "]"

  local message = ""
  for i, part in ipairs(message_parts) do
    if i > 1 then
      message = message .. " "
    end
    if type(part) == "table" or type(part) == "boolean" then
      message = message .. vim.inspect(part)
    else
      message = message .. tostring(part)
    end
  end

  -- Wrap all vim.notify and nvim_echo calls in vim.schedule to avoid
  -- "nvim_echo must not be called in a fast event context" errors
  vim.schedule(function()
    if level == M.levels.ERROR then
      vim.notify(prefix .. " " .. message, vim.log.levels.ERROR, { title = "ClaudeCode Error" })
    elseif level == M.levels.WARN then
      vim.notify(prefix .. " " .. message, vim.log.levels.WARN, { title = "ClaudeCode Warning" })
    else
      -- For INFO, DEBUG, TRACE, use nvim_echo to avoid flooding notifications,
      -- to make them appear in :messages
      vim.api.nvim_echo({ { prefix .. " " .. message, "Normal" } }, true, {})
    end
  end)
end

---Error level logging
---@param component string|nil Optional component/module name.
---@param ... any Varargs representing parts of the message.
function M.error(component, ...)
  if type(component) ~= "string" then
    log(M.levels.ERROR, nil, { component, ... })
  else
    log(M.levels.ERROR, component, { ... })
  end
end

---Warn level logging
---@param component string|nil Optional component/module name.
---@param ... any Varargs representing parts of the message.
function M.warn(component, ...)
  if type(component) ~= "string" then
    log(M.levels.WARN, nil, { component, ... })
  else
    log(M.levels.WARN, component, { ... })
  end
end

---Info level logging
---@param component string|nil Optional component/module name.
---@param ... any Varargs representing parts of the message.
function M.info(component, ...)
  if type(component) ~= "string" then
    log(M.levels.INFO, nil, { component, ... })
  else
    log(M.levels.INFO, component, { ... })
  end
end

---Check if a specific log level is enabled
---@param level_name ClaudeCodeLogLevel The level name ("error", "warn", "info", "debug", "trace")
---@return boolean enabled Whether the level is enabled
function M.is_level_enabled(level_name)
  local level_value = level_values[level_name]
  if not level_value then
    return false
  end
  return level_value <= current_log_level_value
end

---Debug level logging
---@param component string|nil Optional component/module name.
---@param ... any Varargs representing parts of the message.
function M.debug(component, ...)
  if type(component) ~= "string" then
    log(M.levels.DEBUG, nil, { component, ... })
  else
    log(M.levels.DEBUG, component, { ... })
  end
end

---Trace level logging
---@param component string|nil Optional component/module name.
---@param ... any Varargs representing parts of the message.
function M.trace(component, ...)
  if type(component) ~= "string" then
    log(M.levels.TRACE, nil, { component, ... })
  else
    log(M.levels.TRACE, component, { ... })
  end
end

---Notify with optional on_open callback for interactive notifications
---@param message string The notification message
---@param level number|nil The log level (vim.log.levels.INFO, etc.), defaults to INFO
---@param opts table|nil Optional notification options (title, on_open, etc.)
function M.notify(message, level, opts)
  level = level or vim.log.levels.INFO
  opts = opts or {}

  vim.schedule(function()
    vim.notify(message, level, opts)
  end)
end

---Notify with tmux jump action
---Creates a notification with a callback to jump to the current tmux session/window
---@param message string The notification message
---@param level number|nil The log level (vim.log.levels.INFO, etc.), defaults to INFO
---@param opts table|nil Optional notification options
function M.notify_with_tmux_link(message, level, opts)
  opts = opts or {}
  level = level or vim.log.levels.INFO

  -- Check if tmux notifications are enabled in config
  local config_ok, config_module = pcall(require, "claudecode.config")
  local main_ok, main_module = pcall(require, "claudecode")
  local config = (main_ok and main_module.state and main_module.state.config)
    or (config_ok and config_module.defaults)
    or {}

  if config.enable_tmux_notifications == false then
    -- Tmux notifications disabled, use regular notification
    M.notify(message, level, opts)
    return
  end

  -- Try to load tmux module
  local ok, tmux = pcall(require, "claudecode.tmux")
  if not ok or not tmux.is_inside_tmux() then
    -- Fallback to regular notification if not in tmux or tmux module not available
    M.notify(message, level, opts)
    return
  end

  -- Get tmux location info
  local session = tmux.get_session_name()
  local window = tmux.get_window_info()

  if not session then
    -- No tmux info available, use regular notification
    M.notify(message, level, opts)
    return
  end

  -- Build location string for notification
  local location_parts = { session }
  if window and window.name then
    table.insert(location_parts, window.name)
  end
  local location_str = table.concat(location_parts, ":")

  -- Append tmux location to message
  local full_message = message .. " [tmux: " .. location_str .. "]"

  -- Add on_open callback to jump to tmux session/window
  opts.on_open = function()
    tmux.switch_to_session(session)
    if window and window.index then
      tmux.switch_to_window(window.index)
    end
  end

  vim.schedule(function()
    vim.notify(full_message, level, opts)
  end)
end

return M
