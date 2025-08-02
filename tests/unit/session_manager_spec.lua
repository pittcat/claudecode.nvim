---@brief [[
--- Unit tests for session_manager module
---@brief ]]

local busted = require("busted")
local assert = require("luassert")

describe("session_manager", function()
  local session_manager
  local mock_vim

  before_each(function()
    -- Reset package loaded state
    package.loaded["claudecode.session_manager"] = nil
    package.loaded["claudecode.logger"] = nil

    -- Create mock vim API
    mock_vim = {
      loop = {
        fs_stat = function() return nil end,
        fs_scandir = function() return nil end,
        fs_scandir_next = function() return nil end,
      },
      fn = {
        getcwd = function() return "/test/project" end,
      },
      json = {
        decode = function(str)
          if str:find('"type":"summary"') then
            return { type = "summary", summary = "Test Session Summary" }
          elseif str:find('"sessionId"') then
            return {
              sessionId = "test-session-id",
              timestamp = "2025-08-02T10:30:00Z",
              gitBranch = "main"
            }
          end
          return {}
        end,
      },
    }

    -- Mock environment
    _G.os = {
      getenv = function(var)
        if var == "HOME" then
          return "/mock/home"
        end
        return nil
      end,
      date = function(format, timestamp)
        if format == "%m/%d %H:%M" then
          return "08/02 10:30"
        end
        return "2025-08-02 10:30:00"
      end,
    }

    -- Mock io.open
    _G.io = {
      open = function(path, mode)
        return {
          lines = function()
            return coroutine.wrap(function()
              coroutine.yield('{"type":"summary","summary":"Test Session Summary"}')
              coroutine.yield('{"sessionId":"test-session-id","timestamp":"2025-08-02T10:30:00Z","gitBranch":"main"}')
            end)
          end,
          close = function() end,
        }
      end,
    }

    -- Set global vim
    _G.vim = mock_vim

    -- Mock logger
    local mock_logger = {
      warn = function() end,
      error = function() end,
      debug = function() end,
      info = function() end,
    }

    package.loaded["claudecode.logger"] = mock_logger

    session_manager = require("claudecode.session_manager")
  end)

  after_each(function()
    -- Cleanup
    _G.vim = nil
    _G.os = nil
    _G.io = nil
  end)

  describe("get_session_list", function()
    it("should return empty list when no Claude config directory found", function()
      mock_vim.loop.fs_stat = function() return nil end

      local sessions = session_manager.get_session_list()

      assert.is_table(sessions)
      assert.are.equal(0, #sessions)
    end)

    it("should return empty list when no project directory found", function()
      -- Mock Claude config dir exists but project dir doesn't
      mock_vim.loop.fs_stat = function(path)
        if path:match("/.claude$") then
          return { type = "directory" }
        end
        return nil
      end

      local sessions = session_manager.get_session_list()

      assert.is_table(sessions)
      assert.are.equal(0, #sessions)
    end)

    it("should parse and return session list when files exist", function()
      -- Mock directories exist
      mock_vim.loop.fs_stat = function(path)
        return { type = "directory", mtime = { sec = 1691000000 } }
      end

      -- Mock fs_scandir to return test files
      mock_vim.loop.fs_scandir = function() return "handle" end
      local call_count = 0
      mock_vim.loop.fs_scandir_next = function()
        call_count = call_count + 1
        if call_count == 1 then
          return "test-session-1.jsonl", "file"
        elseif call_count == 2 then
          return "test-session-2.jsonl", "file"
        end
        return nil
      end

      local sessions = session_manager.get_session_list()

      assert.is_table(sessions)
      assert.are.equal(2, #sessions)
      assert.are.equal("test-session-id", sessions[1].id)
      assert.are.equal("Test Session Summary", sessions[1].summary)
      assert.are.equal("main", sessions[1].git_branch)
    end)
  end)

  describe("format_session_for_display", function()
    it("should format session info correctly", function()
      local session = {
        id = "test-id",
        summary = "Test Summary",
        modified_time = 1691000000,
        created_time = 1691000000,
        git_branch = "main",
        message_count = 10,
      }

      local formatted = session_manager.format_session_for_display(session)

      assert.is_string(formatted)
      assert.is_true(formatted:find("08/02 10:30") ~= nil)
      assert.is_true(formatted:find("main") ~= nil)
      assert.is_true(formatted:find("Test Summary") ~= nil)
      assert.is_true(formatted:find("10") ~= nil)
    end)

    it("should truncate long summaries", function()
      local session = {
        id = "test-id",
        summary = "This is a very long summary that should be truncated because it exceeds the maximum length",
        modified_time = 1691000000,
        created_time = 1691000000,
        git_branch = "main",
        message_count = 5,
      }

      local formatted = session_manager.format_session_for_display(session)

      assert.is_true(formatted:find("%.%.%.") ~= nil)  -- Should contain "..."
      assert.is_true(#formatted < 200)  -- Should be reasonable length
    end)
  end)

  describe("format_sessions_for_select", function()
    it("should return appropriate message for empty sessions", function()
      local formatted, sessions = session_manager.format_sessions_for_select({})

      assert.is_table(formatted)
      assert.is_table(sessions)
      assert.are.equal(1, #formatted)
      assert.are.equal(0, #sessions)
      assert.are.equal("No sessions found for current project", formatted[1])
    end)

    it("should format sessions with header for non-empty list", function()
      local test_sessions = {
        {
          id = "test-id",
          summary = "Test Summary",
          modified_time = 1691000000,
          created_time = 1691000000,
          git_branch = "main",
          message_count = 10,
        }
      }

      local formatted, sessions = session_manager.format_sessions_for_select(test_sessions)

      assert.is_table(formatted)
      assert.is_table(sessions)
      assert.are.equal(3, #formatted)  -- Header + separator + 1 session
      assert.are.equal(1, #sessions)
      assert.is_true(formatted[1]:find("Modified") ~= nil)  -- Header
      assert.is_true(formatted[2]:find("%-") ~= nil)  -- Separator
      assert.is_true(formatted[3]:find("Test Summary") ~= nil)  -- Session
    end)
  end)
end)