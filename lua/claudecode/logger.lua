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

local current_log_level_value = M.levels.WARN  -- 默认使用WARN级别，直到用户配置

-- 指定一个明确的日志文件路径
local log_file_path = "/tmp/claudecode_debug.log"
local log_file_handle = nil

-- 初始化日志文件
local function init_log_file()
  if not log_file_handle then
    log_file_handle = io.open(log_file_path, "a")
    if log_file_handle then
      log_file_handle:write("\n=== ClaudeCode Debug Session Started at " .. os.date("%Y-%m-%d %H:%M:%S") .. " ===\n")
      log_file_handle:flush()
    end
  end
end

-- 写入文件日志
local function write_to_file(level_name, component, message)
  if not log_file_handle then
    init_log_file()
  end

  if log_file_handle then
    local timestamp = os.date("%H:%M:%S.000")
    local prefix = "[" .. timestamp .. "] [ClaudeCode]"
    if component then
      prefix = prefix .. " [" .. component .. "]"
    end
    prefix = prefix .. " [" .. level_name .. "]"

    log_file_handle:write(prefix .. " " .. message .. "\n")
    log_file_handle:flush()
  end
end

---Setup the logger module
---@param plugin_config ClaudeCodeConfig The configuration table (e.g., from claudecode.init.state.config).
function M.setup(plugin_config)
  local conf = plugin_config

  if conf and conf.log_level and level_values[conf.log_level] then
    current_log_level_value = level_values[conf.log_level]
    -- 日志级别已配置
  else
    vim.notify(
      "ClaudeCode Logger: Invalid or missing log_level in configuration (received: "
        .. tostring(conf and conf.log_level)
        .. "). Defaulting to INFO.",
      vim.log.levels.WARN
    )
    current_log_level_value = M.levels.INFO
    -- 使用默认日志级别
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

  -- 只有满足日志级别要求的才写入文件
  write_to_file(level_name, component, message)

  -- Wrap all vim.notify and nvim_echo calls in vim.schedule to avoid
  -- "nvim_echo must not be called in a fast event context" errors
  vim.schedule(function()
    if level == M.levels.ERROR then
      vim.notify(prefix .. " " .. message, vim.log.levels.ERROR, { title = "ClaudeCode Error" })
    elseif level == M.levels.WARN then
      vim.notify(prefix .. " " .. message, vim.log.levels.WARN, { title = "ClaudeCode Warning" })
    elseif level == M.levels.INFO then
      -- INFO 级别也显示在控制台
      vim.api.nvim_echo({ { prefix .. " " .. message, "Normal" } }, true, {})
    end
    -- DEBUG 和 TRACE 只写入文件，不显示在控制台以避免干扰
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

--- Get the current log file path
-- @return string The absolute path to the log file
function M.get_log_file_path()
  return log_file_path
end

--- Clear the log file
function M.clear_log_file()
  local file = io.open(log_file_path, "w")
  if file then
    file:write("=== ClaudeCode Debug Log Cleared at " .. os.date("%Y-%m-%d %H:%M:%S") .. " ===\n")
    file:close()
  end
  -- 重新初始化文件句柄
  if log_file_handle then
    log_file_handle:close()
    log_file_handle = nil
  end
  init_log_file()
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

return M
