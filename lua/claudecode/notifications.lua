--- macOS notification system for Claude Code
local M = {}

local config = require("claudecode.config")
local logger = require("claudecode.logger")

--- Check if the system supports osascript (macOS)
-- @return boolean true if osascript is available
local function is_macos()
  return vim.fn.has("mac") == 1 or vim.fn.has("macunix") == 1
end

--- Send a macOS notification using osascript
-- @param title string The notification title
-- @param message string The notification message
-- @param subtitle string|nil Optional subtitle
-- @param play_sound boolean Whether to play a sound
-- @param sound_file string|nil Path to sound file
local function send_macos_notification(title, message, subtitle, play_sound, sound_file)
  if not is_macos() then
    logger.debug("macOS notifications not supported on this platform")
    return
  end

  local cmd = string.format("osascript -e 'display notification \"%s\" with title \"%s\"", message, title)
  
  if subtitle then
    cmd = cmd .. string.format(" subtitle \"%s\"", subtitle)
  end
  
  cmd = cmd .. "'"

  -- Send notification immediately, then schedule sound asynchronously
  local handle = io.popen(cmd)
  if handle then
    handle:close()
    logger.debug("Notification sent: " .. message)
  else
    logger.warn("Failed to send notification: " .. message)
  end
  
  -- Play sound asynchronously to avoid blocking
  if play_sound and sound_file then
    vim.schedule(function()
      local sound_cmd = string.format("afplay '%s'", sound_file)
      local sound_handle = io.popen(sound_cmd)
      if sound_handle then
        sound_handle:close()
        logger.debug("Sound played: " .. sound_file)
      end
    end)
  end
end

--- Send a notification based on type and current configuration
-- @param notification_type string Type of notification: "completion", "confirmation", "error", "file_saved", "diff_accepted", "diff_rejected"
-- @param custom_message string|nil Optional custom message to override default
function M.notify(notification_type, custom_message)
  local current_config = config.apply()
  
  if not current_config.notifications.enabled then
    return
  end

  local should_notify = false
  if notification_type == "completion" and current_config.notifications.on_completion then
    should_notify = true
  elseif notification_type == "confirmation" and current_config.notifications.on_confirmation then
    should_notify = true
  elseif notification_type == "error" and current_config.notifications.on_error then
    should_notify = true
  elseif notification_type:match("^(file_saved|diff_accepted|diff_rejected)$") and current_config.notifications.on_completion then
    should_notify = true
  end

  if not should_notify then
    return
  end

  local message = custom_message or current_config.notifications.messages[notification_type] or notification_type
  local title = current_config.notifications.title
  local play_sound = current_config.notifications.sound
  local sound_file = current_config.notifications.sound_file
  
  send_macos_notification(title, message, nil, play_sound, sound_file)
end

--- Convenience functions for common notification types
function M.completion(message)
  M.notify("completion", message)
end

function M.confirmation(message)
  M.notify("confirmation", message)
end

function M.error(message)
  M.notify("error", message)
end

return M