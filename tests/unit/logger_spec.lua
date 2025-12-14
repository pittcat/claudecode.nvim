-- luacheck: globals expect
require("tests.busted_setup")

describe("Logger", function()
  local logger
  local original_vim_schedule
  local original_vim_notify
  local original_nvim_echo
  local scheduled_calls = {}
  local notify_calls = {}
  local echo_calls = {}

  local function setup()
    package.loaded["claudecode.logger"] = nil

    -- Mock vim.schedule to track calls
    original_vim_schedule = vim.schedule
    vim.schedule = function(fn)
      table.insert(scheduled_calls, fn)
      -- Immediately execute the function for testing
      fn()
    end

    -- Mock vim.notify to track calls
    original_vim_notify = vim.notify
    vim.notify = function(msg, level, opts)
      table.insert(notify_calls, { msg = msg, level = level, opts = opts })
    end

    -- Mock nvim_echo to track calls
    original_nvim_echo = vim.api.nvim_echo
    vim.api.nvim_echo = function(chunks, history, opts)
      table.insert(echo_calls, { chunks = chunks, history = history, opts = opts })
    end

    logger = require("claudecode.logger")

    -- Set log level to TRACE to enable all logging levels for testing
    logger.setup({ log_level = "trace" })
  end

  local function teardown()
    vim.schedule = original_vim_schedule
    vim.notify = original_vim_notify
    vim.api.nvim_echo = original_nvim_echo
    scheduled_calls = {}
    notify_calls = {}
    echo_calls = {}
  end

  before_each(function()
    setup()
  end)

  after_each(function()
    teardown()
  end)

  describe("error logging", function()
    it("should wrap error calls in vim.schedule", function()
      logger.error("test", "error message")

      -- Should have made one scheduled call
      expect(#scheduled_calls).to_be(1)

      -- Should have called vim.notify with error level
      expect(#notify_calls).to_be(1)
      expect(notify_calls[1].level).to_be(vim.log.levels.ERROR)
      assert_contains(notify_calls[1].msg, "error message")
    end)

    it("should handle error calls without component", function()
      logger.error("error message")

      expect(#scheduled_calls).to_be(1)
      expect(#notify_calls).to_be(1)
      assert_contains(notify_calls[1].msg, "error message")
    end)
  end)

  describe("warn logging", function()
    it("should wrap warn calls in vim.schedule", function()
      logger.warn("test", "warning message")

      -- Should have made one scheduled call
      expect(#scheduled_calls).to_be(1)

      -- Should have called vim.notify with warn level
      expect(#notify_calls).to_be(1)
      expect(notify_calls[1].level).to_be(vim.log.levels.WARN)
      assert_contains(notify_calls[1].msg, "warning message")
    end)

    it("should handle warn calls without component", function()
      logger.warn("warning message")

      expect(#scheduled_calls).to_be(1)
      expect(#notify_calls).to_be(1)
      assert_contains(notify_calls[1].msg, "warning message")
    end)
  end)

  describe("info logging", function()
    it("should wrap info calls in vim.schedule", function()
      logger.info("test", "info message")

      -- Should have made one scheduled call
      expect(#scheduled_calls).to_be(1)

      -- Should have called nvim_echo instead of notify
      expect(#echo_calls).to_be(1)
      expect(#notify_calls).to_be(0)
      assert_contains(echo_calls[1].chunks[1][1], "info message")
    end)
  end)

  describe("debug logging", function()
    it("should wrap debug calls in vim.schedule", function()
      logger.debug("test", "debug message")

      -- Should have made one scheduled call
      expect(#scheduled_calls).to_be(1)

      -- Should have called nvim_echo instead of notify
      expect(#echo_calls).to_be(1)
      expect(#notify_calls).to_be(0)
      assert_contains(echo_calls[1].chunks[1][1], "debug message")
    end)
  end)

  describe("trace logging", function()
    it("should wrap trace calls in vim.schedule", function()
      logger.trace("test", "trace message")

      -- Should have made one scheduled call
      expect(#scheduled_calls).to_be(1)

      -- Should have called nvim_echo instead of notify
      expect(#echo_calls).to_be(1)
      expect(#notify_calls).to_be(0)
      assert_contains(echo_calls[1].chunks[1][1], "trace message")
    end)
  end)

  describe("fast event context safety", function()
    it("should not call vim API functions directly", function()
      -- Simulate a fast event context by removing the mocked functions
      -- and ensuring no direct calls are made
      local direct_notify_called = false
      local direct_echo_called = false

      vim.notify = function()
        direct_notify_called = true
      end

      vim.api.nvim_echo = function()
        direct_echo_called = true
      end

      vim.schedule = function(fn)
        -- Don't execute the function, just verify it was scheduled
        table.insert(scheduled_calls, fn)
      end

      logger.error("test", "error in fast context")
      logger.warn("test", "warn in fast context")
      logger.info("test", "info in fast context")

      -- All should be scheduled, none should be called directly
      expect(#scheduled_calls).to_be(3)
      expect(direct_notify_called).to_be_false()
      expect(direct_echo_called).to_be_false()
    end)
  end)

  describe("notify", function()
    it("should call vim.notify with scheduled function", function()
      logger.notify("test notification", vim.log.levels.INFO, { title = "Test" })

      expect(#scheduled_calls).to_be(1)
      expect(#notify_calls).to_be(1)
      expect(notify_calls[1].msg).to_be("test notification")
      expect(notify_calls[1].level).to_be(vim.log.levels.INFO)
      expect(notify_calls[1].opts.title).to_be("Test")
    end)

    it("should default to INFO level", function()
      logger.notify("test notification")

      expect(#notify_calls).to_be(1)
      expect(notify_calls[1].level).to_be(vim.log.levels.INFO)
    end)
  end)

  describe("notify_with_tmux_link", function()
    before_each(function()
      -- Mock config module
      package.loaded["claudecode.config"] = {
        defaults = {
          enable_tmux_notifications = true,
        },
      }
    end)

    it("should fall back to regular notify when not in tmux", function()
      -- Mock tmux module to return false for is_inside_tmux
      package.loaded["claudecode.tmux"] = {
        is_inside_tmux = function()
          return false
        end,
      }

      logger.notify_with_tmux_link("test message", vim.log.levels.INFO)

      expect(#notify_calls).to_be(1)
      expect(notify_calls[1].msg).to_be("test message")
    end)

    it("should add tmux info when inside tmux", function()
      -- Mock tmux module
      package.loaded["claudecode.tmux"] = {
        is_inside_tmux = function()
          return true
        end,
        get_session_name = function()
          return "test-session"
        end,
        get_window_info = function()
          return { index = 1, name = "test-window" }
        end,
        switch_to_session = function() end,
        switch_to_window = function() end,
      }

      logger.notify_with_tmux_link("test message", vim.log.levels.INFO)

      expect(#notify_calls).to_be(1)
      assert_contains(notify_calls[1].msg, "test message")
      assert_contains(notify_calls[1].msg, "test-session:test-window")
      expect(notify_calls[1].opts.on_open).to_be_function()
    end)

    it("should respect enable_tmux_notifications config", function()
      -- Mock config with tmux notifications disabled
      package.loaded["claudecode.config"] = {
        defaults = {
          enable_tmux_notifications = false,
        },
      }

      -- Mock tmux module
      package.loaded["claudecode.tmux"] = {
        is_inside_tmux = function()
          return true
        end,
        get_session_name = function()
          return "test-session"
        end,
      }

      logger.notify_with_tmux_link("test message", vim.log.levels.INFO)

      expect(#notify_calls).to_be(1)
      -- Should not contain tmux info when disabled
      expect(notify_calls[1].msg).to_be("test message")
      expect(notify_calls[1].opts.on_open).to_be_nil()
    end)
  end)
end)
