--- Shared utility functions for claudecode.nvim
-- @module claudecode.utils

local M = {}

local logger = require("claudecode.logger")

--- Normalizes focus parameter to default to true for backward compatibility
--- @param focus boolean|nil The focus parameter
--- @return boolean Normalized focus value
function M.normalize_focus(focus)
  return focus == nil and true or focus
end

--- Safely refresh a buffer from disk if it's not modified
--- @param bufnr number Buffer number to refresh
--- @param cursor_pos table|nil Optional cursor position to restore {row, col}
--- @return boolean success Whether the buffer was refreshed
function M.safe_refresh_buffer(bufnr, cursor_pos)
  if not vim.api.nvim_buf_is_valid(bufnr) then
    logger.warn("utils", "Cannot refresh invalid buffer:", bufnr)
    return false
  end

  local modified = vim.api.nvim_buf_get_option(bufnr, "modified")
  if modified then
    logger.debug("utils", "Skipping refresh of modified buffer:", vim.api.nvim_buf_get_name(bufnr))
    return false
  end

  local success, err = pcall(function()
    -- Try to find a window displaying this buffer for proper context
    local win_id = nil
    for _, win in ipairs(vim.api.nvim_list_wins()) do
      if vim.api.nvim_win_get_buf(win) == bufnr then
        win_id = win
        break
      end
    end

    if win_id then
      vim.api.nvim_win_call(win_id, function()
        vim.cmd("edit")
        -- Restore cursor position if provided
        if cursor_pos then
          pcall(vim.api.nvim_win_set_cursor, win_id, cursor_pos)
        end
      end)
    else
      vim.api.nvim_buf_call(bufnr, function()
        vim.cmd("edit")
      end)
    end
  end)

  if not success then
    logger.error("utils", "Failed to refresh buffer:", vim.api.nvim_buf_get_name(bufnr), "Error:", err)
    return false
  end

  logger.debug("utils", "Successfully refreshed buffer:", vim.api.nvim_buf_get_name(bufnr))
  return true
end

--- Reload all buffers for a specific file path
--- @param file_path string Path to the file whose buffers should be reloaded
--- @param cursor_pos table|nil Optional cursor position to restore {row, col}
--- @return number count Number of buffers reloaded
function M.reload_file_buffers(file_path, cursor_pos)
  logger.debug("utils", "Reloading buffers for file:", file_path, cursor_pos and "(restoring cursor)" or "")

  local reloaded_count = 0
  -- Find and reload any open buffers for this file
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_valid(buf) then
      local buf_name = vim.api.nvim_buf_get_name(buf)

      -- Simple string match - if buffer name matches the file path
      if buf_name == file_path then
        if M.safe_refresh_buffer(buf, cursor_pos) then
          reloaded_count = reloaded_count + 1
        end
      end
    end
  end

  logger.debug("utils", "Completed buffer reload - reloaded", reloaded_count, "buffers for file:", file_path)
  return reloaded_count
end

--- Trigger buffer refresh using checktime and optional file-specific reload
--- @param file_path string|nil Optional specific file path to reload buffers for
--- @param cursor_pos table|nil Optional cursor position to restore {row, col}
--- @return boolean success Whether the refresh was successful
function M.refresh_buffers(file_path, cursor_pos)
  local success = true
  local refreshed_count = 0

  -- First, trigger global checktime to detect external changes
  local checktime_success, checktime_err = pcall(function()
    vim.cmd.checktime()
  end)

  if not checktime_success then
    logger.error("utils", "Failed to run checktime:", checktime_err)
    success = false
  else
    logger.debug("utils", "Successfully ran checktime")
  end

  -- If a specific file path is provided, also reload those buffers
  if file_path then
    refreshed_count = M.reload_file_buffers(file_path, cursor_pos)
  end

  -- Schedule a notification about refreshed buffers
  if refreshed_count > 0 then
    vim.schedule(function()
      logger.info("utils", "Refreshed " .. refreshed_count .. " buffer(s)" .. (file_path and " for " .. file_path or ""))
    end)
  end

  return success
end

return M
