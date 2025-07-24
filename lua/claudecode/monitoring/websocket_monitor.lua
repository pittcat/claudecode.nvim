--- WebSocket 连接监控适配器
-- 监控WebSocket服务器的连接状态和消息处理
-- @module claudecode.monitoring.websocket_monitor

local logger = require("claudecode.logger")
local state_manager = require("claudecode.monitoring.state_manager")
local event_listener = require("claudecode.monitoring.event_listener")

local M = {}

--- 是否已设置监控
local monitoring_setup = false

--- 原始服务器模块引用
local server_module = nil

--- 连接状态跟踪
local connection_tracking = {
  active_connections = {},
  connection_history = {},
  last_activity = 0
}

--- 消息处理跟踪
local message_tracking = {
  active_requests = {},
  request_history = {},
  total_messages = 0
}

--- 获取连接信息
--- @param client table 客户端对象
--- @return table connection_info 连接信息
local function get_connection_info(client)
  return {
    id = client.id,
    connected_at = vim.loop.hrtime() / 1000000,
    address = client.address or "unknown",
    user_agent = client.user_agent or "unknown"
  }
end

--- 记录连接活动
--- @param activity_type string 活动类型
--- @param client_id string 客户端ID
--- @param details table|nil 详细信息
local function record_activity(activity_type, client_id, details)
  connection_tracking.last_activity = vim.loop.hrtime() / 1000000
  
  local activity = {
    type = activity_type,
    client_id = client_id,
    timestamp = connection_tracking.last_activity,
    details = details or {}
  }
  
  table.insert(connection_tracking.connection_history, activity)
  
  -- 限制历史记录长度
  if #connection_tracking.connection_history > 100 then
    table.remove(connection_tracking.connection_history, 1)
  end
end

--- 包装的连接回调
--- @param original_callback function 原始回调函数
--- @return function wrapped_callback 包装后的回调
local function wrap_connect_callback(original_callback)
  return function(client)
    local client_info = get_connection_info(client)
    
    -- 记录连接信息
    connection_tracking.active_connections[client.id] = client_info
    record_activity("connect", client.id, client_info)
    
    -- 更新状态管理器
    state_manager.add_client(client.id, client_info)
    
    -- 触发事件
    event_listener.emit(event_listener.Events.CONNECTION_ESTABLISHED, {
      client_id = client.id,
      client_info = client_info,
      total_connections = vim.tbl_count(connection_tracking.active_connections)
    })
    
    -- 调用原始回调
    if original_callback then
      original_callback(client)
    end
  end
end

--- 包装的断开连接回调
--- @param original_callback function 原始回调函数
--- @return function wrapped_callback 包装后的回调
local function wrap_disconnect_callback(original_callback)
  return function(client, code, reason)
    local client_info = connection_tracking.active_connections[client.id]
    
    -- 记录断开信息
    record_activity("disconnect", client.id, {
      code = code,
      reason = reason,
      duration = client_info and 
        (vim.loop.hrtime() / 1000000 - client_info.connected_at) or 0
    })
    
    -- 清除连接跟踪
    connection_tracking.active_connections[client.id] = nil
    
    -- 更新状态管理器
    state_manager.remove_client(client.id, reason)
    
    -- 触发事件
    event_listener.emit(event_listener.Events.CONNECTION_LOST, {
      client_id = client.id,
      client_info = client_info,
      code = code,
      reason = reason,
      remaining_connections = vim.tbl_count(connection_tracking.active_connections)
    })
    
    -- 调用原始回调
    if original_callback then
      original_callback(client, code, reason)
    end
  end
end

--- 包装的消息处理回调
--- @param original_callback function 原始回调函数
--- @return function wrapped_callback 包装后的回调
local function wrap_message_callback(original_callback)
  return function(client, message)
    local request_id = generate_request_id()
    local timestamp = vim.loop.hrtime() / 1000000
    
    -- 解析消息获取方法和ID
    local parsed_message = nil
    local success, result = pcall(vim.json.decode, message)
    if success then
      parsed_message = result
    end
    
    local method = parsed_message and parsed_message.method or "unknown"
    local msg_id = parsed_message and parsed_message.id
    
    -- 记录请求开始
    message_tracking.active_requests[request_id] = {
      client_id = client.id,
      method = method,
      message_id = msg_id,
      start_time = timestamp,
      message_size = #message
    }
    
    message_tracking.total_messages = message_tracking.total_messages + 1
    
    -- 如果是工具调用，更新状态为执行中
    if method == "tools/call" then
      state_manager.set_state(
        state_manager.States.EXECUTING,
        state_manager.OperationTypes.TOOL_CALL,
        {
          client_id = client.id,
          method = method,
          message_id = msg_id,
          request_id = request_id
        }
      )
      
      event_listener.emit(event_listener.Events.EXECUTION_STARTED, {
        client_id = client.id,
        method = method,
        message_id = msg_id,
        request_id = request_id
      })
    else
      -- 其他请求类型
      event_listener.emit(event_listener.Events.REQUEST_STARTED, {
        client_id = client.id,
        method = method,
        message_id = msg_id,
        request_id = request_id
      })
    end
    
    -- 调用原始回调
    if original_callback then
      original_callback(client, message)
    end
    
    -- 记录请求完成（简化处理，实际应该在响应发送后）
    vim.schedule(function()
      local request_info = message_tracking.active_requests[request_id]
      if request_info then
        local duration = vim.loop.hrtime() / 1000000 - request_info.start_time
        
        -- 移到历史记录
        table.insert(message_tracking.request_history, {
          request_id = request_id,
          client_id = client.id,
          method = method,
          message_id = msg_id,
          duration = duration,
          completed_at = vim.loop.hrtime() / 1000000
        })
        
        message_tracking.active_requests[request_id] = nil
        
        -- 限制历史记录长度
        if #message_tracking.request_history > 200 then
          table.remove(message_tracking.request_history, 1)
        end
        
        -- 如果是工具调用完成，更新状态为idle
        if method == "tools/call" then
          state_manager.set_state(
            state_manager.States.IDLE,
            state_manager.OperationTypes.TOOL_CALL,
            {
              client_id = client.id,
              method = method,
              message_id = msg_id,
              request_id = request_id,
              duration = duration,
              reason = "websocket_tool_call_completed"
            }
          )
          
          event_listener.emit(event_listener.Events.EXECUTION_COMPLETED, {
            client_id = client.id,
            method = method,
            message_id = msg_id,
            request_id = request_id,
            duration = duration
          })
        else
          event_listener.emit(event_listener.Events.REQUEST_COMPLETED, {
            client_id = client.id,
            method = method,
            message_id = msg_id,
            request_id = request_id,
            duration = duration
          })
        end
      end
    end)
  end
end

--- 生成请求ID
--- @return string request_id 请求标识符
function generate_request_id() 
  return "req_" .. tostring(vim.loop.hrtime())
end

--- 设置WebSocket监控
--- @param server_mod table 服务器模块引用
--- @return boolean success 是否设置成功
function M.setup(server_mod)
  if monitoring_setup then
    logger.warn("websocket_monitor", "WebSocket monitoring already setup")
    return false
  end
  
  if not server_mod then
    logger.error("websocket_monitor", "Server module reference required")
    return false
  end
  
  server_module = server_mod
  
  -- 重写服务器启动函数以注入监控
  local original_start = server_module.start
  server_module.start = function(config, auth_token)
    -- 调用原始启动函数
    local success, result = original_start(config, auth_token)
    
    if success then
      -- 启动成功后，包装服务器的内部方法
      local original_handle_message = server_module._handle_message
      if original_handle_message then
        server_module._handle_message = function(client, message)
          -- 在处理消息前记录连接状态
          if client and client.id and not connection_tracking.active_connections[client.id] then
            -- 发现新的客户端连接
            local client_info = get_connection_info(client)
            connection_tracking.active_connections[client.id] = client_info
            record_activity("connect", client.id, client_info)
            
            -- 更新状态管理器
            state_manager.add_client(client.id, client_info)
            
            -- 触发连接建立事件
            event_listener.emit(event_listener.Events.CONNECTION_ESTABLISHED, {
              client_id = client.id,
              client_info = client_info,
              total_connections = vim.tbl_count(connection_tracking.active_connections)
            })
          end
          
          -- 包装消息处理逻辑
          local wrapped_message_handler = wrap_message_callback(original_handle_message)
          return wrapped_message_handler(client, message)
        end
      end
    end
    
    return success, result
  end
  
  monitoring_setup = true
  return true
end

--- 获取连接统计信息
--- @return table stats 连接统计
function M.get_connection_stats()
  return {
    active_connections = vim.tbl_count(connection_tracking.active_connections),
    connection_details = vim.deepcopy(connection_tracking.active_connections),
    total_connection_events = #connection_tracking.connection_history,
    last_activity = connection_tracking.last_activity,
    connection_history = vim.deepcopy(connection_tracking.connection_history)
  }
end

--- 获取消息处理统计信息
--- @return table stats 消息统计
function M.get_message_stats()
  local active_count = vim.tbl_count(message_tracking.active_requests)
  local completed_count = #message_tracking.request_history
  
  -- 计算平均响应时间
  local total_duration = 0
  local duration_count = 0
  
  for _, request in ipairs(message_tracking.request_history) do
    if request.duration then
      total_duration = total_duration + request.duration
      duration_count = duration_count + 1
    end
  end
  
  local avg_duration = duration_count > 0 and (total_duration / duration_count) or 0
  
  return {
    total_messages = message_tracking.total_messages,
    active_requests = active_count,
    completed_requests = completed_count,
    average_response_time = avg_duration,
    active_request_details = vim.deepcopy(message_tracking.active_requests),
    request_history = vim.deepcopy(message_tracking.request_history)
  }
end

--- 获取监控状态
--- @return table status 监控状态
function M.get_status()
  return {
    monitoring_active = monitoring_setup,
    server_module_loaded = server_module ~= nil,
    connection_stats = M.get_connection_stats(),
    message_stats = M.get_message_stats()
  }
end

--- 重置监控数据
function M.reset()
  connection_tracking = {
    active_connections = {},
    connection_history = {},
    last_activity = 0
  }
  
  message_tracking = {
    active_requests = {},
    request_history = {},
    total_messages = 0
  }
end

--- 健康检查
--- @return boolean healthy 是否健康
--- @return string|nil issue 问题描述
function M.health_check()
  if not monitoring_setup then
    return false, "监控未设置"
  end
  
  if not server_module then
    return false, "服务器模块引用丢失"
  end
  
  local now = vim.loop.hrtime() / 1000000
  local last_activity_age = now - connection_tracking.last_activity
  
  -- 检查是否有长时间未活动的连接
  if vim.tbl_count(connection_tracking.active_connections) > 0 and last_activity_age > 300000 then -- 5分钟
    return false, "连接长时间无活动 (>5min)"
  end
  
  -- 检查是否有卡住的请求
  local stuck_requests = 0
  for _, request in pairs(message_tracking.active_requests) do
    local request_age = now - request.start_time
    if request_age > 30000 then -- 30秒
      stuck_requests = stuck_requests + 1
    end
  end
  
  if stuck_requests > 0 then
    return false, string.format("有 %d 个请求处理时间过长 (>30s)", stuck_requests)
  end
  
  return true
end

return M