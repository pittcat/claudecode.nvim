---Native Neovim terminal provider for Claude Code.
---@module 'claudecode.terminal.native'

local M = {}

local logger = require("claudecode.logger")
local utils = require("claudecode.utils")

-- State table: key -> terminal state {bufnr, winid, jobid}
local terminals_by_key = {}
local tip_shown = false

---@type ClaudeCodeTerminalConfig
local config = require("claudecode.terminal").defaults

---Get terminal state for scope key
---@param scope_key string|number
---@return table|nil
local function get_terminal_for_scope(scope_key)
  return terminals_by_key[scope_key]
end

---Set terminal state for scope key
---@param scope_key string|number
---@param state table Terminal state {bufnr, winid, jobid}
local function set_terminal_for_scope(scope_key, state)
  terminals_by_key[scope_key] = state
end

---Clear terminal state for scope key
---@param scope_key string|number
local function clear_terminal_for_scope(scope_key)
  terminals_by_key[scope_key] = nil
end

---Get current scope key based on config
---@return string|number
local function get_current_scope_key()
  local terminal_mod = require("claudecode.terminal")
  if terminal_mod.defaults and terminal_mod.defaults.session_scope == "tab" then
    return vim.api.nvim_get_current_tabpage()
  else
    return "global"
  end
end

---Check if terminal is valid for scope key
---@param scope_key string|number
---@return boolean
local function is_valid_for_scope(scope_key)
  local term_state = get_terminal_for_scope(scope_key)
  if not term_state then
    return false
  end

  -- Check if buffer is valid
  if not term_state.bufnr or not vim.api.nvim_buf_is_valid(term_state.bufnr) then
    clear_terminal_for_scope(scope_key)
    return false
  end

  -- If buffer is valid but window is invalid, try to find a window displaying this buffer
  if not term_state.winid or not vim.api.nvim_win_is_valid(term_state.winid) then
    local windows = vim.api.nvim_list_wins()
    for _, win in ipairs(windows) do
      if vim.api.nvim_win_get_buf(win) == term_state.bufnr then
        term_state.winid = win
        set_terminal_for_scope(scope_key, term_state) -- Update state
        logger.debug("terminal", "Recovered terminal window ID for scope:", scope_key, "win:", win)
        return true
      end
    end
    -- Buffer exists but no window displays it - this is normal for hidden terminals
    return true
  end

  -- Both buffer and window are valid
  return true
end

local function open_terminal(cmd_string, env_table, effective_config, focus)
  focus = utils.normalize_focus(focus)
  config = effective_config -- 保存配置以供后续使用

  -- Get scope key
  local scope_key = effective_config.scope_key or "global"

  if is_valid_for_scope(scope_key) then
    -- Terminal exists, focus it
    local term_state = get_terminal_for_scope(scope_key)
    if focus then
      vim.api.nvim_set_current_win(term_state.winid)
      if config.auto_insert_mode then
        vim.cmd("startinsert")
      end
    end
    return true
  end

  local original_win = vim.api.nvim_get_current_win()
  local width = math.floor(vim.o.columns * effective_config.split_width_percentage)
  local full_height = vim.o.lines
  local placement_modifier

  if effective_config.split_side == "left" then
    placement_modifier = "topleft "
  else
    placement_modifier = "botright "
  end

  vim.cmd(placement_modifier .. width .. "vsplit")
  local new_winid = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_height(new_winid, full_height)

  vim.api.nvim_win_call(new_winid, function()
    vim.cmd("enew")
  end)

  local term_cmd_arg
  if cmd_string:find(" ", 1, true) then
    term_cmd_arg = vim.split(cmd_string, " ", { plain = true, trimempty = false })
  else
    term_cmd_arg = { cmd_string }
  end

  local new_jobid = vim.fn.termopen(term_cmd_arg, {
    env = env_table,
    cwd = effective_config.cwd,
    on_exit = function(job_id, exit_code, _)
      vim.schedule(function()
        -- Only clean up matching scope
        local term_state_for_exit = get_terminal_for_scope(scope_key)
        if term_state_for_exit and job_id == term_state_for_exit.jobid then
          logger.debug("terminal", "Terminal process exited for scope:", scope_key)

          local current_winid_for_job = term_state_for_exit.winid
          local current_bufnr_for_job = term_state_for_exit.bufnr

          clear_terminal_for_scope(scope_key)

          if not effective_config.auto_close then
            return
          end

          if current_winid_for_job and vim.api.nvim_win_is_valid(current_winid_for_job) then
            if current_bufnr_for_job and vim.api.nvim_buf_is_valid(current_bufnr_for_job) then
              if vim.api.nvim_win_get_buf(current_winid_for_job) == current_bufnr_for_job then
                vim.api.nvim_win_close(current_winid_for_job, true)
              end
            else
              vim.api.nvim_win_close(current_winid_for_job, true)
            end
          end
        end
      end)
    end,
  })

  if not new_jobid or new_jobid == 0 then
    vim.notify("Failed to open native terminal.", vim.log.levels.ERROR)
    vim.api.nvim_win_close(new_winid, true)
    vim.api.nvim_set_current_win(original_win)
    return false
  end

  local new_bufnr = vim.api.nvim_get_current_buf()
  vim.bo[new_bufnr].bufhidden = "hide"

  -- Save to corresponding scope
  set_terminal_for_scope(scope_key, {
    winid = new_winid,
    bufnr = new_bufnr,
    jobid = new_jobid,
  })

  -- Fix terminal display corruption with reduced scrollback for better performance
  local scrollback_size = 1000 -- Reduced from 10000 to prevent render lag
  vim.api.nvim_buf_set_option(new_bufnr, "scrollback", scrollback_size)

  -- Apply minimal display fixes to prevent flickering
  vim.schedule(function()
    if vim.api.nvim_buf_is_valid(new_bufnr) and vim.api.nvim_win_is_valid(new_winid) then
      -- Set up throttled autocmd to handle display corruption only when needed
      local last_redraw = 0
      local redraw_throttle = 200 -- Minimum 200ms between redraws

      vim.api.nvim_create_autocmd("BufEnter", {
        buffer = new_bufnr,
        callback = function()
          local now = vim.loop.hrtime() / 1000000 -- Convert to milliseconds
          if now - last_redraw > redraw_throttle then
            vim.schedule(function()
              if vim.api.nvim_get_current_buf() == new_bufnr then
                -- Only redraw if there are visible display issues
                -- Check if terminal content appears corrupted before redrawing
                local lines = vim.api.nvim_buf_get_lines(new_bufnr, -10, -1, false)
                local has_corruption = false
                for _, line in ipairs(lines) do
                  if line:match("\27%[[") then -- Check for incomplete ANSI sequences
                    has_corruption = true
                    break
                  end
                end

                if has_corruption then
                  vim.cmd("redraw!")
                  last_redraw = now
                end
              end
            end)
          end
        end,
        once = false,
      })
    end
  end)

  if focus then
    vim.api.nvim_set_current_win(new_winid)
    if config.auto_insert_mode then
      vim.cmd("startinsert")
    end
  else
    vim.api.nvim_set_current_win(original_win)
  end

  if config.show_native_term_exit_tip and not tip_shown then
    vim.notify("Native terminal opened. Press Ctrl-\\ Ctrl-N to return to Normal mode.", vim.log.levels.INFO)
    tip_shown = true
  end
  return true
end

local function close_terminal(scope_key)
  if is_valid_for_scope(scope_key) then
    local term_state = get_terminal_for_scope(scope_key)
    if term_state and term_state.winid and vim.api.nvim_win_is_valid(term_state.winid) then
      vim.api.nvim_win_close(term_state.winid, true)
    end
    clear_terminal_for_scope(scope_key)
  end
end

local function focus_terminal(scope_key)
  if is_valid_for_scope(scope_key) then
    local term_state = get_terminal_for_scope(scope_key)
    if term_state and term_state.winid and vim.api.nvim_win_is_valid(term_state.winid) then
      vim.api.nvim_set_current_win(term_state.winid)
      if config.auto_insert_mode then
        vim.cmd("startinsert")
      end
    end
  end
end

local function is_terminal_visible(scope_key)
  local term_state = get_terminal_for_scope(scope_key)
  if not term_state or not term_state.bufnr or not vim.api.nvim_buf_is_valid(term_state.bufnr) then
    return false
  end

  local windows = vim.api.nvim_list_wins()
  for _, win in ipairs(windows) do
    if vim.api.nvim_win_is_valid(win) and vim.api.nvim_win_get_buf(win) == term_state.bufnr then
      term_state.winid = win
      set_terminal_for_scope(scope_key, term_state)
      return true
    end
  end

  term_state.winid = nil
  set_terminal_for_scope(scope_key, term_state)
  return false
end

local function hide_terminal(scope_key)
  local term_state = get_terminal_for_scope(scope_key)
  if not term_state or not term_state.winid or not vim.api.nvim_win_is_valid(term_state.winid) then
    logger.debug("terminal", "No valid terminal window to hide for scope:", scope_key)
    return
  end

  vim.api.nvim_win_close(term_state.winid, false)
  term_state.winid = nil
  set_terminal_for_scope(scope_key, term_state)
  logger.debug("terminal", "Hidden terminal for scope:", scope_key)
end

local function show_hidden_terminal(scope_key, effective_config, focus)
  local term_state = get_terminal_for_scope(scope_key)
  if not term_state or not term_state.bufnr or not vim.api.nvim_buf_is_valid(term_state.bufnr) then
    logger.error("terminal", "No valid hidden terminal buffer to show for scope:", scope_key)
    return false
  end

  config = effective_config -- 保存配置以供后续使用

  if is_terminal_visible(scope_key) then
    logger.debug("terminal", "Terminal already visible for scope:", scope_key)
    if focus then
      focus_terminal(scope_key)
    end
    return true
  end

  local original_win = vim.api.nvim_get_current_win()

  -- Create a new window for the existing buffer
  local width = math.floor(vim.o.columns * effective_config.split_width_percentage)
  local full_height = vim.o.lines
  local placement_modifier

  if effective_config.split_side == "left" then
    placement_modifier = "topleft "
  else
    placement_modifier = "botright "
  end

  vim.cmd(placement_modifier .. width .. "vsplit")
  local new_winid = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_height(new_winid, full_height)

  -- Set the existing buffer in the new window
  vim.api.nvim_win_set_buf(new_winid, term_state.bufnr)

  term_state.winid = new_winid
  set_terminal_for_scope(scope_key, term_state)

  if focus then
    vim.api.nvim_set_current_win(new_winid)
    if config.auto_insert_mode then
      vim.cmd("startinsert")
    end
  else
    vim.api.nvim_set_current_win(original_win)
  end

  logger.debug("terminal", "Showed hidden terminal for scope:", scope_key)
  return true
end

---Setup the terminal module
---@param term_config ClaudeCodeTerminalConfig
function M.setup(term_config)
  config = term_config
end

--- @param cmd_string string
--- @param env_table table
--- @param effective_config table
--- @param focus boolean|nil
function M.open(cmd_string, env_table, effective_config, focus)
  focus = utils.normalize_focus(focus)
  local scope_key = effective_config.scope_key or "global"

  if is_valid_for_scope(scope_key) then
    local term_state = get_terminal_for_scope(scope_key)
    if not term_state.winid or not vim.api.nvim_win_is_valid(term_state.winid) then
      show_hidden_terminal(scope_key, effective_config, focus)
    else
      if focus then
        focus_terminal(scope_key)
      end
    end
  else
    if not open_terminal(cmd_string, env_table, effective_config, focus) then
      vim.notify("Failed to open Claude terminal using native fallback.", vim.log.levels.ERROR)
    end
  end
end

function M.close()
  local scope_key = get_current_scope_key()
  close_terminal(scope_key)
end

---Simple toggle: always show/hide terminal regardless of focus
---@param cmd_string string
---@param env_table table
---@param effective_config ClaudeCodeTerminalConfig
function M.simple_toggle(cmd_string, env_table, effective_config)
  local scope_key = effective_config.scope_key or "global"
  local has_terminal = get_terminal_for_scope(scope_key) ~= nil
  local is_visible = has_terminal and is_terminal_visible(scope_key)

  if is_visible then
    hide_terminal(scope_key)
  else
    if has_terminal then
      if show_hidden_terminal(scope_key, effective_config, true) then
        logger.debug("terminal", "Showing hidden terminal for scope:", scope_key)
      else
        logger.error("terminal", "Failed to show hidden terminal for scope:", scope_key)
      end
    else
      if not open_terminal(cmd_string, env_table, effective_config) then
        vim.notify("Failed to open Claude terminal using native fallback (simple_toggle).", vim.log.levels.ERROR)
      end
    end
  end
end

---Smart focus toggle: switches to terminal if not focused, hides if currently focused
---@param cmd_string string
---@param env_table table
---@param effective_config ClaudeCodeTerminalConfig
function M.focus_toggle(cmd_string, env_table, effective_config)
  local scope_key = effective_config.scope_key or "global"
  local has_terminal = get_terminal_for_scope(scope_key) ~= nil
  local is_visible = has_terminal and is_terminal_visible(scope_key)

  if not is_visible then
    if has_terminal then
      show_hidden_terminal(scope_key, effective_config, true)
    else
      open_terminal(cmd_string, env_table, effective_config, true)
    end
  else
    local term_state = get_terminal_for_scope(scope_key)
    if term_state and term_state.winid then
      local current_win = vim.api.nvim_get_current_win()
      if current_win == term_state.winid then
        hide_terminal(scope_key)
      else
        focus_terminal(scope_key)
      end
    end
  end
end

--- Legacy toggle function for backward compatibility (defaults to simple_toggle)
--- @param cmd_string string
--- @param env_table table
--- @param effective_config ClaudeCodeTerminalConfig
function M.toggle(cmd_string, env_table, effective_config)
  M.simple_toggle(cmd_string, env_table, effective_config)
end

--- @return number|nil
function M.get_active_bufnr()
  local scope_key = get_current_scope_key()
  if is_valid_for_scope(scope_key) then
    local term_state = get_terminal_for_scope(scope_key)
    return term_state and term_state.bufnr or nil
  end
  return nil
end

--- @return boolean
function M.is_available()
  return true -- Native provider is always available
end

--- Get the terminal job channel ID for text injection
--- @return number|nil The job channel ID, or nil if no terminal is active
function M.get_job_channel()
  local scope_key = get_current_scope_key()
  if is_valid_for_scope(scope_key) then
    local term_state = get_terminal_for_scope(scope_key)
    if term_state and term_state.jobid and term_state.jobid > 0 then
      return term_state.jobid
    end
  end
  return nil
end

---Clean up terminal for specific scope (called when tab is closed)
---@param scope_key string|number
function M._cleanup_scope(scope_key)
  close_terminal(scope_key)
  logger.debug("terminal", "Cleaned up native terminal for scope:", scope_key)
end

---Clean up all terminals (called on exit)
function M._cleanup_all_scopes()
  for scope_key, _ in pairs(terminals_by_key) do
    close_terminal(scope_key)
  end
  terminals_by_key = {}
  logger.debug("terminal", "Cleaned up all native terminals")
end

--- @type ClaudeCodeTerminalProvider
return M
