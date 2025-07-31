--- Flicker detection module that quantitatively measures terminal flicker
-- Provides objective metrics for mode change frequency, redraw events, and flicker patterns
local M = {}

local logger = require("claudecode.logger")
local anti_flicker = require("claudecode.anti_flicker")

-- Detection state
local detection_active = false
local flicker_events = {}
local mode_history = {}
local redraw_history = {}
local detection_start_time = nil

-- Detection thresholds (balanced values with multi-layer validation)
local thresholds = {
  rapid_mode_changes = 6,     -- Mode changes per second indicating flicker (平衡精度)
  excessive_redraws = 12,     -- Redraws per second indicating flicker (平衡精度)
  flicker_window = 1.5,       -- Time window in seconds for flicker detection (适中窗口)
  history_limit = 100,        -- Maximum events to keep in history
  debounce_interval = 30,     -- Milliseconds to debounce cursor events (减少去抖动延迟)
  
  -- 精确的闪烁模式检测参数
  terminal_mode_sequence_threshold = 2,  -- n→nt→t 序列在短时间内出现次数 (降低)
  window_event_burst_threshold = 6,      -- 短时间内连续窗口事件数量 (提高)
  burst_time_window = 0.3,              -- 突发事件检测窗口（300ms，缩短）
}

-- Last event timestamps for debouncing
local last_cursor_move = 0
local last_mode_change = 0

--- Start flicker detection with optional custom thresholds
--- @param custom_thresholds table|nil Optional custom detection thresholds
function M.start_detection(custom_thresholds)
  if detection_active then
    logger.debug("flicker_detector", "Flicker detection already active")
    return
  end
  
  -- Apply custom thresholds if provided
  if custom_thresholds then
    thresholds = vim.tbl_deep_extend("force", thresholds, custom_thresholds)
  end
  
  -- Reset detection state
  flicker_events = {}
  mode_history = {}
  redraw_history = {}
  detection_start_time = vim.loop.hrtime() / 1e9 -- Convert to seconds
  detection_active = true
  
  -- Set up event listeners
  M.setup_event_listeners()
  
  logger.info("flicker_detector", "Started flicker detection with thresholds:", thresholds)
end

--- Stop flicker detection and return final report
--- @return table Final flicker detection report
function M.stop_detection()
  if not detection_active then
    logger.debug("flicker_detector", "Flicker detection not active")
    return M.get_empty_report()
  end
  
  detection_active = false
  
  -- Clean up event listeners
  M.cleanup_event_listeners()
  
  local final_report = M.get_flicker_report()
  logger.info("flicker_detector", "Stopped flicker detection. Final report:", final_report.summary)
  
  return final_report
end

--- Check if flicker detection is currently active
--- @return boolean True if detection is active
function M.is_detection_active()
  return detection_active
end

--- Set up event listeners for flicker detection
function M.setup_event_listeners()
  -- Mode change detection (most critical for flicker detection)
  vim.api.nvim_create_augroup("FlickerDetection", { clear = true })
  
  vim.api.nvim_create_autocmd("ModeChanged", {
    group = "FlickerDetection",
    callback = function(args)
      M.on_mode_changed(args.match)
    end,
  })
  
  -- Redraw event detection
  vim.api.nvim_create_autocmd("VimResized", {
    group = "FlickerDetection", 
    callback = function()
      M.on_redraw_event("VimResized")
    end,
  })
  
  -- Cursor movement (debounced to avoid noise)
  vim.api.nvim_create_autocmd("CursorMoved", {
    group = "FlickerDetection",
    callback = function()
      local now = vim.loop.hrtime() / 1e6 -- Convert to milliseconds
      if now - last_cursor_move > thresholds.debounce_interval then
        M.on_cursor_moved()
        last_cursor_move = now
      end
    end,
  })
  
  -- Window events that can trigger flicker
  vim.api.nvim_create_autocmd({"WinEnter", "WinLeave", "BufEnter", "BufLeave"}, {
    group = "FlickerDetection",
    callback = function(args)
      M.on_window_event(args.event)
    end,
  })
end

--- Clean up event listeners
function M.cleanup_event_listeners()
  pcall(vim.api.nvim_del_augroup_by_name, "FlickerDetection")
end

--- Handle mode change events
--- @param mode_transition string The mode transition pattern (e.g., "n:nt")
function M.on_mode_changed(mode_transition)
  if not detection_active then return end
  
  local now = vim.loop.hrtime() / 1e9
  local event = {
    type = "mode_change",
    timestamp = now,
    transition = mode_transition,
    from_mode = vim.fn.mode(),
  }
  
  -- Debounce rapid mode changes
  if now - last_mode_change < (thresholds.debounce_interval / 1000) then
    return
  end
  last_mode_change = now
  
  table.insert(mode_history, event)
  M.trim_history(mode_history)
  
  -- Analyze for flicker pattern
  local is_flicker = M.analyze_mode_flicker()
  if is_flicker then
    M.record_flicker_event("rapid_mode_changes", event)
  end
  
  logger.trace("flicker_detector", "Mode changed:", mode_transition, "Flicker:", is_flicker)
end

--- Handle redraw events
--- @param event_type string Type of redraw event
function M.on_redraw_event(event_type)
  if not detection_active then return end
  
  local now = vim.loop.hrtime() / 1e9
  local event = {
    type = "redraw",
    timestamp = now,
    event_type = event_type,
  }
  
  table.insert(redraw_history, event)
  M.trim_history(redraw_history)
  
  -- Analyze for excessive redraws
  local is_excessive = M.analyze_redraw_frequency()
  if is_excessive then
    M.record_flicker_event("excessive_redraws", event)
  end
  
  logger.trace("flicker_detector", "Redraw event:", event_type, "Excessive:", is_excessive)
end

--- Handle cursor movement events (debounced)
function M.on_cursor_moved()
  if not detection_active then return end
  
  local now = vim.loop.hrtime() / 1e9
  local event = {
    type = "cursor_move",
    timestamp = now,
  }
  
  -- Light tracking for cursor movement patterns
  table.insert(redraw_history, event)
  M.trim_history(redraw_history)
end

--- Handle window-related events
--- @param event_type string Type of window event
function M.on_window_event(event_type)
  if not detection_active then return end
  
  local now = vim.loop.hrtime() / 1e9
  local event = {
    type = "window_event",
    timestamp = now,
    event_type = event_type,
  }
  
  table.insert(redraw_history, event)
  M.trim_history(redraw_history)
  
  logger.trace("flicker_detector", "Window event:", event_type)
end

--- Analyze mode changes for flicker patterns with enhanced validation
--- @return boolean True if flicker pattern detected
function M.analyze_mode_flicker()
  if not detection_active or #mode_history < 2 then return false end
  
  local now = vim.loop.hrtime() / 1e9
  local anti_flicker_active = anti_flicker.is_active()
  
  -- 1. 检查传统的频率阈值（但需要anti-flicker验证）
  local recent_changes = 0
  for i = #mode_history, 1, -1 do
    local event = mode_history[i]
    if now - event.timestamp > thresholds.flicker_window then
      break
    end
    recent_changes = recent_changes + 1
  end
  
  local changes_per_second = recent_changes / thresholds.flicker_window
  
  -- 高频率模式变化需要anti-flicker系统同时激活才确认为闪烁
  if changes_per_second > thresholds.rapid_mode_changes then
    if anti_flicker_active then
      logger.debug("flicker_detector", "High-confidence rapid mode changes detected (anti-flicker active)")
      return true
    else
      logger.trace("flicker_detector", "Possible rapid mode changes, but no anti-flicker activation - likely false positive")
    end
  end
  
  -- 2. 检查特定的终端闪烁模式序列
  if M.detect_terminal_flicker_sequence() then
    return true
  end
  
  -- 3. 检查突发模式变化（短时间内的快速变化）
  if M.detect_burst_mode_changes() then
    return true
  end
  
  -- 4. 检查terminal初始化闪烁（特定的连续事件模式）
  if M.detect_terminal_initialization_flicker() then
    return true
  end
  
  return false
end

--- 检测终端模式切换的闪烁序列 (n → nt → t 或类似模式)
--- @return boolean True if terminal flicker sequence detected
function M.detect_terminal_flicker_sequence()
  if #mode_history < 3 then return false end
  
  local now = vim.loop.hrtime() / 1e9
  local terminal_sequences = 0
  
  -- 查看最近的模式变化，寻找 n→nt→t 或 nt→n→nt 等闪烁序列
  for i = #mode_history - 2, 1, -1 do
    local event1 = mode_history[i]
    local event2 = mode_history[i + 1]
    local event3 = mode_history[i + 2]
    
    -- 只检查最近500ms内的事件
    if now - event1.timestamp > thresholds.burst_time_window then
      break
    end
    
    -- 检测典型的终端闪烁序列
    local transitions = {
      event1.transition or "",
      event2.transition or "",
      event3.transition or "",
    }
    
    -- 常见的闪烁模式
    local flicker_patterns = {
      {"n:nt", "nt:t", "t:nt"},  -- 进入终端时的闪烁
      {"nt:n", "n:nt", "nt:t"},  -- 来回切换闪烁
      {"t:nt", "nt:n", "n:nt"},  -- 退出再进入闪烁
    }
    
    for _, pattern in ipairs(flicker_patterns) do
      if transitions[1] == pattern[1] and transitions[2] == pattern[2] and transitions[3] == pattern[3] then
        terminal_sequences = terminal_sequences + 1
        break
      end
    end
  end
  
  return terminal_sequences >= thresholds.terminal_mode_sequence_threshold
end

--- 检测突发模式变化（短时间内的快速连续变化）
--- @return boolean True if burst mode changes detected
function M.detect_burst_mode_changes()
  if #mode_history < 3 then return false end
  
  local now = vim.loop.hrtime() / 1e9
  local burst_changes = 0
  local anti_flicker_active = anti_flicker.is_active()
  
  -- 检查突发时间窗口内的变化
  for i = #mode_history, 1, -1 do
    local event = mode_history[i]
    if now - event.timestamp > thresholds.burst_time_window then
      break
    end
    burst_changes = burst_changes + 1
  end
  
  -- 突发模式变化需要anti-flicker同时激活才确认（避免误判）
  local has_burst = burst_changes >= 3
  if has_burst and anti_flicker_active then
    logger.debug("flicker_detector", "Burst mode changes with anti-flicker validation:", burst_changes, "changes")
    return true
  elseif has_burst then
    logger.trace("flicker_detector", "Possible burst changes without anti-flicker - may be normal terminal activity")
  end
  
  return false
end

--- 检测terminal初始化闪烁（基于更精确的模式分析和anti-flicker状态验证）
--- @return boolean True if terminal initialization flicker detected  
function M.detect_terminal_initialization_flicker()
  if #redraw_history < 4 then return false end  -- 降低基础阈值，依赖更多条件
  
  local now = vim.loop.hrtime() / 1e9
  local recent_window_events = {}
  local recent_mode_changes = {}
  
  -- 收集最近200ms内的窗口事件（扩大时间窗口捕获更多模式）
  for i = #redraw_history, 1, -1 do
    local event = redraw_history[i]
    if now - event.timestamp > 0.2 then -- 200ms内
      break
    end
    if event.type == "window_event" then
      table.insert(recent_window_events, event)
    end
  end
  
  -- 收集最近200ms内的模式变化
  for i = #mode_history, 1, -1 do
    local event = mode_history[i] 
    if now - event.timestamp > 0.2 then -- 200ms内
      break
    end
    table.insert(recent_mode_changes, event)
  end
  
  -- 多层验证的闪烁检测条件：
  -- 1. 基础条件：窗口事件数量（降低到6个）
  -- 2. 模式条件：终端模式变化（n:nt 或相关转换）
  -- 3. 模式条件：重复模式检测
  -- 4. 验证条件：Anti-flicker系统激活状态
  -- 5. 时序条件：事件在短时间内集中出现
  
  local has_sufficient_window_events = #recent_window_events >= 6  -- 适中的窗口事件阈值
  local has_terminal_mode_change = false
  local has_repetitive_pattern = false
  local anti_flicker_active = anti_flicker.is_active()  -- 获取anti-flicker状态
  
  -- 检查终端相关的模式变化
  for _, mode_event in ipairs(recent_mode_changes) do
    local transition = mode_event.transition or ""
    if transition == "n:nt" or transition == "nt:t" or transition:find("nt") then
      has_terminal_mode_change = true
      break
    end
  end
  
  -- 更智能的重复模式检测
  if #recent_window_events >= 4 then
    local event_counts = {}
    local event_pairs = {}
    
    -- 统计事件类型
    for _, event in ipairs(recent_window_events) do
      event_counts[event.event_type] = (event_counts[event.event_type] or 0) + 1
    end
    
    -- 检查成对的进入/离开事件（闪烁的典型特征）
    event_pairs.win_pairs = math.min(event_counts.WinEnter or 0, event_counts.WinLeave or 0)
    event_pairs.buf_pairs = math.min(event_counts.BufEnter or 0, event_counts.BufLeave or 0)
    
    -- 闪烁特征：至少有2对进入/离开事件，或者大量单一类型事件
    has_repetitive_pattern = event_pairs.win_pairs >= 2 or 
                            event_pairs.buf_pairs >= 2 or
                            (event_counts.WinEnter or 0) >= 4
  end
  
  -- 时序集中度检测：事件是否在很短时间内集中发生
  local has_concentrated_timing = false
  if #recent_window_events >= 4 then
    local timestamps = {}
    for _, event in ipairs(recent_window_events) do
      table.insert(timestamps, event.timestamp)
    end
    table.sort(timestamps)
    
    -- 检查是否有50%以上的事件在50ms内发生
    local quick_events = 0
    local base_time = timestamps[1]
    for _, timestamp in ipairs(timestamps) do
      if timestamp - base_time <= 0.05 then  -- 50ms内
        quick_events = quick_events + 1
      end
    end
    has_concentrated_timing = quick_events >= math.ceil(#timestamps * 0.5)
  end
  
  -- 多条件综合判断（更严格的条件组合）
  local conditions_met = 0
  local total_conditions = 4  -- 减少到4个条件，去除anti_flicker_active
  
  if has_sufficient_window_events then conditions_met = conditions_met + 1 end
  if has_terminal_mode_change then conditions_met = conditions_met + 1 end
  if has_repetitive_pattern then conditions_met = conditions_met + 1 end
  if has_concentrated_timing then conditions_met = conditions_met + 1 end
  
  -- 需要满足至少3/4个条件才认为是真正的闪烁
  -- 但如果anti-flicker已经激活，说明系统正在处理，不应该报告为flicker
  local is_likely_flicker = (conditions_met >= 3) and not anti_flicker_active
  
  -- 详细日志记录用于调试
  if has_sufficient_window_events then
    logger.debug("flicker_detector", "Flicker analysis:", 
      string.format("WindowEvents=%d, ModeChange=%s, Repetitive=%s, AntiFlicker=%s, Concentrated=%s, Score=%d/4",
        #recent_window_events, 
        tostring(has_terminal_mode_change),
        tostring(has_repetitive_pattern),
        tostring(anti_flicker_active),
        tostring(has_concentrated_timing),
        conditions_met))
    
    if is_likely_flicker then
      logger.info("flicker_detector", "High-confidence flicker detected with comprehensive validation")
      return true
    else
      logger.trace("flicker_detector", "Likely normal terminal operation - insufficient flicker evidence")
    end
  end
  
  return false
end

--- Analyze redraw frequency for excessive patterns
--- @return boolean True if excessive redraws detected
function M.analyze_redraw_frequency()
  if not detection_active or #redraw_history < 3 then return false end
  
  local now = vim.loop.hrtime() / 1e9
  
  -- 1. 检查传统的重绘频率
  local recent_redraws = 0
  for i = #redraw_history, 1, -1 do
    local event = redraw_history[i]
    if now - event.timestamp > thresholds.flicker_window then
      break
    end
    recent_redraws = recent_redraws + 1
  end
  
  local redraws_per_second = recent_redraws / thresholds.flicker_window
  if redraws_per_second > thresholds.excessive_redraws then
    return true
  end
  
  -- 2. 检查窗口事件突发（WinEnter/WinLeave 快速连续出现）
  if M.detect_window_event_burst() then
    return true
  end
  
  return false
end

--- 检测窗口事件突发（快速的 WinEnter/WinLeave 序列）
--- @return boolean True if window event burst detected
function M.detect_window_event_burst()
  if #redraw_history < 4 then return false end
  
  local now = vim.loop.hrtime() / 1e9
  local window_events = 0
  local same_second_events = 0
  local anti_flicker_active = anti_flicker.is_active()
  
  -- 检查突发时间窗口内的窗口事件
  for i = #redraw_history, 1, -1 do
    local event = redraw_history[i]
    if now - event.timestamp > thresholds.burst_time_window then
      break
    end
    
    -- 只计算窗口相关事件
    if event.type == "window_event" and 
       (event.event_type == "WinEnter" or event.event_type == "WinLeave" or 
        event.event_type == "BufEnter" or event.event_type == "BufLeave") then
      window_events = window_events + 1
      
      -- 特别检查同一秒内的事件（terminal初始化闪烁的特征）
      if now - event.timestamp < 0.001 then -- 1毫秒内
        same_second_events = same_second_events + 1
      end
    end
  end
  
  -- 如果同一毫秒内有很多窗口事件且anti-flicker激活，这是明显的闪烁
  if same_second_events >= 4 and anti_flicker_active then
    logger.debug("flicker_detector", "High-confidence window event burst with anti-flicker:", same_second_events, "simultaneous events")
    return true
  end
  
  -- 大量窗口事件需要anti-flicker验证
  local has_burst = window_events >= thresholds.window_event_burst_threshold
  if has_burst and anti_flicker_active then
    logger.debug("flicker_detector", "Window event burst validated by anti-flicker:", window_events, "events")
    return true
  elseif has_burst then
    logger.trace("flicker_detector", "Window event burst without anti-flicker activation - likely normal operation")
  end
  
  return false
end

--- Record a flicker event
--- @param flicker_type string Type of flicker detected
--- @param trigger_event table The event that triggered the flicker detection
function M.record_flicker_event(flicker_type, trigger_event)
  local flicker_event = {
    type = flicker_type,
    timestamp = vim.loop.hrtime() / 1e9,
    trigger = trigger_event,
    severity = M.calculate_flicker_severity(flicker_type),
  }
  
  table.insert(flicker_events, flicker_event)
  M.trim_history(flicker_events)
  
  logger.debug("flicker_detector", "Flicker detected:", flicker_type, "Severity:", flicker_event.severity)
end

--- Calculate flicker severity based on type and recent patterns
--- @param flicker_type string Type of flicker
--- @return number Severity score (1-10, higher = more severe)
function M.calculate_flicker_severity(flicker_type)
  local base_severity = {
    rapid_mode_changes = 8,  -- High severity - very disruptive
    excessive_redraws = 6,   -- Medium-high severity
  }
  
  local severity = base_severity[flicker_type] or 5
  
  -- Increase severity based on recent flicker frequency
  local recent_flickers = M.count_recent_flickers(2.0) -- Last 2 seconds
  if recent_flickers > 3 then
    severity = math.min(10, severity + 2)
  elseif recent_flickers > 1 then
    severity = math.min(10, severity + 1)
  end
  
  return severity
end

--- Count recent flicker events in a time window
--- @param time_window number Time window in seconds
--- @return number Count of recent flicker events
function M.count_recent_flickers(time_window)
  local now = vim.loop.hrtime() / 1e9
  local count = 0
  
  for i = #flicker_events, 1, -1 do
    local event = flicker_events[i]
    if now - event.timestamp > time_window then
      break
    end
    count = count + 1
  end
  
  return count
end

--- Trim event history to prevent memory bloat
--- @param history table Event history array to trim
function M.trim_history(history)
  while #history > thresholds.history_limit do
    table.remove(history, 1)
  end
end

--- Generate comprehensive flicker detection report
--- @return table Detailed flicker report
function M.get_flicker_report()
  if not detection_active then
    return M.get_empty_report()
  end
  
  local now = vim.loop.hrtime() / 1e9
  local detection_duration = now - (detection_start_time or now)
  
  -- Calculate metrics
  local total_flickers = #flicker_events
  local total_mode_changes = #mode_history
  local total_redraws = #redraw_history
  
  local avg_flicker_severity = 0
  if total_flickers > 0 then
    local total_severity = 0
    for _, event in ipairs(flicker_events) do
      total_severity = total_severity + event.severity
    end
    avg_flicker_severity = total_severity / total_flickers
  end
  
  -- Recent activity (last 5 seconds)
  local recent_flickers = M.count_recent_flickers(5.0)
  local recent_modes = 0
  local recent_redraws = 0
  
  for _, event in ipairs(mode_history) do
    if now - event.timestamp <= 5.0 then
      recent_modes = recent_modes + 1
    end
  end
  
  for _, event in ipairs(redraw_history) do
    if now - event.timestamp <= 5.0 then
      recent_redraws = recent_redraws + 1
    end
  end
  
  return {
    detection_active = detection_active,
    detection_duration = detection_duration,
    summary = {
      flicker_events = total_flickers,
      mode_changes = total_mode_changes,
      redraw_events = total_redraws,
      avg_severity = math.floor(avg_flicker_severity * 100) / 100,
    },
    recent_activity = {
      flickers_last_5s = recent_flickers,
      modes_last_5s = recent_modes,
      redraws_last_5s = recent_redraws,
    },
    anti_flicker_status = {
      currently_active = anti_flicker.is_active(),
      integration_enabled = true,
    },
    thresholds = thresholds,
    recommendations = M.generate_recommendations(total_flickers, avg_flicker_severity),
  }
end

--- Generate empty report for when detection is not active
--- @return table Empty flicker report
function M.get_empty_report()
  return {
    detection_active = false,
    detection_duration = 0,
    summary = {
      flicker_events = 0,
      mode_changes = 0,
      redraw_events = 0,
      avg_severity = 0,
    },
    recent_activity = {
      flickers_last_5s = 0,
      modes_last_5s = 0,
      redraws_last_5s = 0,
    },
    anti_flicker_status = {
      currently_active = anti_flicker.is_active(),
      integration_enabled = true,
    },
    thresholds = thresholds,
    recommendations = {"Start flicker detection to analyze terminal behavior"},
  }
end

--- Generate intelligent recommendations based on flicker analysis and anti-flicker status
--- @param flicker_count number Total flicker events detected
--- @param avg_severity number Average flicker severity
--- @return table Array of recommendation strings
function M.generate_recommendations(flicker_count, avg_severity)
  local recommendations = {}
  local anti_flicker_active = anti_flicker.is_active()
  
  if flicker_count == 0 then
    if anti_flicker_active then
      table.insert(recommendations, "No flicker detected despite anti-flicker activation - check for other display issues")
    else
      table.insert(recommendations, "No flicker detected - terminal behavior is optimal")
    end
  elseif flicker_count <= 2 then
    if anti_flicker_active then
      table.insert(recommendations, "Minimal validated flicker - anti-flicker system is working effectively")
    else
      table.insert(recommendations, "Minimal flicker detected - may be false positives without anti-flicker validation")
      table.insert(recommendations, "Consider enabling debug logging for further analysis")
    end
  elseif flicker_count <= 5 then
    if anti_flicker_active then
      table.insert(recommendations, "Moderate validated flicker - anti-flicker helps but more optimization needed")
      table.insert(recommendations, "Apply additional terminal display optimizations")
    else
      table.insert(recommendations, "Moderate flicker detected - results may include false positives")
      table.insert(recommendations, "Enable anti-flicker system to improve detection accuracy")
    end
  else
    if anti_flicker_active then
      table.insert(recommendations, "High-confidence significant flicker detected with validation")
      table.insert(recommendations, "Apply comprehensive anti-flicker settings and terminal optimizations")
      table.insert(recommendations, "Consider changing terminal provider or checking system performance")
    else
      table.insert(recommendations, "Possible significant flicker - needs anti-flicker validation for confidence")
      table.insert(recommendations, "Enable anti-flicker system for accurate flicker confirmation")
    end
  end
  
  if avg_severity > 7 then
    table.insert(recommendations, "High severity flicker - check for conflicting plugins or terminal issues")
    if anti_flicker_active then
      table.insert(recommendations, "Consider system-level display settings or hardware acceleration issues")
    end
  end
  
  -- Add detection accuracy recommendations
  if flicker_count > 0 and not anti_flicker_active then
    table.insert(recommendations, "💡 Tip: Anti-flicker validation helps distinguish real flicker from normal terminal activity")
  end
  
  return recommendations
end

--- Get current detection statistics for real-time monitoring
--- @return table Current statistics
function M.get_current_stats()
  if not detection_active then
    return { active = false }
  end
  
  local now = vim.loop.hrtime() / 1e9
  return {
    active = true,
    uptime = now - (detection_start_time or now),
    events = {
      flicker = #flicker_events,
      mode_changes = #mode_history,
      redraws = #redraw_history,
    },
    recent_flickers = M.count_recent_flickers(2.0),
  }
end

return M
