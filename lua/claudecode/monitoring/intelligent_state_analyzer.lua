--- Claude Code 智能状态分析器
-- 通过分析终端缓冲区内容和后台交互状态来判断真实的执行状态
-- @module claudecode.monitoring.intelligent_state_analyzer

local logger = require("claudecode.logger")
local state_manager = require("claudecode.monitoring.state_manager")
local event_listener = require("claudecode.monitoring.event_listener")
local notification = require("claudecode.utils.notification")

local M = {}

-- DEBUG: 添加唯一实例ID
local instance_id = string.format("MODIFIED_%d_%d", os.time(), math.random(1000, 9999))

--- 分析器状态
local analyzer_state = {
  enabled = false,
  timer = nil,
  -- 添加启动计数器来跟踪重复启动
  start_count = 0,
  
  -- 可配置的检查参数
  check_interval = 4000,       -- 检查间隔时间（毫秒）
  executing_timeout = 10000,   -- 执行状态超时时间（毫秒）
  lines_to_check = 30,         -- 检查末尾行数
  
  -- 可配置的状态确认阈值
  idle_confirmation_threshold = 3,     -- idle状态确认次数（连续无变化N次确认为idle）
  executing_confirmation_threshold = 1, -- executing状态确认次数（检测到N次确认为executing）
  disconnected_confirmation_threshold = 2, -- disconnected状态确认次数
  waiting_confirmation_threshold = 1,   -- waiting状态确认次数
  
  -- 运行时状态
  last_analysis = 0,
  last_terminal_content = "",
  consecutive_idle_checks = 0,
  last_tool_call_time = 0,
  last_executing_detected = 0, -- 最后一次检测到执行状态的时间
  
  -- 动态检测相关状态
  last_terminal_hash = "",     -- 上次终端内容的哈希值
  no_change_count = 0,         -- 连续无变化的检测次数
  
  -- 状态确认计数器
  state_counters = {
    idle = 0,
    executing = 0,
    disconnected = 0,
    waiting = 0
  }
}

--- 终端状态关键词模式
local TERMINAL_PATTERNS = {
  -- 正在执行的模式
  executing = {
    "\\d+s.*tokens",      -- 显示时间和token数
    "esc to interrupt",   -- 可中断状态（正在执行）- 这是最重要的执行标识
    "↓.*tokens",          -- 下载token显示
    "↑.*tokens",          -- 上传token显示
    "⚒.*tokens",          -- 工具调用token显示
    "\\d+s.*·.*tokens.*esc to interrupt", -- 完整格式：时间·token数·esc to interrupt
    "·.*esc to interrupt", -- 任何包含 esc to interrupt 的格式
  },
  
  -- 空闲状态模式（简化：不依赖动态检测）
  idle = {
    -- 空闲状态现在主要通过其他状态的排除来确定
  },
  
  -- 断开连接模式
  disconnected = {
    "◯ IDE disconnected", -- IDE断开连接标识（最明确的断开标识）
    "IDE disconnected",   -- 简单文本版本
  },
  
  -- 用户中断模式
  interrupted = {
    -- 这个模式需要特殊处理，通过check_user_interrupted函数检测
    "user_interrupted_combined_pattern", -- 占位符，实际检测在专门函数中
  }
}

--- 计算字符串简单哈希值
--- @param str string 输入字符串
--- @return string hash 哈希值
local function simple_hash(str)
  if not str or str == "" then
    return "empty"
  end
  local hash = 0
  for i = 1, #str do
    hash = (hash * 31 + string.byte(str, i)) % 2147483647
  end
  return tostring(hash)
end


--- 检测终端内容是否有变化
--- @param content string 当前终端内容
--- @return boolean has_changed 是否有变化
local function check_terminal_change(content)
  local current_hash = simple_hash(content)
  local has_changed = current_hash ~= analyzer_state.last_terminal_hash
  
  if has_changed then
    analyzer_state.no_change_count = 0
    analyzer_state.last_terminal_hash = current_hash
    return true
  else
    analyzer_state.no_change_count = analyzer_state.no_change_count + 1
    return false
  end
end


--- 获取终端缓冲区内容
--- @return string content 终端内容
--- @return boolean found 是否找到终端
local function get_terminal_content()
  local content = ""
  local found = false
  
  -- 查找Claude Code终端缓冲区
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_valid(buf) then
      local buf_type = vim.api.nvim_buf_get_option(buf, 'buftype')
      if buf_type == 'terminal' then
        local buf_name = vim.api.nvim_buf_get_name(buf)
        -- 检查是否是Claude终端
        if buf_name:match("claude") or buf_name:match("Claude") then
          -- 获取所有行
          local all_lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
          
          -- 从后向前找有内容的行，跳过空行
          local meaningful_lines = {}
          for i = #all_lines, 1, -1 do
            local line = all_lines[i]
            -- 如果行不为空（去除空白字符后有内容）
            if line and line:match("%S") then
              table.insert(meaningful_lines, 1, line)  -- 插入到开头保持顺序
              -- 如果已经收集够了指定行数就停止
              if #meaningful_lines >= analyzer_state.lines_to_check then
                break
              end
            elseif #meaningful_lines > 0 then
              -- 如果已经开始收集有意义的行，空行也要包含（保持格式）
              table.insert(meaningful_lines, 1, line)
            end
            
            -- 防止检查过多行（最多检查100行来找有内容的行）
            if #all_lines - i + 1 > 100 then
              break
            end
          end
          
          content = table.concat(meaningful_lines, "\n")
          found = true
          break
        end
      end
    end
  end
  
  return content, found
end

--- 检测断开连接状态
--- @param content string 终端内容
--- @return boolean is_disconnected 是否断开连接
--- @return string|nil reason 断开原因
local function check_disconnected(content)
  for _, pattern in ipairs(TERMINAL_PATTERNS.disconnected) do
    if content:match(pattern) then
      return true, "terminal_pattern_disconnected:" .. pattern
    end
  end
  return false, nil
end

--- 检测执行状态
--- @param content string 终端内容
--- @return boolean is_executing 是否正在执行
--- @return string|nil reason 执行原因
local function check_executing(content)
  -- 检查"esc to interrupt"模式 - 最可靠的执行状态标识
  if content:match("esc to interrupt") then
    return true, "terminal_pattern_executing:esc_to_interrupt"
  end
  
  -- 检查其他执行中模式
  for _, pattern in ipairs(TERMINAL_PATTERNS.executing) do
    if pattern ~= "esc to interrupt" and content:match(pattern) then
      return true, "terminal_pattern_executing:" .. pattern
    end
  end
  
  return false, nil
end

--- 检测用户中断标识（简化版）
--- @param content string 终端内容
--- @return boolean is_interrupted 是否包含中断标识
local function check_interrupted_in_recent_lines(content)
  if not content or content == "" then
    return false
  end
  
  -- 获取所有行
  local lines = vim.split(content, "\n")
  
  -- 检查最后有字符的10行中是否包含中断标识
  local checked_lines = 0
  local max_lines_to_check = 10
  
  for i = #lines, 1, -1 do
    local line = lines[i]
    if line and line:match("%S") then -- 有字符的行
      checked_lines = checked_lines + 1
      
      -- 检查是否包含中断标识（支持不间断空格和普通空格）
      if line:match("⎿[%s\194\160]*Interrupted by user") then
        return true
      end
      
      -- 只检查最后10行有字符的行
      if checked_lines >= max_lines_to_check then
        break
      end
    end
  end
  
  return false
end

--- 检测空闲状态（包含中断后的空闲）
--- @param content string 终端内容
--- @param no_change_count number 无变化次数
--- @param threshold number 阈值
--- @return boolean is_idle 是否空闲
--- @return string|nil reason 空闲原因
local function check_idle(content, no_change_count)
  -- 先判断是否idle（基于内容稳定性）
  if no_change_count >= analyzer_state.idle_confirmation_threshold then
    -- 如果是idle，再检查最后有字符的10行中是否包含中断标识
    if check_interrupted_in_recent_lines(content) then
      return true, "idle_interrupted_type"
    else
      return true, string.format("idle_stable_for_%d_checks", no_change_count)
    end
  end
  
  return false, nil
end

--- 分析终端内容状态（重新设计的优先级逻辑）
--- @param content string 终端内容
--- @return string state 推断的状态
--- @return string reason 判断理由
local function analyze_terminal_content(content)
  if not content or content == "" then
    return "disconnected", "no_terminal_content"
  end
  
  -- 检查终端内容变化
  local has_changed = check_terminal_change(content)
  
  -- 优先级1：disconnected检测（横切所有状态）
  local is_disconnected, disconnect_reason = check_disconnected(content)
  if is_disconnected then
    return "disconnected", disconnect_reason
  end
  
  -- 优先级2：executing检测（明确的执行状态）
  local is_executing, exec_reason = check_executing(content)
  if is_executing then
    return "executing", exec_reason
  end
  
  -- 优先级3：idle检测（包含interrupted情况，基于内容稳定性）
  local is_idle, idle_reason = check_idle(content, analyzer_state.no_change_count)
  if is_idle then
    return "idle", idle_reason
  end
  
  -- 调试：显示为什么没有匹配到任何明确状态
  
  -- 优先级4：等待稳定状态
  return "waiting", string.format("content_changing_count_%d", analyzer_state.no_change_count)
end

--- 获取后台交互状态信息
--- @return table interaction_info 交互信息
local function get_backend_interaction_info()
  local now = vim.loop.hrtime() / 1000000
  local state_info = state_manager.get_state_info()
  local metrics = state_manager.get_metrics()
  
  return {
    current_state = state_manager.get_current_state(),
    last_state_change = state_info.last_changed or 0,
    time_since_last_change = now - (state_info.last_changed or 0),
    last_tool_call = metrics.last_execution_start or 0,
    time_since_last_tool_call = now - (metrics.last_execution_start or 0),
    client_count = state_info.client_count or 0,
    recent_activity = (now - (metrics.last_execution_start or 0)) < 10000 -- 10秒内有活动
  }
end

--- 综合分析真实状态 - 重新设计的优先级逻辑
--- @param terminal_content string 终端内容
--- @param backend_info table 后台信息
--- @return string real_state 真实状态
--- @return string analysis_reason 分析理由
local function analyze_real_state(terminal_content, backend_info)
  local terminal_state, terminal_reason = analyze_terminal_content(terminal_content)
  local current_monitoring_state = backend_info.current_state
  local now = vim.loop.hrtime() / 1000000
  
  -- 新的优先级逻辑：直接使用terminal状态分析结果
  
  -- 优先级1：disconnected（横切状态，最高优先级）
  if terminal_state == "disconnected" then
    return "disconnected", terminal_reason
  end
  
  -- 优先级2：executing（明确的执行状态）
  if terminal_state == "executing" then
    return "executing", terminal_reason
  end
  
  -- 优先级3：idle（包含中断后的idle，基于内容稳定性）
  if terminal_state == "idle" then
    return "idle", terminal_reason
  end
  
  -- 优先级4：waiting（内容还在变化，等待稳定）
  if terminal_state == "waiting" then
    -- 保持当前状态直到内容稳定
    return current_monitoring_state, terminal_reason
  end
  
  -- 兜底：如果都不匹配，返回unknown状态
  logger.warn("intelligent_analyzer", string.format(
    "Unexpected terminal state: %s, reason: %s", terminal_state, terminal_reason
  ))
  return "unknown", terminal_reason
end

--- 执行智能状态分析
local function perform_intelligent_analysis()
  local now = vim.loop.hrtime() / 1000000
  
  -- 获取终端内容
  local terminal_content, terminal_found = get_terminal_content()
  if not terminal_found then
    return
  end
  
  -- 获取后台交互信息
  local backend_info = get_backend_interaction_info()
  
  -- 执行综合分析
  local real_state, analysis_reason = analyze_real_state(terminal_content, backend_info)
  local current_state = state_manager.get_current_state()
  
  -- 如果分析出的真实状态与当前状态不同，进行调整
  
  if real_state ~= current_state then
    
    -- 根据真实状态调整监控系统状态
    
    if real_state == "executing" and current_state ~= "executing" then
      state_manager.set_state(
        state_manager.States.EXECUTING,
        "intelligent_analysis",
        {
          analysis_reason = analysis_reason,
          correction_time = now,
          previous_state = current_state
        }
      )
    elseif real_state == "idle" and current_state == "disconnected" then
      -- 从断开连接转为空闲状态
      -- 先转为已连接状态（如果需要的话）
      -- 直接设置为 idle 状态
      local success = state_manager.set_state(
        state_manager.States.IDLE,
        "intelligent_analysis",
        {
          analysis_reason = analysis_reason,
          correction_time = now,
          previous_state = current_state,
          no_change_count = analyzer_state.no_change_count
        }
      )
    elseif real_state == "idle" and current_state == "executing" then
      -- 从执行中直接转为空闲
      state_manager.set_state(
        state_manager.States.IDLE,
        "intelligent_analysis",
        { analysis_reason = analysis_reason }
      )
      
      -- 检查是否需要发送任务完成通知
      -- 只有在不是中断情况下才发送通知
      if analysis_reason and not analysis_reason:match("interrupted") then
        
        -- 发送任务完成通知
        notification.send_task_completion_notification({
          message = "Claude Code 任务已完成",
          include_project = true
        })
      end
    elseif real_state == "interrupted" and current_state ~= "interrupted" then
      -- 检测到用户中断状态
      state_manager.set_state(
        state_manager.States.INTERRUPTED,  -- 独立的中断状态
        "intelligent_analysis",
        {
          analysis_reason = analysis_reason,
          interruption_time = now,
          previous_state = current_state,
          interrupt_type = "user_interrupted"
        }
      )
    elseif real_state == "disconnected" and current_state ~= "disconnected" then
      -- 检测到断开连接状态
      state_manager.set_state(
        state_manager.States.DISCONNECTED,
        "intelligent_analysis",
        {
          analysis_reason = analysis_reason,
          detection_time = now,
          previous_state = current_state
        }
      )
    -- 移除了completed状态，不再需要此分支
    end
    
    -- 发送智能分析事件
    event_listener.emit("intelligent_state_correction", {
      from_state = current_state,
      to_state = real_state,
      analysis_reason = analysis_reason,
      terminal_content_preview = terminal_content:sub(1, 200),
      backend_info = backend_info
    })
  end
  
  analyzer_state.last_analysis = now
  analyzer_state.last_terminal_content = terminal_content
end

--- 启动智能状态分析器
--- @param config table|nil 配置选项
function M.start(config)
  analyzer_state.start_count = analyzer_state.start_count + 1
  if analyzer_state.enabled then
    logger.warn("intelligent_analyzer", string.format(
      "Intelligent state analyzer already running [ID=%s] - start_count=%d", 
      instance_id, analyzer_state.start_count
    ))
    return false
  end
  
  -- 强制清理任何遗留的timer
  if analyzer_state.timer then
    logger.warn("intelligent_analyzer", "Found existing timer, cleaning up before start")
    analyzer_state.timer:stop()
    analyzer_state.timer:close()
    analyzer_state.timer = nil
  end
  
  config = config or {}
  
  -- 基本检查参数配置
  analyzer_state.check_interval = config.check_interval or 4000
  analyzer_state.executing_timeout = config.executing_timeout or 10000
  analyzer_state.lines_to_check = config.lines_to_check or 30
  
  -- 状态确认阈值配置
  analyzer_state.idle_confirmation_threshold = config.idle_confirmation_threshold or 3
  analyzer_state.executing_confirmation_threshold = config.executing_confirmation_threshold or 1
  analyzer_state.disconnected_confirmation_threshold = config.disconnected_confirmation_threshold or 2
  analyzer_state.waiting_confirmation_threshold = config.waiting_confirmation_threshold or 1
  
  -- 重置状态
  local now = vim.loop.hrtime() / 1000000
  analyzer_state.last_analysis = 0
  analyzer_state.last_executing_detected = now -- 初始化为当前时间
  analyzer_state.consecutive_idle_checks = 0
  analyzer_state.no_change_count = 0
  analyzer_state.last_terminal_hash = ""
  
  -- 重置状态确认计数器
  analyzer_state.state_counters = {
    idle = 0,
    executing = 0,
    disconnected = 0,
    waiting = 0
  }
  
  -- 创建定时器
  analyzer_state.timer = vim.loop.new_timer()
  analyzer_state.timer:start(1000, analyzer_state.check_interval, vim.schedule_wrap(function()
    local success, error_msg = pcall(perform_intelligent_analysis)
    if not success then
      logger.error("intelligent_analyzer", "Analysis error: " .. tostring(error_msg))
    end
  end))
  
  analyzer_state.enabled = true
  
  return true
end

--- 停止智能状态分析器
function M.stop()
  -- 停止分析器
  if not analyzer_state.enabled then
    return false
  end
  
  if analyzer_state.timer then
    logger.warn("intelligent_analyzer", "Cleaning up timer during stop")
    analyzer_state.timer:stop()
    analyzer_state.timer:close()
    analyzer_state.timer = nil
  else
    logger.warn("intelligent_analyzer", "No timer to clean up during stop")
  end
  
  analyzer_state.enabled = false
  
  return true
end

--- 获取分析器状态
--- @return table status 分析器状态
function M.get_status()
  return {
    enabled = analyzer_state.enabled,
    check_interval = analyzer_state.check_interval,
    last_analysis = analyzer_state.last_analysis,
    uptime = analyzer_state.enabled and 
      (vim.loop.hrtime() / 1000000 - analyzer_state.last_analysis) or 0
  }
end

--- 手动触发一次分析
function M.analyze_now()
  if not analyzer_state.enabled then
    logger.warn("intelligent_analyzer", "Analyzer not running, cannot perform manual analysis")
    return false
  end
  
  local success, error_msg = pcall(perform_intelligent_analysis)
  if not success then
    logger.error("intelligent_analyzer", "Manual analysis error: " .. tostring(error_msg))
    return false
  end
  
  return true
end

return M
