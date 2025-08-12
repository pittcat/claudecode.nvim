--- Anti-flicker module for terminal window switching
-- This module reduces flicker during rapid window focus changes
local M = {}

local logger = require("claudecode.logger")

-- State tracking
local is_anti_flicker_active = false
local flicker_prevention_timer = nil
local original_settings = {}

--- Apply anti-flicker settings temporarily
local function apply_anti_flicker_settings()
  if is_anti_flicker_active then
    return -- Already active
  end

  logger.debug("anti_flicker", "[ANTI_FLICKER] Activating anti-flicker mode")

  -- Store original settings
  original_settings = {
    lazyredraw = vim.o.lazyredraw,
    ttyfast = vim.o.ttyfast,
    updatetime = vim.o.updatetime,
    timeoutlen = vim.o.timeoutlen,
  }

  -- Apply anti-flicker settings
  vim.o.lazyredraw = true
  vim.o.ttyfast = true
  vim.o.updatetime = 500 -- Increase update time to reduce frequency
  vim.o.timeoutlen = 800 -- Slightly increase timeout

  is_anti_flicker_active = true
end

--- Restore original settings
local function restore_original_settings()
  if not is_anti_flicker_active then
    return -- Not active
  end

  logger.debug("anti_flicker", "[ANTI_FLICKER] Restoring original settings")

  -- Restore settings
  if original_settings.lazyredraw ~= nil then
    vim.o.lazyredraw = original_settings.lazyredraw
  end
  if original_settings.ttyfast ~= nil then
    vim.o.ttyfast = original_settings.ttyfast
  end
  if original_settings.updatetime ~= nil then
    vim.o.updatetime = original_settings.updatetime
  end
  if original_settings.timeoutlen ~= nil then
    vim.o.timeoutlen = original_settings.timeoutlen
  end

  is_anti_flicker_active = false
  original_settings = {}
end

--- Start anti-flicker mode with automatic timeout
--- @param duration_ms number Duration in milliseconds (default: 200)
function M.start_temporary_anti_flicker(duration_ms)
  duration_ms = duration_ms or 200


  apply_anti_flicker_settings()

  -- Cancel existing timer if any
  if flicker_prevention_timer then
    flicker_prevention_timer:stop()
    flicker_prevention_timer:close()
    flicker_prevention_timer = nil
  end

  -- Set up automatic restoration
  flicker_prevention_timer = vim.loop.new_timer()
  flicker_prevention_timer:start(
    duration_ms,
    0,
    vim.schedule_wrap(function()
      restore_original_settings()
      if flicker_prevention_timer then
        flicker_prevention_timer:close()
        flicker_prevention_timer = nil
      end
    end)
  )
end

--- Manually stop anti-flicker mode
function M.stop_anti_flicker()
  if flicker_prevention_timer then
    flicker_prevention_timer:stop()
    flicker_prevention_timer:close()
    flicker_prevention_timer = nil
  end
  restore_original_settings()
end

--- Check if anti-flicker mode is active
--- @return boolean
function M.is_active()
  return is_anti_flicker_active
end

--- Handle rapid window switching by extending anti-flicker period
function M.handle_rapid_switching()
  if is_anti_flicker_active then
    -- Extend the anti-flicker period if we're already in it
    logger.debug("anti_flicker", "[ANTI_FLICKER] Extending anti-flicker period due to rapid switching")
    M.start_temporary_anti_flicker(300) -- Extend to 300ms
  else
    -- Start anti-flicker mode for rapid switching
    logger.debug("anti_flicker", "[ANTI_FLICKER] Starting anti-flicker for rapid switching")
    M.start_temporary_anti_flicker(200)
  end
end

--- Apply immediate visual optimizations for terminal window
--- @param win_id number Window ID
--- @param buf_id number Buffer ID
function M.optimize_terminal_window(win_id, buf_id)
  if not win_id or not vim.api.nvim_win_is_valid(win_id) then
    return
  end

  if not buf_id or not vim.api.nvim_buf_is_valid(buf_id) then
    return
  end

  -- Apply optimizations in protected calls to avoid errors
  local optimizations = {
    -- Window options
    function()
      vim.api.nvim_win_set_option(win_id, "number", false)
    end,
    function()
      vim.api.nvim_win_set_option(win_id, "relativenumber", false)
    end,
    function()
      vim.api.nvim_win_set_option(win_id, "cursorline", false)
    end,
    function()
      vim.api.nvim_win_set_option(win_id, "cursorcolumn", false)
    end,
    function()
      vim.api.nvim_win_set_option(win_id, "signcolumn", "no")
    end,
    function()
      vim.api.nvim_win_set_option(win_id, "foldcolumn", "0")
    end,
    function()
      vim.api.nvim_win_set_option(win_id, "colorcolumn", "")
    end,

    -- Buffer options
    function()
      vim.api.nvim_buf_set_option(buf_id, "cursorline", false)
    end,
    function()
      vim.api.nvim_buf_set_option(buf_id, "number", false)
    end,
    function()
      vim.api.nvim_buf_set_option(buf_id, "relativenumber", false)
    end,
  }

  for _, optimization in ipairs(optimizations) do
    pcall(optimization)
  end

  logger.debug("anti_flicker", "[ANTI_FLICKER] Applied terminal window optimizations")
end

return M
