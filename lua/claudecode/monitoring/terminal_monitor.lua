--- 终端进程监控适配器  
-- 监控Claude Code终端进程的生命周期和状态
-- @module claudecode.monitoring.terminal_monitor

local logger = require("claudecode.logger")
local state_manager = require("claudecode.monitoring.state_manager")
local event_listener = require("claudecode.monitoring.event_listener")

local M = {}

--- 是否已设置监控
local monitoring_setup = false

--- 原始终端模块引用
local terminal_module = nil

--- 终端进程跟踪
local process_tracking = {
  active_processes = {},
  process_history = {},
  terminal_instances = {},
  total_processes = 0
}

--- 终端实例信息
--- @class TerminalInstanceInfo
--- @field instance_id string 实例ID
--- @field job_id number|nil 作业ID
--- @field buffer_id number|nil 缓冲区ID
--- @field window_id number|nil 窗口ID
--- @field created_at number 创建时间
--- @field status string 状态 (active, exited, error)
--- @field provider string 终端提供者 (native, snacks)

--- 进程信息
--- @class ProcessInfo
--- @field process_id string 进程ID
--- @field job_id number 作业ID
--- @field instance_id string 终端实例ID
--- @field command string 执行的命令
--- @field start_time number 开始时间
--- @field end_time number|nil 结束时间
--- @field exit_code number|nil 退出码
--- @field duration number|nil 运行时长

--- 生成实例ID
--- @return string instance_id 实例标识符
local function generate_instance_id()
  return "term_" .. tostring(vim.loop.hrtime())
end

--- 生成进程ID
--- @return string process_id 进程标识符
local function generate_process_id()
  return "proc_" .. tostring(vim.loop.hrtime())
end

--- 记录终端实例创建
--- @param instance_info TerminalInstanceInfo 实例信息
local function record_terminal_instance(instance_info)
  process_tracking.terminal_instances[instance_info.instance_id] = instance_info
  
  logger.info("monitoring", string.format(
    "Terminal instance created: %s (provider: %s)",
    instance_info.instance_id, instance_info.provider
  ))
  
  -- 触发事件
  event_listener.emit("terminal_instance_created", {
    instance_id = instance_info.instance_id,
    provider = instance_info.provider,
    created_at = instance_info.created_at
  })
end

--- 记录进程启动
--- @param process_info ProcessInfo 进程信息
local function record_process_start(process_info)
  process_tracking.active_processes[process_info.process_id] = process_info
  process_tracking.total_processes = process_tracking.total_processes + 1
  
  logger.info("monitoring", string.format(
    "Process started: %s (job_id: %d, command: %s)",
    process_info.process_id, process_info.job_id, process_info.command
  ))
  
  -- 触发事件
  event_listener.emit("terminal_process_started", {
    process_id = process_info.process_id,
    job_id = process_info.job_id,
    instance_id = process_info.instance_id,
    command = process_info.command,
    start_time = process_info.start_time
  })
end

--- 记录进程结束
--- @param process_id string 进程ID
--- @param exit_code number 退出码
local function record_process_end(process_id, exit_code)
  local process_info = process_tracking.active_processes[process_id]
  if not process_info then
    logger.warn("terminal_monitor", "Process end recorded for unknown process: " .. process_id)
    return
  end
  
  local end_time = vim.loop.hrtime() / 1000000
  process_info.end_time = end_time
  process_info.exit_code = exit_code
  process_info.duration = end_time - process_info.start_time
  
  -- 移动到历史记录
  table.insert(process_tracking.process_history, vim.deepcopy(process_info))
  process_tracking.active_processes[process_id] = nil
  
  -- 限制历史记录长度
  if #process_tracking.process_history > 100 then
    table.remove(process_tracking.process_history, 1)
  end
  
  -- 更新相关终端实例状态
  local instance_info = process_tracking.terminal_instances[process_info.instance_id]
  if instance_info then
    instance_info.status = exit_code == 0 and "exited" or "error"
  end
  
  logger.info("monitoring", string.format(
    "Process ended: %s (exit_code: %d, duration: %.2fms)",
    process_id, exit_code, process_info.duration
  ))
  
  -- 触发事件
  event_listener.emit(event_listener.Events.TERMINAL_PROCESS_EXITED, {
    process_id = process_id,
    job_id = process_info.job_id,
    instance_id = process_info.instance_id,
    exit_code = exit_code,
    duration = process_info.duration,
    end_time = end_time,
    command = process_info.command
  })
  
  -- 如果是Claude Code进程结束，可能需要更新全局状态
  if process_info.command and string.find(process_info.command, "claude") then
    -- 检查是否还有其他Claude进程在运行
    local has_active_claude = false
    for _, active_process in pairs(process_tracking.active_processes) do
      if active_process.command and string.find(active_process.command, "claude") then
        has_active_claude = true
        break
      end
    end
    
    if not has_active_claude then
      -- 没有活跃的Claude进程，可能需要更新连接状态
      -- 这里可以与WebSocket监控协调
    end
  end
end

--- 包装native终端的termopen调用
--- @param original_termopen function 原始termopen函数
--- @param instance_id string 终端实例ID
--- @return function wrapped_termopen 包装后的函数
local function wrap_native_termopen(original_termopen, instance_id)
  return function(cmd, opts)
    local original_on_exit = opts.on_exit
    local process_id = generate_process_id()
    
    -- 包装退出回调
    opts.on_exit = function(job_id, exit_code, event_type)
      -- 记录进程结束
      record_process_end(process_id, exit_code)
      
      -- 调用原始回调
      if original_on_exit then
        original_on_exit(job_id, exit_code, event_type)
      end
    end
    
    -- 调用原始termopen
    local job_id = original_termopen(cmd, opts)
    
    if job_id > 0 then
      -- 记录进程开始
      record_process_start({
        process_id = process_id,
        job_id = job_id,
        instance_id = instance_id,
        command = type(cmd) == "table" and table.concat(cmd, " ") or cmd,
        start_time = vim.loop.hrtime() / 1000000
      })
    else
      logger.error("terminal_monitor", string.format(
        "Failed to start terminal process: %s (job_id: %d)", 
        tostring(cmd), job_id
      ))
    end
    
    return job_id
  end
end

--- 包装native终端的open函数
--- @param original_open function 原始open函数
--- @return function wrapped_open 包装后的函数
local function wrap_native_open(original_open)
  return function(cmd_string, env_table, effective_config, focus)
    local instance_id = generate_instance_id()
    
    -- 记录终端实例创建
    record_terminal_instance({
      instance_id = instance_id,
      job_id = nil, -- 将在termopen后设置
      buffer_id = nil, -- 将在创建后设置
      window_id = nil, -- 将在创建后设置
      created_at = vim.loop.hrtime() / 1000000,
      status = "active",
      provider = "native"
    })
    
    -- 暂时保存vim.fn.termopen的引用并包装它
    local original_vim_termopen = vim.fn.termopen
    vim.fn.termopen = wrap_native_termopen(original_vim_termopen, instance_id)
    
    -- 调用原始open函数
    local result = original_open(cmd_string, env_table, effective_config, focus)
    
    -- 恢复原始termopen
    vim.fn.termopen = original_vim_termopen
    
    return result
  end
end

--- 包装snacks终端的open函数
--- @param original_open function 原始open函数
--- @return function wrapped_open 包装后的函数
local function wrap_snacks_open(original_open)
  return function(cmd_string, env_table, config, focus)
    local instance_id = generate_instance_id()
    
    -- 记录终端实例创建
    record_terminal_instance({
      instance_id = instance_id,
      job_id = nil,
      buffer_id = nil,
      window_id = nil,
      created_at = vim.loop.hrtime() / 1000000,
      status = "active",
      provider = "snacks"
    })
    
    logger.debug("monitoring", string.format(
      "Terminal instance created: %s (provider: snacks)", instance_id
    ))
    
    -- 调用原始open函数，传递正确的参数
    local result = original_open(cmd_string, env_table, config, focus)
    
    return result
  end
end

--- 设置终端进程监控
--- @param terminal_mod table 终端模块引用
--- @return boolean success 是否设置成功
function M.setup(terminal_mod)
  if monitoring_setup then
    logger.warn("terminal_monitor", "Terminal process monitoring already setup")
    return false
  end
  
  if not terminal_mod then
    logger.error("terminal_monitor", "Terminal module reference required")
    return false
  end
  
  terminal_module = terminal_mod
  
  -- 监控native终端提供者
  local native_provider = require("claudecode.terminal.native")
  if native_provider and native_provider.open then
    local original_native_open = native_provider.open
    native_provider.open = wrap_native_open(original_native_open)
  end
  
  -- 监控snacks终端提供者（如果可用）
  local snacks_available, snacks_provider = pcall(require, "claudecode.terminal.snacks")
  if snacks_available and snacks_provider and snacks_provider.open then
    local original_snacks_open = snacks_provider.open
    snacks_provider.open = wrap_snacks_open(original_snacks_open)
  end
  
  -- 定期检查进程健康状态
  local health_check_timer = vim.loop.new_timer()
  health_check_timer:start(30000, 30000, vim.schedule_wrap(function()
    M.check_process_health()
  end)) -- 每30秒检查一次
  
  monitoring_setup = true
  return true
end

--- 检查进程健康状态
function M.check_process_health()
  local now = vim.loop.hrtime() / 1000000
  local issues = {}
  
  -- 检查长时间运行的进程
  for process_id, process_info in pairs(process_tracking.active_processes) do
    local runtime = now - process_info.start_time
    if runtime > 3600000 then -- 1小时
      table.insert(issues, {
        type = "long_running_process",
        process_id = process_id,
        runtime = runtime,
        message = string.format("进程运行时间过长: %s (%.2f小时)", 
          process_id, runtime / 3600000)
      })
    end
  end
  
  -- 检查僵尸终端实例 (已禁用长时间未活动警告)
  -- 终端可能会长时间保持连接状态，这是正常的，不需要发出警告
  
  -- 如果有问题，记录并触发事件
  if #issues > 0 then
    for _, issue in ipairs(issues) do
      logger.warn("terminal_monitor", issue.message)
    end
    
    event_listener.emit("terminal_health_issues", {
      issues = issues,
      check_time = now
    })
  end
end

--- 获取进程统计信息
--- @return table stats 进程统计
function M.get_process_stats()
  local active_count = vim.tbl_count(process_tracking.active_processes)
  local completed_count = #process_tracking.process_history
  local instance_count = vim.tbl_count(process_tracking.terminal_instances)
  
  -- 计算平均运行时间
  local total_duration = 0
  local duration_count = 0
  
  for _, process in ipairs(process_tracking.process_history) do
    if process.duration then
      total_duration = total_duration + process.duration
      duration_count = duration_count + 1
    end
  end
  
  local avg_duration = duration_count > 0 and (total_duration / duration_count) or 0
  
  return {
    total_processes = process_tracking.total_processes,
    active_processes = active_count,
    completed_processes = completed_count,
    terminal_instances = instance_count,
    average_process_duration = avg_duration,
    active_process_details = vim.deepcopy(process_tracking.active_processes),
    recent_processes = vim.list_slice(process_tracking.process_history, -10)
  }
end

--- 获取终端实例统计信息
--- @return table stats 实例统计
function M.get_instance_stats()
  local active_instances = 0
  local exited_instances = 0
  local error_instances = 0
  
  for _, instance in pairs(process_tracking.terminal_instances) do
    if instance.status == "active" then
      active_instances = active_instances + 1
    elseif instance.status == "exited" then
      exited_instances = exited_instances + 1
    elseif instance.status == "error" then
      error_instances = error_instances + 1
    end
  end
  
  return {
    total_instances = vim.tbl_count(process_tracking.terminal_instances),
    active_instances = active_instances,
    exited_instances = exited_instances,
    error_instances = error_instances,
    instance_details = vim.deepcopy(process_tracking.terminal_instances)
  }
end

--- 获取监控状态
--- @return table status 监控状态
function M.get_status()
  return {
    monitoring_active = monitoring_setup,
    terminal_module_loaded = terminal_module ~= nil,
    process_stats = M.get_process_stats(),
    instance_stats = M.get_instance_stats()
  }
end

--- 强制结束进程
--- @param process_id string 进程ID
--- @return boolean success 是否成功
function M.kill_process(process_id)
  local process_info = process_tracking.active_processes[process_id]
  if not process_info then
    return false
  end
  
  local success = vim.fn.jobstop(process_info.job_id)
  if success == 1 then
    logger.info("monitoring", string.format(
      "Process killed: %s (job_id: %d)", process_id, process_info.job_id
    ))
    return true
  else
    logger.error("terminal_monitor", string.format(
      "Failed to kill process: %s (job_id: %d)", process_id, process_info.job_id
    ))
    return false
  end
end

--- 重置监控数据
function M.reset()
  process_tracking = {
    active_processes = {},
    process_history = {},
    terminal_instances = {},
    total_processes = 0
  }
  
end

--- 健康检查
--- @return boolean healthy 是否健康
--- @return string|nil issue 问题描述
function M.health_check()
  if not monitoring_setup then
    return false, "终端进程监控未设置"
  end
  
  if not terminal_module then
    return false, "终端模块引用丢失"
  end
  
  local now = vim.loop.hrtime() / 1000000
  
  -- 检查是否有太多活跃进程
  local active_count = vim.tbl_count(process_tracking.active_processes)
  if active_count > 10 then
    return false, string.format("活跃进程数量过多: %d", active_count)
  end
  
  -- 检查是否有长时间运行的进程
  for _, process_info in pairs(process_tracking.active_processes) do
    local runtime = now - process_info.start_time
    if runtime > 3600000 then -- 1小时
      return false, string.format("进程运行时间过长: %.2f小时", runtime / 3600000)
    end
  end
  
  return true
end

return M