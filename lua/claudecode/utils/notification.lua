--- 系统通知工具模块
--- 用于发送 macOS 系统通知，提醒用户任务完成
--- @module claudecode.utils.notification

local logger = require("claudecode.logger")

local M = {}

--- 默认配置
local default_config = {
  enabled = true,
  sound = "Glass",
  include_project_path = true,
  title_prefix = "Claude Code",
}

--- 当前配置
local config = vim.deepcopy(default_config)

--- 设置通知配置
--- @param user_config table 用户配置
function M.setup(user_config)
  config = vim.tbl_deep_extend("force", default_config, user_config or {})
  local inspect_func = vim.inspect or tostring
  logger.debug("notification", string.format("Notification configured: %s", inspect_func(config)))
end

--- 获取当前项目信息
--- @return string project_name 项目名称
--- @return string project_path 项目路径
local function get_project_info()
  local cwd = vim.fn.getcwd()
  local project_name = vim.fn.fnamemodify(cwd, ":t")
  return project_name, cwd
end

--- 转义 AppleScript 字符串中的特殊字符
--- @param str string 需要转义的字符串
--- @return string 转义后的字符串
local function escape_applescript_string(str)
  if not str then return "" end
  -- 转义双引号和反斜杠
  return str:gsub('\\', '\\\\'):gsub('"', '\\"')
end

--- 发送 macOS 系统通知
--- @param title string 通知标题
--- @param message string 通知内容
--- @param sound string|nil 通知声音，默认使用配置中的声音
--- @return boolean success 是否发送成功
local function send_macos_notification(title, message, sound)
  if not config.enabled then
    logger.debug("notification", "Notification disabled, skipping")
    return false
  end

  -- 使用配置中的声音或默认声音
  sound = sound or config.sound or "Glass"
  
  -- 转义字符串
  local escaped_title = escape_applescript_string(title)
  local escaped_message = escape_applescript_string(message)
  local escaped_sound = escape_applescript_string(sound)
  
  -- 构建 AppleScript 命令
  local cmd = string.format(
    'osascript -e \'display notification "%s" with title "%s" sound name "%s"\'',
    escaped_message,
    escaped_title,
    escaped_sound
  )
  
  logger.debug("notification", string.format("Sending notification command: %s", cmd))
  
  -- 异步执行通知命令
  vim.fn.jobstart(cmd, {
    on_exit = function(_, exit_code)
      if exit_code == 0 then
        logger.debug("notification", "Notification sent successfully")
      else
        logger.warn("notification", string.format("Failed to send notification, exit code: %d", exit_code))
      end
    end,
    stdout_buffered = true,
    stderr_buffered = true,
  })
  
  return true
end

--- 发送任务完成通知
--- @param options table|nil 通知选项
---   - message: string 自定义消息内容
---   - sound: string 自定义声音
---   - include_project: boolean 是否包含项目信息
function M.send_task_completion_notification(options)
  options = options or {}
  
  -- 获取项目信息
  local project_name, project_path = get_project_info()
  
  -- 构建通知标题
  local title = config.title_prefix
  if config.include_project_path and options.include_project ~= false then
    title = project_name
  end
  
  -- 构建通知消息
  local message = options.message or "任务已完成"
  if config.include_project_path and options.include_project ~= false then
    message = string.format("%s\n路径: %s", message, project_path)
  end
  
  logger.info("notification", string.format(
    "Sending task completion notification for project: %s", project_name
  ))
  
  return send_macos_notification(title, message, options.sound)
end

--- 发送自定义通知
--- @param title string 通知标题
--- @param message string 通知内容
--- @param sound string|nil 通知声音
--- @return boolean success 是否发送成功
function M.send_notification(title, message, sound)
  return send_macos_notification(title, message, sound)
end

--- 检查是否支持通知功能
--- @return boolean 是否支持
function M.is_supported()
  -- 检查是否为 macOS 系统
  if vim.fn.has("mac") == 0 then
    return false
  end
  
  -- 检查 osascript 命令是否可用
  return vim.fn.executable("osascript") == 1
end

--- 获取当前配置
--- @return table 当前配置
function M.get_config()
  return vim.deepcopy(config)
end

return M