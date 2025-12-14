-- luacheck: globals expect
require("tests.busted_setup")

describe("Tmux module", function()
  local tmux
  local original_env_tmux
  local original_io_popen
  local popen_commands = {}

  local function setup()
    package.loaded["claudecode.tmux"] = nil

    -- Save original environment
    original_env_tmux = vim.env.TMUX
    original_io_popen = io.popen

    -- Reset popen command tracking
    popen_commands = {}

    -- Mock io.popen to simulate tmux commands
    io.popen = function(cmd)
      table.insert(popen_commands, cmd)

      -- Create mock file handle
      local mock_handle = {}
      mock_handle.read = function(self, mode)
        -- Return mock data based on command
        if cmd:match("display%-message.*#S") then
          return "test-session\n"
        elseif cmd:match("display%-message.*#I:#W") then
          return "1:test-window\n"
        elseif cmd:match("display%-message.*#P") then
          return "0\n"
        end
        return ""
      end
      mock_handle.close = function(self)
        return true
      end
      return mock_handle
    end

    tmux = require("claudecode.tmux")
  end

  local function teardown()
    vim.env.TMUX = original_env_tmux
    io.popen = original_io_popen
    popen_commands = {}
  end

  before_each(function()
    setup()
  end)

  after_each(function()
    teardown()
  end)

  describe("is_inside_tmux", function()
    it("should return true when TMUX environment variable is set", function()
      vim.env.TMUX = "/tmp/tmux-1000/default,12345,0"
      local result = tmux.is_inside_tmux()
      expect(result).to_be_true()
    end)

    it("should return false when TMUX environment variable is not set", function()
      vim.env.TMUX = nil
      local result = tmux.is_inside_tmux()
      expect(result).to_be_false()
    end)

    it("should return false when TMUX environment variable is empty", function()
      vim.env.TMUX = ""
      local result = tmux.is_inside_tmux()
      expect(result).to_be_false()
    end)
  end)

  describe("get_session_name", function()
    it("should return session name when inside tmux", function()
      vim.env.TMUX = "/tmp/tmux-1000/default,12345,0"
      local session = tmux.get_session_name()
      expect(session).to_be("test-session")
      expect(#popen_commands).to_be(1)
      assert_contains(popen_commands[1], "tmux display-message")
    end)

    it("should return nil when not inside tmux", function()
      vim.env.TMUX = nil
      local session = tmux.get_session_name()
      expect(session).to_be_nil()
      expect(#popen_commands).to_be(0)
    end)
  end)

  describe("get_window_info", function()
    it("should return window info when inside tmux", function()
      vim.env.TMUX = "/tmp/tmux-1000/default,12345,0"
      local window = tmux.get_window_info()
      expect(window).to_be_table()
      expect(window.index).to_be(1)
      expect(window.name).to_be("test-window")
      expect(#popen_commands).to_be(1)
    end)

    it("should return nil when not inside tmux", function()
      vim.env.TMUX = nil
      local window = tmux.get_window_info()
      expect(window).to_be_nil()
      expect(#popen_commands).to_be(0)
    end)
  end)

  describe("get_pane_index", function()
    it("should return pane index when inside tmux", function()
      vim.env.TMUX = "/tmp/tmux-1000/default,12345,0"
      local pane = tmux.get_pane_index()
      expect(pane).to_be(0)
      expect(#popen_commands).to_be(1)
    end)

    it("should return nil when not inside tmux", function()
      vim.env.TMUX = nil
      local pane = tmux.get_pane_index()
      expect(pane).to_be_nil()
      expect(#popen_commands).to_be(0)
    end)
  end)

  describe("get_location_string", function()
    it("should return formatted location string when inside tmux", function()
      vim.env.TMUX = "/tmp/tmux-1000/default,12345,0"
      local location = tmux.get_location_string()
      expect(location).to_be("test-session:1:0")
    end)

    it("should return nil when not inside tmux", function()
      vim.env.TMUX = nil
      local location = tmux.get_location_string()
      expect(location).to_be_nil()
    end)
  end)

  describe("switch_to_session", function()
    it("should call tmux switch-client when inside tmux", function()
      vim.env.TMUX = "/tmp/tmux-1000/default,12345,0"
      local original_os_execute = os.execute
      local execute_commands = {}

      os.execute = function(cmd)
        table.insert(execute_commands, cmd)
        return 0 -- success
      end

      local result = tmux.switch_to_session("new-session")
      expect(result).to_be_true()
      expect(#execute_commands).to_be(1)
      assert_contains(execute_commands[1], "tmux switch-client")
      assert_contains(execute_commands[1], "new-session")

      os.execute = original_os_execute
    end)

    it("should return false when not inside tmux", function()
      vim.env.TMUX = nil
      local result = tmux.switch_to_session("new-session")
      expect(result).to_be_false()
    end)
  end)

  describe("switch_to_window", function()
    it("should call tmux select-window when inside tmux", function()
      vim.env.TMUX = "/tmp/tmux-1000/default,12345,0"
      local original_os_execute = os.execute
      local execute_commands = {}

      os.execute = function(cmd)
        table.insert(execute_commands, cmd)
        return 0 -- success
      end

      local result = tmux.switch_to_window(2)
      expect(result).to_be_true()
      expect(#execute_commands).to_be(1)
      assert_contains(execute_commands[1], "tmux select-window")

      os.execute = original_os_execute
    end)

    it("should return false when not inside tmux", function()
      vim.env.TMUX = nil
      local result = tmux.switch_to_window(2)
      expect(result).to_be_false()
    end)
  end)

  describe("create_jump_action", function()
    it("should create jump action when inside tmux", function()
      vim.env.TMUX = "/tmp/tmux-1000/default,12345,0"
      local action = tmux.create_jump_action()
      expect(action).to_be_table()
      expect(action.text).to_be("Jump to tmux: test-session:test-window")
      expect(action.callback).to_be_function()
    end)

    it("should return nil when not inside tmux", function()
      vim.env.TMUX = nil
      local action = tmux.create_jump_action()
      expect(action).to_be_nil()
    end)
  end)
end)
