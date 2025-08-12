--- Snacks.nvim terminal provider for Claude Code.
-- @module claudecode.terminal.snacks

--- @type TerminalProvider
local M = {}

local snacks_available, Snacks = pcall(require, "snacks")
local logger = require("claudecode.logger")
local utils = require("claudecode.utils")
local terminal = nil

--- @return boolean
local function is_available()
  return snacks_available and Snacks and Snacks.terminal
end

--- Setup event handlers for terminal instance
--- @param term_instance table The Snacks terminal instance
--- @param config table Configuration options
local function setup_terminal_events(term_instance, config)
  -- 事件节流变量
  local last_buf_enter = 0
  local last_win_enter = 0
  local last_buf_leave = 0
  local event_throttle_ms = 100 -- 100ms 内的重复事件将被忽略

  -- 添加节流的事件监听
  term_instance:on("BufEnter", function()
    local now = vim.loop.hrtime() / 1000000
    if now - last_buf_enter > event_throttle_ms then
      last_buf_enter = now

      -- 在 BufEnter 时应用防闪烁设置
      vim.schedule(function()
        if term_instance.win and vim.api.nvim_win_is_valid(term_instance.win) then
          -- 临时禁用某些可能导致闪烁的选项
          pcall(vim.api.nvim_win_set_option, term_instance.win, "cursorline", false)
          pcall(vim.api.nvim_win_set_option, term_instance.win, "number", false)
          pcall(vim.api.nvim_win_set_option, term_instance.win, "relativenumber", false)
        end
      end)
    end
  end, { buf = true })

  term_instance:on("WinEnter", function()
    local now = vim.loop.hrtime() / 1000000
    if now - last_win_enter > event_throttle_ms then
      last_win_enter = now


      -- 在窗口进入时启动防闪烁模式
      local anti_flicker = require("claudecode.anti_flicker")

      -- 检查是否为快速切换（与上次 BufLeave 的时间间隔）
      local time_since_last_leave = now - last_buf_leave
      if time_since_last_leave < 500 then -- 500ms 内的切换视为快速切换
        anti_flicker.handle_rapid_switching()
      else
        anti_flicker.start_temporary_anti_flicker(150)
      end

      -- 优化终端窗口
      anti_flicker.optimize_terminal_window(term_instance.win, term_instance.buf)
    end
  end, { buf = true })

  term_instance:on("BufLeave", function()
    local now = vim.loop.hrtime() / 1000000
    if now - last_buf_leave > event_throttle_ms then
      last_buf_leave = now
    end
  end, { buf = true })

  -- Handle command completion/exit - only if auto_close is enabled
  if config.auto_close then
    term_instance:on("TermClose", function()
      local exit_code = vim.v.event.status
      if exit_code ~= 0 then
        logger.error("terminal", "Claude exited with code " .. exit_code .. ".\nCheck for any errors.")
      end

      -- Clean up
      terminal = nil
      vim.schedule(function()
        term_instance:close({ buf = true })
        vim.cmd.checktime()
      end)
    end, { buf = true })
  end

  -- Handle buffer deletion
  term_instance:on("BufWipeout", function()
    logger.debug("terminal", "Terminal buffer wiped")
    terminal = nil
  end, { buf = true })
end

--- Builds Snacks terminal options with focus control
--- @param config table Terminal configuration (split_side, split_width_percentage, etc.)
--- @param env_table table Environment variables to set for the terminal process
--- @param focus boolean|nil Whether to focus the terminal when opened (defaults to true)
--- @return table Snacks terminal options with start_insert/auto_insert controlled by focus parameter
local function build_opts(config, env_table, focus)
  focus = utils.normalize_focus(focus)
  local should_auto_insert = focus and config.auto_insert_mode
  return {
    env = env_table,
    start_insert = should_auto_insert,
    auto_insert = should_auto_insert,
    auto_close = false,
    win = vim.tbl_deep_extend("force", {
      position = config.split_side,
      width = config.split_width_percentage,
      height = 0,
      relative = "editor",
      -- 添加防闪烁的窗口选项
      style = "minimal", -- 减少边框渲染
      border = "none", -- 无边框减少重绘
    }, config.snacks_win_opts or {}),
    -- Fix terminal display corruption with reduced scrollback for better performance
    bo = {
      scrollback = 1000, -- Reduced from 10000 to prevent render lag
      -- 添加防闪烁的缓冲区选项
      modifiable = false,
      readonly = false,
      swapfile = false,
      undofile = false,
    },
    -- 添加窗口渲染选项以减少闪烁
    wo = {
      number = false,
      relativenumber = false,
      cursorline = false,
      cursorcolumn = false,
      signcolumn = "no",
      foldcolumn = "0",
      colorcolumn = "",
      statuscolumn = "",
    },
  }
end

function M.setup()
  -- No specific setup needed for Snacks provider
end

--- @param cmd_string string
--- @param env_table table
--- @param config table
--- @param focus boolean|nil
function M.open(cmd_string, env_table, config, focus)
  if not is_available() then
    vim.notify("Snacks.nvim terminal provider selected but Snacks.terminal not available.", vim.log.levels.ERROR)
    return
  end

  focus = utils.normalize_focus(focus)

  if terminal and terminal:buf_valid() then
    -- Check if terminal exists but is hidden (no window)
    if not terminal.win or not vim.api.nvim_win_is_valid(terminal.win) then
      -- Terminal is hidden, show it using snacks toggle
      terminal:toggle()
      if focus then
        -- 使用新的防闪烁系统
        local anti_flicker = require("claudecode.anti_flicker")
        anti_flicker.start_temporary_anti_flicker(200)

        terminal:focus()

        local term_buf_id = terminal.buf
        if
          config.auto_insert_mode
          and term_buf_id
          and vim.api.nvim_buf_get_option(term_buf_id, "buftype") == "terminal"
        then
          if terminal.win and vim.api.nvim_win_is_valid(terminal.win) then
            vim.api.nvim_win_call(terminal.win, function()
              vim.cmd("startinsert")
            end)
          end
        end
      end
    else
      -- Terminal is already visible
      if focus then
        -- 使用新的防闪烁系统
        local anti_flicker = require("claudecode.anti_flicker")
        anti_flicker.start_temporary_anti_flicker(200)

        terminal:focus()

        local term_buf_id = terminal.buf
        if term_buf_id and vim.api.nvim_buf_get_option(term_buf_id, "buftype") == "terminal" then
          -- Check if window is valid before calling nvim_win_call
          if terminal.win and vim.api.nvim_win_is_valid(terminal.win) then
            vim.api.nvim_win_call(terminal.win, function()
              vim.cmd("startinsert")
            end)
          end
        end
      end
    end
    return
  end

  local opts = build_opts(config, env_table, focus)
  local term_instance = Snacks.terminal.open(cmd_string, opts)

  if term_instance and term_instance:buf_valid() then
    -- 应用额外的防闪烁设置
    if term_instance.buf and vim.api.nvim_buf_is_valid(term_instance.buf) then
      vim.api.nvim_buf_set_option(term_instance.buf, "number", false)
      vim.api.nvim_buf_set_option(term_instance.buf, "relativenumber", false)
      vim.api.nvim_buf_set_option(term_instance.buf, "cursorline", false)
      vim.api.nvim_buf_set_option(term_instance.buf, "signcolumn", "no")
      vim.api.nvim_buf_set_option(term_instance.buf, "foldcolumn", "0")
    end

    if term_instance.win and vim.api.nvim_win_is_valid(term_instance.win) then
      vim.api.nvim_win_set_option(term_instance.win, "number", false)
      vim.api.nvim_win_set_option(term_instance.win, "relativenumber", false)
      vim.api.nvim_win_set_option(term_instance.win, "cursorline", false)
      vim.api.nvim_win_set_option(term_instance.win, "cursorcolumn", false)
      vim.api.nvim_win_set_option(term_instance.win, "signcolumn", "no")
      vim.api.nvim_win_set_option(term_instance.win, "foldcolumn", "0")
      vim.api.nvim_win_set_option(term_instance.win, "colorcolumn", "")
    end

    setup_terminal_events(term_instance, config)
    terminal = term_instance

    -- 添加监听器来防止意外进入 insert 模式
    if not config.auto_insert_mode then
      local augroup = vim.api.nvim_create_augroup("ClaudeCodeAutoInsertPrevention", { clear = true })
      vim.api.nvim_create_autocmd({ "WinEnter", "BufEnter", "TermEnter" }, {
        group = augroup,
        buffer = term_instance.buf,
        callback = function(event)
          vim.schedule(function()
            local mode = vim.api.nvim_get_mode().mode
            -- 如果进入了 insert 模式但我们不希望这样，强制回到 normal 模式
            if mode:sub(1, 1) == "i" then
              vim.cmd("stopinsert")
            end
          end)
        end,
      })
    end
  else
    terminal = nil
    local logger = require("claudecode.logger")
    local error_details = {}
    if not term_instance then
      table.insert(error_details, "Snacks.terminal.open() returned nil")
    elseif not term_instance:buf_valid() then
      table.insert(error_details, "terminal instance is invalid")
      if term_instance.buf and not vim.api.nvim_buf_is_valid(term_instance.buf) then
        table.insert(error_details, "buffer is invalid")
      end
      if term_instance.win and not vim.api.nvim_win_is_valid(term_instance.win) then
        table.insert(error_details, "window is invalid")
      end
    end

    local context = string.format("cmd='%s', opts=%s", cmd_string, vim.inspect(opts))
    local error_msg = string.format(
      "Failed to open Claude terminal using Snacks. Details: %s. Context: %s",
      table.concat(error_details, ", "),
      context
    )
    vim.notify(error_msg, vim.log.levels.ERROR)
    logger.debug("terminal", error_msg)
  end
end

function M.close()
  if not is_available() then
    return
  end
  if terminal and terminal:buf_valid() then
    terminal:close()
  end
end

--- Simple toggle: always show/hide terminal regardless of focus
--- @param cmd_string string
--- @param env_table table
--- @param config table
function M.simple_toggle(cmd_string, env_table, config)
  if not is_available() then
    vim.notify("Snacks.nvim terminal provider selected but Snacks.terminal not available.", vim.log.levels.ERROR)
    return
  end

  local logger = require("claudecode.logger")

  -- Check if terminal exists and is visible
  if terminal and terminal:buf_valid() and terminal:win_valid() then
    -- Terminal is visible, hide it
    logger.debug("terminal", "Simple toggle: hiding visible terminal")
    terminal:toggle()
  elseif terminal and terminal:buf_valid() and not terminal:win_valid() then
    -- Terminal exists but not visible, show it
    logger.debug("terminal", "Simple toggle: showing hidden terminal")
    terminal:toggle()
  else
    -- No terminal exists, create new one
    M.open(cmd_string, env_table, config, false) -- 不自动聚焦
  end
end

--- Smart focus toggle: switches to terminal if not focused, hides if currently focused
--- @param cmd_string string
--- @param env_table table
--- @param config table
function M.focus_toggle(cmd_string, env_table, config)
  if not is_available() then
    vim.notify("Snacks.nvim terminal provider selected but Snacks.terminal not available.", vim.log.levels.ERROR)
    return
  end

  local logger = require("claudecode.logger")

  -- Terminal exists, is valid, but not visible
  if terminal and terminal:buf_valid() and not terminal:win_valid() then
    logger.debug("terminal", "Focus toggle: showing hidden terminal")
    terminal:toggle()
  -- Terminal exists, is valid, and is visible
  elseif terminal and terminal:buf_valid() and terminal:win_valid() then
    local claude_term_neovim_win_id = terminal.win
    local current_neovim_win_id = vim.api.nvim_get_current_win()

    -- you're IN it
    if claude_term_neovim_win_id == current_neovim_win_id then
      logger.debug("terminal", "Focus toggle: hiding terminal (currently focused)")
      terminal:toggle()
    -- you're NOT in it
    else
      logger.debug("terminal", "Focus toggle: focusing terminal")
      vim.api.nvim_set_current_win(claude_term_neovim_win_id)
      if config.auto_insert_mode and terminal.buf and vim.api.nvim_buf_is_valid(terminal.buf) then
        if vim.api.nvim_buf_get_option(terminal.buf, "buftype") == "terminal" then
          vim.api.nvim_win_call(claude_term_neovim_win_id, function()
            vim.cmd("startinsert")
          end)
        end
      end
    end
  -- No terminal exists
  else
    logger.debug("terminal", "Focus toggle: creating new terminal")
    M.open(cmd_string, env_table, config)
  end
end

--- Legacy toggle function for backward compatibility (defaults to simple_toggle)
--- @param cmd_string string
--- @param env_table table
--- @param config table
function M.toggle(cmd_string, env_table, config)
  M.simple_toggle(cmd_string, env_table, config)
end

--- @return number|nil
function M.get_active_bufnr()
  if terminal and terminal:buf_valid() and terminal.buf then
    if vim.api.nvim_buf_is_valid(terminal.buf) then
      return terminal.buf
    end
  end
  return nil
end

--- @return boolean
function M.is_available()
  return is_available()
end

-- For testing purposes
--- @return table|nil
function M._get_terminal_for_test()
  return terminal
end

return M
