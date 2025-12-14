--- Tmux integration for claudecode.nvim
--- Provides tmux session/window detection and navigation
---@module 'claudecode.tmux'

local M = {}

--- Check if running inside tmux
---@return boolean
function M.is_inside_tmux()
  return vim.env.TMUX ~= nil and vim.env.TMUX ~= ""
end

--- Get current tmux session name
---@return string|nil session_name The current tmux session name, or nil if not in tmux
function M.get_session_name()
  if not M.is_inside_tmux() then
    return nil
  end

  local handle = io.popen("tmux display-message -p '#S' 2>/dev/null")
  if not handle then
    return nil
  end

  local session = handle:read("*a")
  handle:close()

  if session then
    session = session:gsub("%s+$", "") -- trim trailing whitespace
    return session ~= "" and session or nil
  end

  return nil
end

--- Get current tmux window index and name
---@return table|nil window_info Table with {index, name} or nil if not in tmux
function M.get_window_info()
  if not M.is_inside_tmux() then
    return nil
  end

  local handle = io.popen("tmux display-message -p '#I:#W' 2>/dev/null")
  if not handle then
    return nil
  end

  local output = handle:read("*a")
  handle:close()

  if output then
    output = output:gsub("%s+$", "") -- trim trailing whitespace
    local index, name = output:match("^(%d+):(.*)$")
    if index and name then
      return {
        index = tonumber(index),
        name = name,
      }
    end
  end

  return nil
end

--- Get current tmux pane index
---@return number|nil pane_index The current pane index, or nil if not in tmux
function M.get_pane_index()
  if not M.is_inside_tmux() then
    return nil
  end

  local handle = io.popen("tmux display-message -p '#P' 2>/dev/null")
  if not handle then
    return nil
  end

  local pane = handle:read("*a")
  handle:close()

  if pane then
    pane = pane:gsub("%s+$", "") -- trim trailing whitespace
    local pane_num = tonumber(pane)
    return pane_num
  end

  return nil
end

--- Switch to a tmux session
---@param session_name string The session name to switch to
---@return boolean success Whether the switch was successful
function M.switch_to_session(session_name)
  if not M.is_inside_tmux() then
    return false
  end

  local cmd = string.format("tmux switch-client -t %s 2>/dev/null", vim.fn.shellescape(session_name))
  local result = os.execute(cmd)
  return result == 0
end

--- Switch to a tmux window in the current session
---@param window_target string|number Window name or index
---@return boolean success Whether the switch was successful
function M.switch_to_window(window_target)
  if not M.is_inside_tmux() then
    return false
  end

  local cmd = string.format("tmux select-window -t %s 2>/dev/null", vim.fn.shellescape(tostring(window_target)))
  local result = os.execute(cmd)
  return result == 0
end

--- Switch to a tmux pane in the current window
---@param pane_index number Pane index
---@return boolean success Whether the switch was successful
function M.switch_to_pane(pane_index)
  if not M.is_inside_tmux() then
    return false
  end

  local cmd = string.format("tmux select-pane -t %d 2>/dev/null", pane_index)
  local result = os.execute(cmd)
  return result == 0
end

--- Get a formatted tmux location string
---@return string|nil location Formatted location like "session:window.pane" or nil
function M.get_location_string()
  if not M.is_inside_tmux() then
    return nil
  end

  local session = M.get_session_name()
  local window = M.get_window_info()
  local pane = M.get_pane_index()

  if not session then
    return nil
  end

  local parts = { session }

  if window and window.index then
    table.insert(parts, tostring(window.index))
  end

  if pane then
    table.insert(parts, tostring(pane))
  end

  return table.concat(parts, ":")
end

--- Create a notification action to jump to current tmux location
---@return table|nil action Notification action configuration or nil
function M.create_jump_action()
  if not M.is_inside_tmux() then
    return nil
  end

  local session = M.get_session_name()
  local window = M.get_window_info()

  if not session then
    return nil
  end

  local location_text = session
  if window and window.name then
    location_text = location_text .. ":" .. window.name
  end

  return {
    text = "Jump to tmux: " .. location_text,
    callback = function()
      -- The callback will switch to the session and window
      -- This is useful when the notification is clicked from outside the tmux session
      M.switch_to_session(session)
      if window and window.index then
        M.switch_to_window(window.index)
      end
    end,
  }
end

return M
