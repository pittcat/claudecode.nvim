--- Focus change debugging module
-- This module helps track window focus changes that might cause flickering
local M = {}

local logger = require("claudecode.logger")
local is_monitoring = false
local autocmd_group = nil

--- Start monitoring window focus changes
function M.start_monitoring()
  if is_monitoring then
    return
  end
  
  logger.debug("focus_debug", "[FOCUS_DEBUG] Starting focus change monitoring")
  
  -- Create autocmd group
  autocmd_group = vim.api.nvim_create_augroup("ClaudeCodeFocusDebug", { clear = true })
  
  -- Monitor window enter events
  vim.api.nvim_create_autocmd("WinEnter", {
    group = autocmd_group,
    callback = function()
      local current_win = vim.api.nvim_get_current_win()
      local current_buf = vim.api.nvim_win_get_buf(current_win)
      local buftype = vim.api.nvim_buf_get_option(current_buf, "buftype")
      local filetype = vim.api.nvim_buf_get_option(current_buf, "filetype")
      
      logger.debug("focus_debug", "[FOCUS_DEBUG] WinEnter - win:", current_win, "buf:", current_buf, "buftype:", buftype, "filetype:", filetype)
      
      -- Special attention to terminal windows
      if buftype == "terminal" then
        logger.debug("focus_debug", "[FOCUS_DEBUG] Entering TERMINAL window - checking for flicker triggers")
        
        -- Check if this might be a ClaudeCode terminal
        local buf_name = vim.api.nvim_buf_get_name(current_buf)
        if buf_name:match("claude") then
          logger.debug("focus_debug", "[FOCUS_DEBUG] This appears to be a ClaudeCode terminal")
        end
        
        -- Monitor immediate visual changes
        vim.schedule(function()
          logger.debug("focus_debug", "[FOCUS_DEBUG] Terminal focus change scheduled callback executed")
        end)
      end
    end
  })
  
  -- Monitor window leave events  
  vim.api.nvim_create_autocmd("WinLeave", {
    group = autocmd_group,
    callback = function()
      local leaving_win = vim.api.nvim_get_current_win()
      local leaving_buf = vim.api.nvim_win_get_buf(leaving_win)
      local buftype = vim.api.nvim_buf_get_option(leaving_buf, "buftype")
      
      logger.debug("focus_debug", "[FOCUS_DEBUG] WinLeave - win:", leaving_win, "buf:", leaving_buf, "buftype:", buftype)
    end
  })
  
  -- Monitor buffer enter events (can trigger visual updates)
  vim.api.nvim_create_autocmd("BufEnter", {
    group = autocmd_group,
    callback = function()
      local current_buf = vim.api.nvim_get_current_buf()
      local buftype = vim.api.nvim_buf_get_option(current_buf, "buftype")
      
      if buftype == "terminal" then
        logger.debug("focus_debug", "[FOCUS_DEBUG] BufEnter on terminal buffer:", current_buf)
        
        -- This is where redraw might be triggered
        local redraw_start = vim.loop.hrtime()
        vim.schedule(function()
          local redraw_end = vim.loop.hrtime()
          logger.debug("focus_debug", "[FOCUS_DEBUG] BufEnter schedule callback - time:", (redraw_end - redraw_start) / 1000000, "ms")
        end)
      end
    end
  })
  
  -- Monitor cursor movements that might trigger redraws
  vim.api.nvim_create_autocmd("CursorMoved", {
    group = autocmd_group,
    callback = function()
      local current_buf = vim.api.nvim_get_current_buf()
      local buftype = vim.api.nvim_buf_get_option(current_buf, "buftype")
      
      if buftype == "terminal" then
        logger.debug("focus_debug", "[FOCUS_DEBUG] CursorMoved in terminal buffer:", current_buf)
      end
    end
  })
  
  is_monitoring = true
end

--- Stop monitoring window focus changes
function M.stop_monitoring()
  if not is_monitoring then
    return
  end
  
  logger.debug("focus_debug", "[FOCUS_DEBUG] Stopping focus change monitoring")
  
  if autocmd_group then
    vim.api.nvim_del_augroup_by_id(autocmd_group)
    autocmd_group = nil
  end
  
  is_monitoring = false
end

--- Check if monitoring is active
function M.is_monitoring()
  return is_monitoring
end

return M