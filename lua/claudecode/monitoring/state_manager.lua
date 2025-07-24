--- Claude Code 监控状态管理器
-- 负责管理Claude Code的执行状态，包括状态转换、历史记录和性能指标
-- @module claudecode.monitoring.state_manager

local logger = require("claudecode.logger")

local M = {}

--- 状态枚举
M.States = {
  DISCONNECTED = "disconnected",
  IDLE = "idle",
  EXECUTING = "executing", 
  INTERRUPTED = "interrupted"
}

--- 执行操作类型
M.OperationTypes = {
  TOOL_CALL = "tool_call",
  REQUEST_HANDLING = "request_handling",
  CONNECTION_SETUP = "connection_setup"
}

--- 初始化状态数据结构
local function init_state()
  return {
    current = M.States.DISCONNECTED,
    last_changed = vim.loop.hrtime() / 1000000, -- 转换为毫秒
    execution_count = 0,
    current_operation = nil,
    history = {},
    metrics = {
      total_executions = 0,
      total_execution_time = 0,
      avg_execution_time = 0,
      last_execution_time = 0,
      last_execution_start = 0,
      connection_count = 0,
      disconnection_count = 0
    },
    clients = {},
    config = {
      history_limit = 100,
      enable_metrics = true
    }
  }
end

--- 全局状态实例
M.state = init_state()

--- 状态历史记录项
--- @class StateHistoryItem
--- @field state string 状态名称
--- @field timestamp number 时间戳（毫秒）
--- @field operation_type string|nil 操作类型
--- @field operation_details table|nil 操作详情
--- @field duration number|nil 持续时间（毫秒）

--- 添加状态历史记录
--- @param old_state string 旧状态
--- @param new_state string 新状态
--- @param operation_type string|nil 操作类型
--- @param operation_details table|nil 操作详情
local function add_history_entry(old_state, new_state, operation_type, operation_details)
  local now = vim.loop.hrtime() / 1000000
  local duration = now - M.state.last_changed
  
  local entry = {
    from_state = old_state,
    to_state = new_state,
    timestamp = now,
    operation_type = operation_type,
    operation_details = operation_details,
    duration = duration
  }
  
  table.insert(M.state.history, entry)
  
  -- 限制历史记录长度
  if #M.state.history > M.state.config.history_limit then
    table.remove(M.state.history, 1)
  end
  
  logger.info("monitoring", string.format(
    "State history: %s -> %s (%.2fms)", 
    old_state, new_state, duration
  ))
end

--- 更新性能指标
--- @param operation_type string 操作类型
--- @param duration number 持续时间（毫秒）
local function update_metrics(operation_type, duration)
  if not M.state.config.enable_metrics then
    return
  end
  
  local metrics = M.state.metrics
  
  if operation_type == M.OperationTypes.TOOL_CALL then
    metrics.total_executions = metrics.total_executions + 1
    metrics.total_execution_time = metrics.total_execution_time + duration
    metrics.avg_execution_time = metrics.total_execution_time / metrics.total_executions
    metrics.last_execution_time = duration
  end
  
  logger.info("monitoring", string.format(
    "Metrics updated: %s took %.2fms, avg: %.2fms", 
    operation_type, duration, metrics.avg_execution_time
  ))
end

--- 检查状态转换是否有效
--- @param from_state string 源状态
--- @param to_state string 目标状态
--- @return boolean valid 是否为有效转换
local function is_valid_transition(from_state, to_state)
  local valid_transitions = {
    [M.States.DISCONNECTED] = { M.States.IDLE, M.States.EXECUTING, M.States.DISCONNECTED },
    [M.States.IDLE] = { M.States.EXECUTING, M.States.DISCONNECTED, M.States.INTERRUPTED, M.States.IDLE },
    [M.States.EXECUTING] = { M.States.IDLE, M.States.DISCONNECTED, M.States.INTERRUPTED, M.States.EXECUTING },
    [M.States.INTERRUPTED] = { M.States.IDLE, M.States.EXECUTING, M.States.DISCONNECTED, M.States.INTERRUPTED }
  }
  
  local allowed = valid_transitions[from_state] or {}
  for _, allowed_state in ipairs(allowed) do
    if allowed_state == to_state then
      return true
    end
  end
  
  return false
end

-- 移除了completion_timer相关逻辑，因为已不再使用completed状态

--- 设置当前状态
--- @param new_state string 新状态
--- @param operation_type string|nil 操作类型
--- @param operation_details table|nil 操作详情
--- @return boolean success 是否设置成功
function M.set_state(new_state, operation_type, operation_details)
  local old_state = M.state.current
  
  logger.info("monitoring", string.format(
    "set_state called: %s -> %s (operation: %s)", 
    old_state, new_state, operation_type or "nil"
  ))
  
  -- 检查状态转换是否有效
  if not is_valid_transition(old_state, new_state) then
    logger.warn("monitoring", string.format(
      "Invalid state transition: %s -> %s", 
      old_state, new_state
    ))
    return false
  end
  
  -- 如果状态没有变化，跳过
  if old_state == new_state then
    logger.info("monitoring", string.format(
      "State unchanged: %s", old_state
    ))
    return true
  end
  
  -- 计算持续时间并更新指标
  local now = vim.loop.hrtime() / 1000000
  local duration = now - M.state.last_changed
  
  if old_state == M.States.EXECUTING and M.state.current_operation then
    update_metrics(M.state.current_operation.type, duration)
  end
  
  -- 更新状态
  M.state.current = new_state
  M.state.last_changed = now
  
  logger.info("monitoring", string.format(
    "State changed: %s -> %s (operation: %s)", 
    old_state, new_state, operation_type or "nil"
  ))
  
  -- 根据新状态设置操作信息
  if new_state == M.States.EXECUTING then
    M.state.current_operation = {
      type = operation_type or M.OperationTypes.REQUEST_HANDLING,
      details = operation_details,
      start_time = now
    }
    M.state.execution_count = M.state.execution_count + 1
    M.state.metrics.last_execution_start = now
  else
    M.state.current_operation = nil
  end
  
  -- 添加历史记录
  add_history_entry(old_state, new_state, operation_type, operation_details)
  
  -- 触发事件（如果事件系统已加载）
  local ok, event_listener = pcall(require, "claudecode.monitoring.event_listener")
  if ok then
    event_listener.emit("state_changed", {
      from_state = old_state,
      to_state = new_state,
      operation_type = operation_type,
      operation_details = operation_details,
      timestamp = now
    })
  end
  
  logger.info("monitoring", string.format(
    "Claude Code state: %s -> %s%s", 
    old_state, 
    new_state,
    operation_type and (" (" .. operation_type .. ")") or ""
  ))
  
  return true
end

--- 获取当前状态
--- @return string current_state 当前状态
function M.get_current_state()
  return M.state.current
end

--- 获取完整状态信息
--- @return table state_info 完整状态信息
function M.get_state_info()
  local now = vim.loop.hrtime() / 1000000
  local current_duration = now - M.state.last_changed
  
  return {
    current_state = M.state.current,
    last_changed = M.state.last_changed,
    current_duration = current_duration,
    execution_count = M.state.execution_count,
    current_operation = M.state.current_operation,
    metrics = vim.deepcopy(M.state.metrics),
    client_count = vim.tbl_count(M.state.clients),
    uptime = now - (M.state.history[1] and M.state.history[1].timestamp or now)
  }
end

--- 获取状态历史
--- @param limit number|nil 限制返回数量
--- @return table[] history 状态历史列表
function M.get_history(limit)
  local history = vim.deepcopy(M.state.history)
  if limit and limit > 0 then
    local start = math.max(1, #history - limit + 1)
    return vim.list_slice(history, start)
  end
  return history
end

--- 获取性能指标
--- @return table metrics 性能指标
function M.get_metrics()
  return vim.deepcopy(M.state.metrics)
end

--- 添加客户端连接
--- @param client_id string 客户端ID
--- @param client_info table 客户端信息
function M.add_client(client_id, client_info)
  M.state.clients[client_id] = {
    id = client_id,
    info = client_info,
    connected_at = vim.loop.hrtime() / 1000000
  }
  
  M.state.metrics.connection_count = M.state.metrics.connection_count + 1
  
  -- 如果是第一个客户端连接，切换到IDLE状态
  if vim.tbl_count(M.state.clients) == 1 and M.state.current == M.States.DISCONNECTED then
    M.set_state(M.States.IDLE, M.OperationTypes.CONNECTION_SETUP, {
      client_id = client_id,
      reason = "first_client_connected"
    })
  end
end

--- 移除客户端连接
--- @param client_id string 客户端ID
--- @param reason string|nil 断开原因
function M.remove_client(client_id, reason)
  if M.state.clients[client_id] then
    M.state.clients[client_id] = nil
    M.state.metrics.disconnection_count = M.state.metrics.disconnection_count + 1
  end
  
  -- 如果没有客户端连接，切换到DISCONNECTED状态
  if vim.tbl_count(M.state.clients) == 0 then
    M.set_state(M.States.DISCONNECTED, nil, {
      client_id = client_id,
      reason = reason or "all_clients_disconnected"
    })
  end
end

--- 重置状态和指标
function M.reset()
  -- 移除了completion_timer清理逻辑
  
  M.state = init_state()
end

--- 更新配置
--- @param config table 新配置
function M.update_config(config)
  M.state.config = vim.tbl_deep_extend("force", M.state.config, config)
end

--- 检查状态是否正常
--- @return boolean healthy 是否健康
--- @return string|nil issue 问题描述
function M.health_check()
  local now = vim.loop.hrtime() / 1000000
  local current_duration = now - M.state.last_changed
  
  -- 检查是否在执行状态停留太久
  if M.state.current == M.States.EXECUTING and current_duration > 30000 then -- 30秒
    return false, "执行状态停留时间过长 (>30s)"
  end
  
  -- 检查是否有孤立的客户端连接
  if vim.tbl_count(M.state.clients) > 0 and M.state.current == M.States.DISCONNECTED then
    return false, "状态不一致：有客户端连接但状态为断开"
  end
  
  return true
end

return M