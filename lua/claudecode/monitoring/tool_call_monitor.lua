--- 工具调用监控适配器
-- 监控Claude Code工具调用的执行状态和性能
-- @module claudecode.monitoring.tool_call_monitor

local logger = require("claudecode.logger")
local state_manager = require("claudecode.monitoring.state_manager")  
local event_listener = require("claudecode.monitoring.event_listener")

local M = {}

--- 是否已设置监控
local monitoring_setup = false

--- 原始工具模块引用
local tools_module = nil

--- 工具调用跟踪
local tool_tracking = {
  active_calls = {},
  call_history = {},
  tool_stats = {},
  total_calls = 0
}

--- 延迟响应跟踪
local deferred_tracking = {
  active_deferred = {},
  deferred_history = {}
}

--- 工具调用信息
--- @class ToolCallInfo
--- @field call_id string 调用ID
--- @field tool_name string 工具名称
--- @field client_id string 客户端ID
--- @field start_time number 开始时间
--- @field arguments table 调用参数
--- @field request_id string|nil 请求ID

--- 生成工具调用ID
--- @return string call_id 调用标识符
local function generate_call_id()
  return "tool_" .. tostring(vim.loop.hrtime())
end

--- 记录工具统计信息
--- @param tool_name string 工具名称
--- @param duration number 执行时间
--- @param success boolean 是否成功
local function update_tool_stats(tool_name, duration, success)
  if not tool_tracking.tool_stats[tool_name] then
    tool_tracking.tool_stats[tool_name] = {
      total_calls = 0,
      total_duration = 0,
      avg_duration = 0,
      success_count = 0,
      error_count = 0,
      last_called = 0
    }
  end
  
  local stats = tool_tracking.tool_stats[tool_name]
  stats.total_calls = stats.total_calls + 1
  stats.total_duration = stats.total_duration + duration
  stats.avg_duration = stats.total_duration / stats.total_calls
  stats.last_called = vim.loop.hrtime() / 1000000
  
  if success then
    stats.success_count = stats.success_count + 1
  else
    stats.error_count = stats.error_count + 1
  end
end

--- 包装工具处理函数
--- @param original_handler function 原始处理函数
--- @param tool_name string 工具名称
--- @return function wrapped_handler 包装后的处理函数
local function wrap_tool_handler(original_handler, tool_name)
  return function(client, params)
    local call_id = generate_call_id()
    local start_time = vim.loop.hrtime() / 1000000
    
    -- 检查客户端连接状态并确保监控系统同步
    local current_state = state_manager.get_current_state()
    
    -- 如果当前状态是断开连接但有工具调用，说明有活跃的连接
    if current_state == "disconnected" then
      local client_id = client and client.id or "auto_detected_client"
      
      state_manager.add_client(client_id, {
        id = client_id,
        address = "detected_from_tool_call",
        connected_at = start_time,
        detection_method = "tool_call_monitor"
      })
      
      -- 触发连接建立事件
      event_listener.emit(event_listener.Events.CONNECTION_ESTABLISHED, {
        client_id = client_id,
        client_info = { id = client_id, method = "tool_call_detection" },
        total_connections = 1
      })
    end
    
    -- 记录工具调用开始
    local call_info = {
      call_id = call_id,
      tool_name = tool_name,
      client_id = client and client.id or "unknown",
      start_time = start_time,
      arguments = vim.deepcopy(params),
      request_id = params and params._request_id
    }
    
    tool_tracking.active_calls[call_id] = call_info
    tool_tracking.total_calls = tool_tracking.total_calls + 1
    
    -- 更新状态管理器
    state_manager.set_state(
      state_manager.States.EXECUTING,
      state_manager.OperationTypes.TOOL_CALL,
      {
        tool_name = tool_name,
        call_id = call_id,
        client_id = call_info.client_id,
        arguments = call_info.arguments
      }
    )
    
    -- 触发事件
    event_listener.emit(event_listener.Events.TOOL_CALL_STARTED, {
      call_id = call_id,
      tool_name = tool_name,
      client_id = call_info.client_id,
      arguments = call_info.arguments,
      start_time = start_time
    })
    
    
    -- 执行原始处理函数
    local success, result = pcall(original_handler, client, params)
    local end_time = vim.loop.hrtime() / 1000000
    local duration = end_time - start_time
    
    -- 处理结果
    local call_result = {
      success = success,
      result = success and result or nil,
      error = not success and result or nil,
      duration = duration,
      end_time = end_time
    }
    
    -- 检查是否为延迟响应
    local is_deferred = success and result and result._deferred
    
    if is_deferred then
      -- 处理延迟响应
      deferred_tracking.active_deferred[call_id] = {
        call_id = call_id,
        tool_name = tool_name,
        client_id = call_info.client_id,
        deferred_info = result,
        created_at = end_time
      }
      
      -- 延迟响应不立即更新为完成状态，保持执行状态
    else
      -- 立即完成的调用
      -- 移动到历史记录
      local history_entry = vim.tbl_extend("force", call_info, call_result)
      table.insert(tool_tracking.call_history, history_entry)
      tool_tracking.active_calls[call_id] = nil
      
      -- 限制历史记录长度
      if #tool_tracking.call_history > 300 then
        table.remove(tool_tracking.call_history, 1)
      end
      
      -- 更新工具统计
      update_tool_stats(tool_name, duration, success)
      
      -- 更新状态管理器（工具调用完成后转为idle）
      state_manager.set_state(
        state_manager.States.IDLE,
        state_manager.OperationTypes.TOOL_CALL,
        {
          tool_name = tool_name,
          call_id = call_id,
          client_id = call_info.client_id,
          success = success,
          duration = duration,
          reason = "tool_call_completed"
        }
      )
      
      -- 触发事件
      event_listener.emit(event_listener.Events.TOOL_CALL_COMPLETED, {
        call_id = call_id,
        tool_name = tool_name,
        client_id = call_info.client_id,
        success = success,
        result = call_result.result,
        error = call_result.error,
        duration = duration,
        end_time = end_time
      })
      
    end
    
    -- 返回原始结果
    if success then
      return result
    else
      error(result)
    end
  end
end

--- 监控延迟响应完成
--- @param deferred_info table 延迟响应信息
local function handle_deferred_completion(deferred_info)
  local call_id = deferred_info.call_id
  local deferred_entry = deferred_tracking.active_deferred[call_id]
  
  if not deferred_entry then
    logger.warn("tool_call_monitor", "Deferred response completed for unknown call: " .. call_id)
    return
  end
  
  local completion_time = vim.loop.hrtime() / 1000000
  local total_duration = completion_time - deferred_entry.created_at
  
  -- 移动到历史记录
  table.insert(deferred_tracking.deferred_history, {
    call_id = call_id,
    tool_name = deferred_entry.tool_name,
    client_id = deferred_entry.client_id,
    deferred_duration = total_duration,
    completed_at = completion_time,
    success = deferred_info.success,
    result = deferred_info.result,
    error = deferred_info.error
  })
  
  deferred_tracking.active_deferred[call_id] = nil
  
  -- 限制历史记录长度
  if #deferred_tracking.deferred_history > 100 then
    table.remove(deferred_tracking.deferred_history, 1)
  end
  
  -- 更新状态为idle（延迟工具调用完成后转为idle）
  state_manager.set_state(
    state_manager.States.IDLE,
    state_manager.OperationTypes.TOOL_CALL,
    {
      tool_name = deferred_entry.tool_name,
      call_id = call_id,
      client_id = deferred_entry.client_id,
      success = deferred_info.success,
      duration = total_duration,
      deferred = true,
      reason = "deferred_tool_call_completed"
    }
  )
  
  -- 触发事件
  event_listener.emit(event_listener.Events.TOOL_CALL_COMPLETED, {
    call_id = call_id,
    tool_name = deferred_entry.tool_name,
    client_id = deferred_entry.client_id,
    success = deferred_info.success,
    result = deferred_info.result,
    error = deferred_info.error,
    duration = total_duration,
    deferred = true,
    completed_at = completion_time
  })
end

--- 包装工具调用处理函数
--- @param original_handle_invoke function 原始调用处理函数
--- @return function wrapped_handle_invoke 包装后的处理函数
local function wrap_handle_invoke(original_handle_invoke)
  return function(client, params)
    local tool_name = params.name
    local call_id = generate_call_id()
    local start_time = vim.loop.hrtime() / 1000000
    
    -- 记录调用信息，传递请求ID用于关联
    params._request_id = call_id
    
    -- 调用原始处理函数
    local result = original_handle_invoke(client, params)
    
    -- 处理延迟响应的情况
    if result and result._deferred then
      -- 设置延迟响应完成回调
      local original_coroutine = result.coroutine
      result.coroutine = coroutine.create(function()
        local success, deferred_result = pcall(coroutine.resume, original_coroutine)
        
        handle_deferred_completion({
          call_id = call_id,
          success = success,
          result = success and deferred_result or nil,
          error = not success and deferred_result or nil
        })
        
        return deferred_result
      end)
    end
    
    return result
  end
end

--- 设置工具调用监控
--- @param tools_mod table 工具模块引用
--- @return boolean success 是否设置成功
function M.setup(tools_mod)
  if monitoring_setup then
    logger.warn("tool_call_monitor", "Tool call monitoring already setup")
    return false
  end
  
  if not tools_mod then
    logger.error("tool_call_monitor", "Tools module reference required")
    return false
  end
  
  tools_module = tools_mod
  
  -- 包装主要的工具调用处理函数
  if tools_module.handle_invoke then
    local original_handle_invoke = tools_module.handle_invoke
    tools_module.handle_invoke = wrap_handle_invoke(original_handle_invoke)
  end
  
  -- 包装个别工具的处理函数（如果需要更细粒度的监控）
  if tools_module.tools then
    for tool_name, tool_data in pairs(tools_module.tools) do
      if tool_data.handler then
        tool_data.handler = wrap_tool_handler(tool_data.handler, tool_name)
      end
    end
  end
  
  -- 监控全局延迟响应表
  local function monitor_deferred_responses()
    if _G.claude_deferred_responses then
      local count = 0
      for _ in pairs(_G.claude_deferred_responses) do
        count = count + 1
      end
    end
  end
  
  -- 定期检查延迟响应状态
  local deferred_check_timer = vim.loop.new_timer()
  deferred_check_timer:start(10000, 10000, vim.schedule_wrap(monitor_deferred_responses)) -- 每10秒检查一次
  
  monitoring_setup = true
  return true
end

--- 获取工具调用统计信息
--- @return table stats 调用统计
function M.get_call_stats()
  local active_count = vim.tbl_count(tool_tracking.active_calls)
  local completed_count = #tool_tracking.call_history
  local deferred_count = vim.tbl_count(deferred_tracking.active_deferred)
  
  return {
    total_calls = tool_tracking.total_calls,
    active_calls = active_count,
    completed_calls = completed_count,
    deferred_calls = deferred_count,
    active_call_details = vim.deepcopy(tool_tracking.active_calls),
    recent_calls = vim.list_slice(tool_tracking.call_history, -20), -- 最近20个调用
    tool_stats = vim.deepcopy(tool_tracking.tool_stats)
  }
end

--- 获取延迟响应统计信息
--- @return table stats 延迟响应统计
function M.get_deferred_stats()
  return {
    active_deferred = vim.tbl_count(deferred_tracking.active_deferred),
    completed_deferred = #deferred_tracking.deferred_history,
    active_deferred_details = vim.deepcopy(deferred_tracking.active_deferred),
    deferred_history = vim.deepcopy(deferred_tracking.deferred_history)
  }
end

--- 获取特定工具的统计信息
--- @param tool_name string 工具名称
--- @return table|nil stats 工具统计，不存在则返回nil
function M.get_tool_stats(tool_name)
  return tool_tracking.tool_stats[tool_name] and 
    vim.deepcopy(tool_tracking.tool_stats[tool_name]) or nil
end

--- 获取监控状态
--- @return table status 监控状态
function M.get_status()
  return {
    monitoring_active = monitoring_setup,
    tools_module_loaded = tools_module ~= nil,
    call_stats = M.get_call_stats(),
    deferred_stats = M.get_deferred_stats()
  }
end

--- 重置监控数据
function M.reset()
  tool_tracking = {
    active_calls = {},
    call_history = {},
    tool_stats = {},
    total_calls = 0
  }
  
  deferred_tracking = {
    active_deferred = {},
    deferred_history = {}
  }
end

--- 健康检查
--- @return boolean healthy 是否健康
--- @return string|nil issue 问题描述
function M.health_check()
  if not monitoring_setup then
    return false, "工具调用监控未设置"
  end
  
  if not tools_module then
    return false, "工具模块引用丢失"
  end
  
  local now = vim.loop.hrtime() / 1000000
  
  -- 检查长时间运行的工具调用
  local long_running_calls = 0
  for _, call_info in pairs(tool_tracking.active_calls) do
    local call_age = now - call_info.start_time
    if call_age > 60000 then -- 60秒
      long_running_calls = long_running_calls + 1
    end
  end
  
  if long_running_calls > 0 then
    return false, string.format("有 %d 个工具调用运行时间过长 (>60s)", long_running_calls)
  end
  
  -- 检查长时间未完成的延迟响应
  local stale_deferred = 0
  for _, deferred_info in pairs(deferred_tracking.active_deferred) do
    local deferred_age = now - deferred_info.created_at
    if deferred_age > 300000 then -- 5分钟
      stale_deferred = stale_deferred + 1
    end
  end
  
  if stale_deferred > 0 then
    return false, string.format("有 %d 个延迟响应长时间未完成 (>5min)", stale_deferred)
  end
  
  return true
end

return M