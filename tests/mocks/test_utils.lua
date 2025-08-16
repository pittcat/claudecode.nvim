--- Test utilities for monitoring system tests
--- @module tests.mocks.test_utils

local M = {}

--- Create a mock monitoring system for testing
--- @return table Mock monitoring system
function M.create_monitoring_mock()
  return {
    state = {
      enabled = false,
      websocket_connected = false,
      terminal_active = false,
      tool_calls = {},
    },
    stats = {
      websocket_messages = 0,
      terminal_commands = 0,
      tool_executions = 0,
      errors = 0,
    },
    history = {},
    analysis = {
      last_run = nil,
      recommendations = {},
    },
    -- Mock methods
    enable = function(self)
      self.state.enabled = true
    end,
    disable = function(self)
      self.state.enabled = false
    end,
    get_status = function(self)
      return self.state
    end,
    get_stats = function(self)
      return self.stats
    end,
    get_history = function(self)
      return self.history
    end,
    analyze = function(self)
      self.analysis.last_run = os.time()
      return self.analysis
    end,
    reset = function(self)
      self.stats = {
        websocket_messages = 0,
        terminal_commands = 0,
        tool_executions = 0,
        errors = 0,
      }
      self.history = {}
    end,
  }
end

--- Create a mock notification system for testing
--- @return table Mock notification system
function M.create_notification_mock()
  return {
    enabled = true,
    last_notification = nil,
    notifications = {},
    send_notification = function(self, title, message, sound)
      local notification = {
        title = title,
        message = message,
        sound = sound,
        timestamp = os.time(),
      }
      self.last_notification = notification
      table.insert(self.notifications, notification)
      return true
    end,
    send_task_completion_notification = function(self, options)
      return self:send_notification(
        "Claude Code",
        options and options.message or "任务已完成",
        options and options.sound
      )
    end,
    clear = function(self)
      self.notifications = {}
      self.last_notification = nil
    end,
    get_count = function(self)
      return #self.notifications
    end,
  }
end

--- Create a mock terminal system for testing
--- @return table Mock terminal system
function M.create_terminal_mock()
  return {
    open_calls = {},
    toggle_calls = {},
    last_command = nil,
    is_open = false,
    open = function(self, cmd, args)
      local command = cmd or "claude"
      if args and args.cmd_args then
        command = command .. " " .. args.cmd_args
      end
      self.last_command = command
      self.is_open = true
      table.insert(self.open_calls, {
        command = command,
        args = args,
        timestamp = os.time(),
      })
    end,
    toggle = function(self, cmd, args)
      local command = cmd or "claude"
      if args and args.cmd_args then
        command = command .. " " .. args.cmd_args
      end
      self.last_command = command
      self.is_open = not self.is_open
      table.insert(self.toggle_calls, {
        command = command,
        args = args,
        timestamp = os.time(),
      })
    end,
    close = function(self)
      self.is_open = false
    end,
    reset = function(self)
      self.open_calls = {}
      self.toggle_calls = {}
      self.last_command = nil
      self.is_open = false
    end,
  }
end

--- Create a mock WebSocket client for testing
--- @return table Mock WebSocket client
function M.create_websocket_mock()
  return {
    connected = false,
    messages_sent = {},
    messages_received = {},
    connect = function(self, url, headers)
      self.connected = true
      return true
    end,
    disconnect = function(self)
      self.connected = false
    end,
    send = function(self, message)
      table.insert(self.messages_sent, {
        message = message,
        timestamp = os.time(),
      })
    end,
    receive = function(self, message)
      table.insert(self.messages_received, {
        message = message,
        timestamp = os.time(),
      })
    end,
    reset = function(self)
      self.messages_sent = {}
      self.messages_received = {}
      self.connected = false
    end,
  }
end

--- Create a comprehensive mock system for claudecode testing
--- @return table Complete mock system
function M.create_full_mock_system()
  return {
    monitoring = M.create_monitoring_mock(),
    notification = M.create_notification_mock(),
    terminal = M.create_terminal_mock(),
    websocket = M.create_websocket_mock(),
    reset_all = function(self)
      self.monitoring:reset()
      self.notification:clear()
      self.terminal:reset()
      self.websocket:reset()
    end,
  }
end

--- Helper to wait for async operations in tests
--- @param condition function Function to check for completion
--- @param timeout number Timeout in milliseconds (default: 1000)
--- @param interval number Check interval in milliseconds (default: 10)
--- @return boolean Success
function M.wait_for_condition(condition, timeout, interval)
  timeout = timeout or 1000
  interval = interval or 10
  local start_time = os.clock()
  
  while (os.clock() - start_time) * 1000 < timeout do
    if condition() then
      return true
    end
    -- Small sleep to prevent busy waiting
    if vim and vim.wait then
      vim.wait(interval, function() return false end)
    else
      os.execute("sleep " .. (interval / 1000))
    end
  end
  
  return false
end

--- Mock implementation of vim.schedule for testing
--- @param callback function Callback to execute
function M.mock_schedule(callback)
  -- In tests, execute immediately instead of scheduling
  if callback then
    callback()
  end
end

--- Create a mock logger for testing
--- @return table Mock logger
function M.create_logger_mock()
  return {
    logs = {},
    debug = function(self, category, message)
      table.insert(self.logs, {
        level = "debug",
        category = category,
        message = message,
        timestamp = os.time(),
      })
    end,
    info = function(self, category, message)
      table.insert(self.logs, {
        level = "info",
        category = category,
        message = message,
        timestamp = os.time(),
      })
    end,
    warn = function(self, category, message)
      table.insert(self.logs, {
        level = "warn",
        category = category,
        message = message,
        timestamp = os.time(),
      })
    end,
    error = function(self, category, message)
      table.insert(self.logs, {
        level = "error",
        category = category,
        message = message,
        timestamp = os.time(),
      })
    end,
    trace = function(self, category, message)
      table.insert(self.logs, {
        level = "trace",
        category = category,
        message = message,
        timestamp = os.time(),
      })
    end,
    get_logs = function(self, level)
      if not level then
        return self.logs
      end
      local filtered = {}
      for _, log in ipairs(self.logs) do
        if log.level == level then
          table.insert(filtered, log)
        end
      end
      return filtered
    end,
    clear = function(self)
      self.logs = {}
    end,
  }
end

return M
