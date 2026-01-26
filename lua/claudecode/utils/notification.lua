--- System notification utility module
--- Used to send macOS system notifications to alert users when tasks are complete
--- @module claudecode.utils.notification

local logger = require("claudecode.logger")

local M = {}

--- 默认配置
local default_config = {
  enabled = true,
  sound = "Glass",
  include_project_path = true,
  title_prefix = "Claude Code",
  mode = "system", -- 通知模式: "system" (macOS系统通知), "vim" (vim.notify), "both" (两者都)
  backend = "terminal-notifier", -- 目前支持 terminal-notifier
  terminal_notifier = {
    ignore_dnd = true, -- 是否忽略勿扰模式，对应 -ignoreDnD
    sender = "com.apple.Terminal",
    group = "claudecode",
    activate = "com.apple.Terminal",
  },
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

-- AppleScript 转义函数已移除（不再使用 osascript）

--- 发送 Neovim 内置通知
--- @param title string 通知标题
--- @param message string 通知内容
local function send_vim_notification(title, message)
  vim.notify(message, vim.log.levels.INFO, {
    title = title,
    timeout = 3000,
  })
end

--- 发送 macOS 系统通知（使用 terminal-notifier）
--- @param title string 通知标题
--- @param message string 通知内容
--- @param sound string|nil 通知声音，默认使用配置中的声音
--- @return boolean success 是否发送成功
local function send_macos_notification(title, message, sound)
  if not config.enabled then
    logger.debug("notification", "Notification disabled, skipping")
    return false
  end

  -- 获取通知模式
  local mode = config.mode or "system"

  -- 根据模式发送通知
  if mode == "vim" or mode == "both" then
    send_vim_notification(title, message)
  end

  -- 如果是 vim only 模式，不需要发送系统通知
  if mode == "vim" then
    return true
  end

  -- 使用配置中的声音或默认声音
  sound = sound or config.sound or "Glass"

  -- subtitle：若标题已是项目名，则不重复项目名
  local project_name = select(1, get_project_info())
  local subtitle
  if not title or title ~= project_name then
    subtitle = string.format("Project：%s", project_name)
  end

  -- 构建 terminal-notifier 参数列表
  local tn = config.terminal_notifier or {}
  local args = {
    "terminal-notifier",
    "-message",
    message or "",
    "-title",
    title or (config.title_prefix or "Claude Code"),
    -- subtitle 需要后续按条件插入
    "-sound",
    sound,
    "-sender",
    tn.sender or "com.apple.Terminal",
    "-group",
    tn.group or "claudecode",
    "-activate",
    tn.activate or "com.apple.Terminal",
  }

  if subtitle and subtitle ~= "" then
    table.insert(args, 6, "-subtitle")
    table.insert(args, 7, subtitle)
  end

  -- 是否忽略勿扰模式
  if tn.ignore_dnd ~= false then
    table.insert(args, "-ignoreDnD")
  end

  logger.debug("notification", "Sending notification via terminal-notifier")

  -- 异步执行通知命令（列表避免转义问题）
  vim.fn.jobstart(args, {
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

--- Send task completion notification
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

  -- Build notification message
  local message = options.message or "Task completed"
  if config.include_project_path and options.include_project ~= false then
    message = string.format("%s\nPath: %s", message, project_path)
  end

  logger.info("notification", string.format("Sending task completion notification for project: %s", project_name))

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

  local backend = (config.backend or "terminal-notifier")
  if backend == "terminal-notifier" then
    return vim.fn.executable("terminal-notifier") == 1
  end
  return false
end

--- 获取当前配置
--- @return table 当前配置
function M.get_config()
  return vim.deepcopy(config)
end

return M
