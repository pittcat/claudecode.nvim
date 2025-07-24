--- Claude Code 监控系统入口模块
-- 统一管理监控系统的初始化、配置和API接口
-- @module claudecode.monitoring.init

local logger = require("claudecode.logger")

local M = {}

--- 监控系统状态
local monitoring_state = {
  initialized = false,
  modules = {},
  config = {},
  start_time = 0
}

--- 默认配置
local default_config = {
  -- 状态管理器配置
  state_manager = {
    history_limit = 100,
    completion_timeout = 2000,
    enable_metrics = true
  },
  
  -- 事件监听器配置
  event_listener = {
    max_history = 200,
    enable_history = true,
    debug_events = false
  },
  
  -- 监控适配器配置
  monitors = {
    websocket = true,
    tool_call = true,
    terminal = true,
    intelligent_analyzer = true
  },
  
  -- 智能状态分析器配置
  intelligent_analyzer = {
    -- 基本检查参数
    check_interval = 4000,                -- 检查间隔时间（毫秒）
    executing_timeout = 10000,            -- 执行状态超时时间（毫秒）
    lines_to_check = 30,                  -- 检查末尾行数
    
    -- 状态确认阈值配置
    idle_confirmation_threshold = 3,      -- idle状态确认次数（连续无变化N次确认为idle）
    executing_confirmation_threshold = 1, -- executing状态确认次数（检测到N次确认为executing）
    disconnected_confirmation_threshold = 2, -- disconnected状态确认次数
    waiting_confirmation_threshold = 1,   -- waiting状态确认次数
    
    enabled = true
  },
  
  -- 性能配置
  performance = {
    health_check_interval = 30000, -- 30秒
    cleanup_interval = 300000,     -- 5分钟
    max_memory_usage = 50 * 1024 * 1024 -- 50MB
  },
  
  -- 用户界面配置
  ui = {
    enable_status_line = false,
    enable_floating_window = false,
    auto_refresh_interval = 1000 -- 1秒
  }
}

--- 延迟加载的模块引用
local lazy_modules = {}

--- 获取模块（延迟加载）
--- @param module_name string 模块名称
--- @return table|nil module 模块引用
local function get_module(module_name)
  if not lazy_modules[module_name] then
    local success, module = pcall(require, "claudecode.monitoring." .. module_name)
    if success then
      lazy_modules[module_name] = module
    else
      logger.error("monitoring", "Failed to load module: " .. module_name .. " - " .. tostring(module))
      return nil
    end
  end
  return lazy_modules[module_name]
end

--- 初始化监控系统
--- @param user_config table|nil 用户配置
--- @return boolean success 是否初始化成功
function M.setup(user_config)
  if monitoring_state.initialized then
    logger.warn("monitoring", "Monitoring system already initialized")
    return true
  end
  
  monitoring_state.start_time = vim.loop.hrtime() / 1000000
  
  -- 合并配置
  monitoring_state.config = vim.tbl_deep_extend("force", default_config, user_config or {})
  
  logger.info("monitoring", "Initializing monitoring system")
  
  -- 初始化核心模块
  local state_manager = get_module("state_manager")
  if state_manager then
    state_manager.update_config(monitoring_state.config.state_manager)
    monitoring_state.modules.state_manager = state_manager
  else
    logger.error("monitoring", "Failed to initialize state manager")
    return false
  end
  
  local event_listener = get_module("event_listener")
  if event_listener then
    event_listener.update_config(monitoring_state.config.event_listener)
    monitoring_state.modules.event_listener = event_listener
  else
    logger.error("monitoring", "Failed to initialize event listener")
    return false
  end
  
  -- 初始化监控适配器
  if monitoring_state.config.monitors.websocket then
    local websocket_monitor = get_module("websocket_monitor")
    if websocket_monitor then
      monitoring_state.modules.websocket_monitor = websocket_monitor
    end
  end
  
  if monitoring_state.config.monitors.tool_call then
    local tool_call_monitor = get_module("tool_call_monitor")
    if tool_call_monitor then
      monitoring_state.modules.tool_call_monitor = tool_call_monitor
    end
  end
  
  if monitoring_state.config.monitors.terminal then
    local terminal_monitor = get_module("terminal_monitor")
    if terminal_monitor then
      monitoring_state.modules.terminal_monitor = terminal_monitor
    end
  end
  
  -- 初始化智能状态分析器
  if monitoring_state.config.monitors.intelligent_analyzer then
    local intelligent_analyzer = get_module("intelligent_state_analyzer")
    if intelligent_analyzer then
      monitoring_state.modules.intelligent_analyzer = intelligent_analyzer
    end
  end
  
  -- 设置定期健康检查
  if monitoring_state.config.performance.health_check_interval > 0 then
    local health_timer = vim.loop.new_timer()
    health_timer:start(
      monitoring_state.config.performance.health_check_interval,
      monitoring_state.config.performance.health_check_interval,
      vim.schedule_wrap(function()
        M.health_check()
      end)
    )
    monitoring_state.health_timer = health_timer
  end
  
  -- 设置定期清理
  if monitoring_state.config.performance.cleanup_interval > 0 then
    local cleanup_timer = vim.loop.new_timer()
    cleanup_timer:start(
      monitoring_state.config.performance.cleanup_interval,
      monitoring_state.config.performance.cleanup_interval,
      vim.schedule_wrap(function()
        M.cleanup()
      end)
    )
    monitoring_state.cleanup_timer = cleanup_timer
  end
  
  monitoring_state.initialized = true
  
  -- 触发初始化完成事件
  if event_listener then
    event_listener.emit("monitoring_system_initialized", {
      config = vim.deepcopy(monitoring_state.config),
      modules = vim.tbl_keys(monitoring_state.modules),
      start_time = monitoring_state.start_time
    })
  end
  
  return true
end

--- 激活监控适配器
--- @param server_module table|nil 服务器模块引用
--- @param tools_module table|nil 工具模块引用  
--- @param terminal_module table|nil 终端模块引用
--- @return boolean success 是否激活成功
function M.activate_monitors(server_module, tools_module, terminal_module)
  if not monitoring_state.initialized then
    logger.error("monitoring", "Monitoring system not initialized")
    return false
  end
  
  local success_count = 0
  local total_monitors = 0
  
  -- 激活WebSocket监控
  if monitoring_state.modules.websocket_monitor and server_module then
    total_monitors = total_monitors + 1
    if monitoring_state.modules.websocket_monitor.setup(server_module) then
      success_count = success_count + 1
    else
      logger.error("monitoring", "Failed to activate WebSocket monitor")
    end
  end
  
  -- 激活工具调用监控
  if monitoring_state.modules.tool_call_monitor and tools_module then
    total_monitors = total_monitors + 1
    if monitoring_state.modules.tool_call_monitor.setup(tools_module) then
      success_count = success_count + 1
    else
      logger.error("monitoring", "Failed to activate tool call monitor")
    end
  end
  
  -- 激活终端进程监控
  if monitoring_state.modules.terminal_monitor and terminal_module then
    total_monitors = total_monitors + 1
    if monitoring_state.modules.terminal_monitor.setup(terminal_module) then
      success_count = success_count + 1
    else
      logger.error("monitoring", "Failed to activate terminal monitor")
    end
  end
  
  -- 激活智能状态分析器
  if monitoring_state.modules.intelligent_analyzer then
    total_monitors = total_monitors + 1
    if monitoring_state.modules.intelligent_analyzer.start(monitoring_state.config.intelligent_analyzer) then
      success_count = success_count + 1
    else
      logger.error("monitoring", "Failed to activate intelligent state analyzer")
    end
  end
  
  logger.info("monitoring", string.format(
    "Monitoring activation completed: %d/%d monitors activated",
    success_count, total_monitors
  ))
  
  -- 触发激活完成事件
  if monitoring_state.modules.event_listener then
    monitoring_state.modules.event_listener.emit("monitors_activated", {
      success_count = success_count,
      total_monitors = total_monitors,
      activated_monitors = vim.tbl_keys(monitoring_state.modules)
    })
  end
  
  return success_count == total_monitors
end

--- 获取当前状态
--- @return table status 当前状态信息
function M.get_status()
  if not monitoring_state.initialized then
    return {
      initialized = false,
      error = "Monitoring system not initialized"
    }
  end
  
  local state_manager = monitoring_state.modules.state_manager
  local current_state_info = state_manager and state_manager.get_state_info() or {}
  
  return {
    initialized = true,
    current_state = current_state_info.current_state or "unknown",
    state_info = current_state_info,
    uptime = (vim.loop.hrtime() / 1000000) - monitoring_state.start_time,
    modules = vim.tbl_keys(monitoring_state.modules),
    config = vim.deepcopy(monitoring_state.config)
  }
end

--- 获取终端缓冲区状态快照
--- @return table buffer_states 终端缓冲区状态信息  
local function get_terminal_buffer_states()
  local buffer_states = {}
  
  -- 获取所有缓冲区
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_valid(buf) then
      local buf_type = vim.api.nvim_buf_get_option(buf, 'buftype')
      if buf_type == 'terminal' then
        local buf_name = vim.api.nvim_buf_get_name(buf)
        local job_id = vim.b[buf].terminal_job_id
        local is_running = job_id and vim.fn.jobwait({job_id}, 0)[1] == -1
        
        table.insert(buffer_states, {
          buffer_id = buf,
          buffer_name = buf_name,
          job_id = job_id,
          is_running = is_running,
          last_activity = vim.loop.hrtime() / 1000000
        })
      end
    end
  end
  
  return buffer_states
end

--- 记录终端缓冲区状态到日志
local function log_terminal_buffer_states()
  local states = get_terminal_buffer_states()
  if #states > 0 then
    logger.info("monitoring", "Terminal buffer states:")
    for i, state in ipairs(states) do
      logger.info("monitoring", string.format(
        "  Buffer %d: id=%d, job_id=%s, running=%s, name=%s",
        i, state.buffer_id, 
        state.job_id or "nil",
        state.is_running and "yes" or "no",
        state.buffer_name
      ))
    end
  else
    logger.info("monitoring", "No terminal buffers found")
  end
end

--- 获取详细统计信息
--- @return table stats 详细统计信息
function M.get_detailed_stats()
  if not monitoring_state.initialized then
    return { error = "Monitoring system not initialized" }
  end
  
  -- 记录终端缓冲区状态快照
  log_terminal_buffer_states()
  
  local stats = {
    system = M.get_status(),
    state_manager = {},
    websocket = {},
    tool_calls = {},
    terminal = {},
    events = {},
    terminal_buffers = get_terminal_buffer_states()
  }
  
  -- 状态管理器统计
  if monitoring_state.modules.state_manager then
    stats.state_manager = {
      current_state = monitoring_state.modules.state_manager.get_current_state(),
      state_info = monitoring_state.modules.state_manager.get_state_info(),
      metrics = monitoring_state.modules.state_manager.get_metrics(),
      history = monitoring_state.modules.state_manager.get_history(10) -- 最近10条
    }
  end
  
  -- WebSocket监控统计
  if monitoring_state.modules.websocket_monitor then
    stats.websocket = monitoring_state.modules.websocket_monitor.get_status()
  end
  
  -- 工具调用监控统计
  if monitoring_state.modules.tool_call_monitor then
    stats.tool_calls = monitoring_state.modules.tool_call_monitor.get_status()
  end
  
  -- 终端进程监控统计
  if monitoring_state.modules.terminal_monitor then
    stats.terminal = monitoring_state.modules.terminal_monitor.get_status()
  end
  
  -- 事件统计
  if monitoring_state.modules.event_listener then
    stats.events = monitoring_state.modules.event_listener.get_stats()
  end
  
  -- 智能状态分析器统计
  if monitoring_state.modules.intelligent_analyzer then
    stats.intelligent_analyzer = monitoring_state.modules.intelligent_analyzer.get_status()
  end
  
  return stats
end

--- 获取状态历史
--- @param limit number|nil 限制数量
--- @return table[] history 状态历史
function M.get_history(limit)
  if not monitoring_state.modules.state_manager then
    return {}
  end
  
  return monitoring_state.modules.state_manager.get_history(limit)
end

--- 获取事件历史
--- @param event string|nil 事件类型过滤
--- @param limit number|nil 限制数量
--- @return table[] history 事件历史
function M.get_event_history(event, limit)
  if not monitoring_state.modules.event_listener then
    return {}
  end
  
  return monitoring_state.modules.event_listener.get_history(event, limit)
end

--- 订阅状态变化事件
--- @param callback function 回调函数
--- @return string|nil callback_id 回调ID，失败则返回nil
function M.on_state_change(callback)
  if not monitoring_state.modules.event_listener then
    return nil
  end
  
  return monitoring_state.modules.event_listener.on("state_changed", callback)
end

--- 订阅任意事件
--- @param event string 事件名称
--- @param callback function 回调函数
--- @param opts table|nil 选项
--- @return string|nil callback_id 回调ID，失败则返回nil
function M.on(event, callback, opts)
  if not monitoring_state.modules.event_listener then
    return nil
  end
  
  return monitoring_state.modules.event_listener.on(event, callback, opts)
end

--- 取消事件订阅
--- @param event string 事件名称
--- @param callback_id string 回调ID
--- @return boolean success 是否成功
function M.off(event, callback_id)
  if not monitoring_state.modules.event_listener then
    return false
  end
  
  return monitoring_state.modules.event_listener.off(event, callback_id)
end

--- 健康检查
--- @return table health_report 健康检查报告
function M.health_check()
  local health_report = {
    overall_healthy = true,
    timestamp = vim.loop.hrtime() / 1000000,
    issues = {},
    module_health = {}
  }
  
  if not monitoring_state.initialized then
    health_report.overall_healthy = false
    table.insert(health_report.issues, "监控系统未初始化")
    return health_report
  end
  
  -- 检查各个模块的健康状态
  for module_name, module in pairs(monitoring_state.modules) do
    if module.health_check then
      local healthy, issue = module.health_check()
      health_report.module_health[module_name] = {
        healthy = healthy,
        issue = issue
      }
      
      if not healthy then
        health_report.overall_healthy = false
        table.insert(health_report.issues, string.format("%s: %s", module_name, issue))
      end
    end
  end
  
  -- 检查内存使用
  local memory_usage = collectgarbage("count") * 1024 -- 转换为字节
  if memory_usage > monitoring_state.config.performance.max_memory_usage then
    health_report.overall_healthy = false
    table.insert(health_report.issues, string.format(
      "内存使用过高: %.2fMB (限制: %.2fMB)",
      memory_usage / 1024 / 1024,
      monitoring_state.config.performance.max_memory_usage / 1024 / 1024
    ))
  end
  
  health_report.memory_usage = memory_usage
  
  -- 如果有问题，触发健康检查事件
  if not health_report.overall_healthy and monitoring_state.modules.event_listener then
    monitoring_state.modules.event_listener.emit("health_check_failed", health_report)
  end
  
  return health_report
end

--- 清理过期数据
function M.cleanup()
  if not monitoring_state.initialized then
    return
  end
  
  logger.debug("monitoring", "Performing cleanup")
  
  -- 强制垃圾回收
  collectgarbage("collect")
  
  -- 触发清理事件
  if monitoring_state.modules.event_listener then
    monitoring_state.modules.event_listener.emit("cleanup_performed", {
      timestamp = vim.loop.hrtime() / 1000000,
      memory_before = collectgarbage("count") * 1024
    })
  end
  
end

--- 重置监控系统
function M.reset()
  if not monitoring_state.initialized then
    return
  end
  
  logger.info("monitoring", "Resetting monitoring system")
  
  -- 重置各个模块
  for module_name, module in pairs(monitoring_state.modules) do
    if module.reset then
      module.reset()
    end
  end
  
  -- 触发重置事件
  if monitoring_state.modules.event_listener then
    monitoring_state.modules.event_listener.emit("monitoring_system_reset", {
      timestamp = vim.loop.hrtime() / 1000000
    })
  end
  
end

--- 关闭监控系统
function M.shutdown()
  if not monitoring_state.initialized then
    return
  end
  
  logger.info("monitoring", "Shutting down monitoring system")
  
  -- 停止智能状态分析器
  if monitoring_state.modules.intelligent_analyzer then
    monitoring_state.modules.intelligent_analyzer.stop()
  end
  
  -- 清理定时器
  if monitoring_state.health_timer then
    monitoring_state.health_timer:stop()
    monitoring_state.health_timer:close()
    monitoring_state.health_timer = nil
  end
  
  if monitoring_state.cleanup_timer then
    monitoring_state.cleanup_timer:stop()
    monitoring_state.cleanup_timer:close()
    monitoring_state.cleanup_timer = nil
  end
  
  -- 触发关闭事件
  if monitoring_state.modules.event_listener then
    monitoring_state.modules.event_listener.emit("monitoring_system_shutdown", {
      timestamp = vim.loop.hrtime() / 1000000,
      uptime = (vim.loop.hrtime() / 1000000) - monitoring_state.start_time
    })
  end
  
  -- 重置状态
  monitoring_state.initialized = false
  monitoring_state.modules = {}
  lazy_modules = {}
  
end

--- 更新配置
--- @param new_config table 新配置
function M.update_config(new_config)
  if not monitoring_state.initialized then
    logger.error("monitoring", "Cannot update config: monitoring system not initialized")
    return false
  end
  
  monitoring_state.config = vim.tbl_deep_extend("force", monitoring_state.config, new_config)
  
  -- 更新各模块配置
  for module_name, module in pairs(monitoring_state.modules) do
    if module.update_config and monitoring_state.config[module_name] then
      module.update_config(monitoring_state.config[module_name])
    end
  end
  
  return true
end

--- 检查监控系统是否已初始化
--- @return boolean initialized 是否已初始化
function M.is_initialized()
  return monitoring_state.initialized
end

return M