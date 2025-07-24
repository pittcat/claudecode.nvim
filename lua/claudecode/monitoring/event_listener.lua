--- Claude Code 监控事件监听器
-- 提供事件发布订阅机制，用于状态变化通知和系统解耦
-- @module claudecode.monitoring.event_listener

local logger = require("claudecode.logger")

local M = {}

--- 事件类型枚举
M.Events = {
  STATE_CHANGED = "state_changed",
  EXECUTION_STARTED = "execution_started",
  EXECUTION_COMPLETED = "execution_completed", 
  CONNECTION_ESTABLISHED = "connection_established",
  CONNECTION_LOST = "connection_lost",
  TOOL_CALL_STARTED = "tool_call_started",
  TOOL_CALL_COMPLETED = "tool_call_completed",
  REQUEST_STARTED = "request_started",
  REQUEST_COMPLETED = "request_completed",
  TERMINAL_PROCESS_EXITED = "terminal_process_exited",
  ERROR_OCCURRED = "error_occurred"
}

--- 回调存储结构
--- @class EventCallback
--- @field id string 回调ID
--- @field callback function 回调函数
--- @field once boolean 是否只执行一次
--- @field created_at number 创建时间

--- 事件回调存储
--- @type table<string, EventCallback[]>
local callbacks = {}

--- 事件历史记录
--- @type table[]
local event_history = {}

--- 配置选项
local config = {
  max_history = 200,  -- 最大事件历史数量
  enable_history = true,  -- 是否启用事件历史
  debug_events = false  -- 是否启用事件调试日志
}

--- 生成唯一ID
--- @return string id 唯一标识符
local function generate_id()
  return tostring(vim.loop.hrtime())
end

--- 添加事件到历史记录
--- @param event string 事件名称
--- @param data table 事件数据
local function add_to_history(event, data)
  if not config.enable_history then
    return
  end
  
  local entry = {
    event = event,
    data = vim.deepcopy(data),
    timestamp = vim.loop.hrtime() / 1000000,
    id = generate_id()
  }
  
  table.insert(event_history, entry)
  
  -- 限制历史记录长度
  if #event_history > config.max_history then
    table.remove(event_history, 1)
  end
end

--- 注册事件回调
--- @param event string 事件名称
--- @param callback function 回调函数，接收 (event, data) 参数
--- @param opts table|nil 选项：{ once: boolean, id: string }
--- @return string callback_id 回调ID，用于取消订阅
function M.on(event, callback, opts)
  opts = opts or {}
  
  if type(event) ~= "string" then
    error("Event name must be a string")
  end
  
  if type(callback) ~= "function" then
    error("Callback must be a function")
  end
  
  -- 初始化事件回调列表
  if not callbacks[event] then
    callbacks[event] = {}
  end
  
  local callback_id = opts.id or generate_id()
  
  local callback_info = {
    id = callback_id,
    callback = callback,
    once = opts.once or false,
    created_at = vim.loop.hrtime() / 1000000
  }
  
  table.insert(callbacks[event], callback_info)
  
  if config.debug_events then
    logger.debug("monitoring", string.format(
      "Event listener registered: %s (id: %s, once: %s)",
      event, callback_id, tostring(callback_info.once)
    ))
  end
  
  return callback_id
end

--- 注册一次性事件回调
--- @param event string 事件名称  
--- @param callback function 回调函数
--- @return string callback_id 回调ID
function M.once(event, callback)
  return M.on(event, callback, { once = true })
end

--- 取消事件回调
--- @param event string 事件名称
--- @param callback_id string 回调ID
--- @return boolean success 是否成功取消
function M.off(event, callback_id)
  if not callbacks[event] then
    return false
  end
  
  for i, callback_info in ipairs(callbacks[event]) do
    if callback_info.id == callback_id then
      table.remove(callbacks[event], i)
      
      if config.debug_events then
        logger.debug("monitoring", string.format(
          "Event listener removed: %s (id: %s)", 
          event, callback_id
        ))
      end
      
      return true
    end
  end
  
  return false
end

--- 取消所有事件回调
--- @param event string 事件名称
--- @return number removed_count 取消的回调数量
function M.off_all(event)
  if not callbacks[event] then
    return 0
  end
  
  local count = #callbacks[event]
  callbacks[event] = {}
  
  if config.debug_events then
    logger.debug("monitoring", string.format(
      "All event listeners removed for: %s (%d callbacks)", 
      event, count
    ))
  end
  
  return count
end

--- 发射事件
--- @param event string 事件名称
--- @param data table|nil 事件数据
--- @return number callback_count 执行的回调数量
function M.emit(event, data)
  data = data or {}
  
  -- 添加到历史记录
  add_to_history(event, data)
  
  if config.debug_events then
    logger.debug("monitoring", string.format(
      "Event emitted: %s with data: %s", 
      event, vim.inspect(data)
    ))
  end
  
  -- 如果没有注册的回调，直接返回
  if not callbacks[event] or #callbacks[event] == 0 then
    return 0
  end
  
  local callback_count = 0
  local to_remove = {}
  
  -- 执行所有回调
  for i, callback_info in ipairs(callbacks[event]) do
    local success, result = pcall(callback_info.callback, event, data)
    
    if success then
      callback_count = callback_count + 1
      
      -- 如果是一次性回调，标记为待删除
      if callback_info.once then
        table.insert(to_remove, i)
      end
    else
      logger.error("monitoring", string.format(
        "Event callback error for %s (id: %s): %s",
        event, callback_info.id, tostring(result)
      ))
      
      -- 触发错误事件
      if event ~= M.Events.ERROR_OCCURRED then
        M.emit(M.Events.ERROR_OCCURRED, {
          source = "event_callback",
          original_event = event,
          callback_id = callback_info.id,
          error = result
        })
      end
    end
  end
  
  -- 移除一次性回调（从后往前删除以避免索引问题）
  for i = #to_remove, 1, -1 do
    local index = to_remove[i]
    local callback_info = callbacks[event][index]
    table.remove(callbacks[event], index)
    
    if config.debug_events then
      logger.debug("monitoring", string.format(
        "One-time event listener removed: %s (id: %s)",
        event, callback_info.id
      ))
    end
  end
  
  return callback_count
end

--- 异步发射事件（在下一个事件循环中执行）
--- @param event string 事件名称
--- @param data table|nil 事件数据
function M.emit_async(event, data)
  vim.schedule(function()
    M.emit(event, data)
  end)
end

--- 获取事件历史
--- @param event string|nil 事件名称过滤，nil表示获取所有事件
--- @param limit number|nil 限制数量
--- @return table[] history 事件历史列表
function M.get_history(event, limit)
  local filtered_history = event_history
  
  -- 按事件名称过滤
  if event then
    filtered_history = {}
    for _, entry in ipairs(event_history) do
      if entry.event == event then
        table.insert(filtered_history, entry)
      end
    end
  end
  
  -- 应用数量限制
  if limit and limit > 0 then
    local start = math.max(1, #filtered_history - limit + 1)
    return vim.list_slice(filtered_history, start)
  end
  
  return vim.deepcopy(filtered_history)
end

--- 获取已注册的事件回调信息
--- @param event string|nil 事件名称，nil表示获取所有事件
--- @return table callback_info 回调信息
function M.get_listeners(event)
  if event then
    return {
      [event] = vim.deepcopy(callbacks[event] or {})
    }
  end
  
  local all_callbacks = {}
  for event_name, callback_list in pairs(callbacks) do
    all_callbacks[event_name] = vim.deepcopy(callback_list)
  end
  
  return all_callbacks
end

--- 获取事件统计信息
--- @return table stats 统计信息
function M.get_stats()
  local total_callbacks = 0
  local events_with_callbacks = 0
  local event_counts = {}
  
  for event_name, callback_list in pairs(callbacks) do
    local count = #callback_list
    if count > 0 then
      events_with_callbacks = events_with_callbacks + 1
      total_callbacks = total_callbacks + count
      event_counts[event_name] = count
    end
  end
  
  -- 统计历史事件
  local history_by_event = {}
  for _, entry in ipairs(event_history) do
    history_by_event[entry.event] = (history_by_event[entry.event] or 0) + 1
  end
  
  return {
    total_callbacks = total_callbacks,
    events_with_callbacks = events_with_callbacks,
    event_counts = event_counts,
    history_total = #event_history,
    history_by_event = history_by_event,
    config = vim.deepcopy(config)
  }
end

--- 清空事件历史
function M.clear_history()
  event_history = {}
  logger.debug("monitoring", "Event history cleared")
end

--- 重置事件监听器（清除所有回调和历史）
function M.reset()
  callbacks = {}
  event_history = {}
  logger.info("monitoring", "Event listener reset")
end

--- 更新配置
--- @param new_config table 新配置
function M.update_config(new_config)
  config = vim.tbl_deep_extend("force", config, new_config)
  logger.debug("monitoring", "Event listener config updated")
end

--- 等待特定事件（Promise风格）
--- @param event string 事件名称
--- @param timeout number|nil 超时时间（毫秒），nil表示不超时
--- @param condition function|nil 条件函数，接收事件数据，返回boolean
--- @return table|nil result 事件数据，超时则返回nil
function M.wait_for(event, timeout, condition)
  local result = nil
  local completed = false
  
  -- 注册一次性监听器
  local callback_id = M.once(event, function(_, data)
    if not condition or condition(data) then
      result = data
      completed = true
    end
  end)
  
  -- 设置超时
  local timer = nil
  if timeout then
    timer = vim.loop.new_timer()
    timer:start(timeout, 0, function()
      completed = true
      timer:close()
    end)
  end
  
  -- 等待完成
  vim.wait(timeout or 30000, function()
    return completed
  end)
  
  -- 清理
  if timer then
    timer:close()
  end
  M.off(event, callback_id)
  
  return result
end

return M