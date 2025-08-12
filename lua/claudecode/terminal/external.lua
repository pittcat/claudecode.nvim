--- External terminal provider for Claude Code.
---Launches Claude Code in an external terminal application using a user-specified command.
---@module 'claudecode.terminal.external'

---@type ClaudeCodeTerminalProvider
local M = {}

local logger = require("claudecode.logger")

local jobid = nil
---@type ClaudeCodeTerminalConfig
local config

local function cleanup_state()
  jobid = nil
end

local function is_valid()
  -- For external terminals, we only track if we have a running job
  -- We don't manage terminal windows since they're external
  return jobid and jobid > 0
end

---@param term_config ClaudeCodeTerminalConfig
function M.setup(term_config)
  config = term_config or {}
end

---@param cmd_string string
---@param env_table table
function M.open(cmd_string, env_table)
  if is_valid() then
    -- External terminal is already running, we can't focus it programmatically
    -- Just log that it's already running
    logger.debug("terminal", "External Claude terminal is already running")
    return
  end

  -- Get external terminal command from provider_opts
  local external_cmd = config.provider_opts and config.provider_opts.external_terminal_cmd

  if not external_cmd or external_cmd == "" then
    vim.notify(
      "external_terminal_cmd not configured. Please set terminal.provider_opts.external_terminal_cmd in your config.",
      vim.log.levels.ERROR
    )
    return
  end

  -- Replace %s in the template with the Claude command
  if not external_cmd:find("%%s") then
    vim.notify("external_terminal_cmd must contain '%s' placeholder for the Claude command.", vim.log.levels.ERROR)
    return
  end

  -- Build command by replacing %s with Claude command and splitting
  local full_command = string.format(external_cmd, cmd_string)
  local cmd_parts = vim.split(full_command, " ")

  -- Start the external terminal as a detached process
  jobid = vim.fn.jobstart(cmd_parts, {
    detach = true,
    env = env_table,
    on_exit = function(job_id, exit_code, _)
      vim.schedule(function()
        if job_id == jobid then
          cleanup_state()
        end
      end)
    end,
  })

  if not jobid or jobid <= 0 then
    vim.notify("Failed to start external terminal with command: " .. full_command, vim.log.levels.ERROR)
    cleanup_state()
    return
  end
end

function M.close()
  if is_valid() then
    -- Try to stop the job gracefully
    vim.fn.jobstop(jobid)
    cleanup_state()
  end
end

--- Simple toggle: always start external terminal (can't hide external terminals)
---@param cmd_string string
---@param env_table table
---@param effective_config table
function M.simple_toggle(cmd_string, env_table, effective_config)
  if is_valid() then
    -- External terminal is running, stop it
    M.close()
  else
    -- Start external terminal
    M.open(cmd_string, env_table, effective_config, true)
  end
end

--- Smart focus toggle: same as simple toggle for external terminals
---@param cmd_string string
---@param env_table table
---@param effective_config table
function M.focus_toggle(cmd_string, env_table, effective_config)
  -- For external terminals, focus toggle behaves the same as simple toggle
  -- since we can't detect or control focus of external windows
  M.simple_toggle(cmd_string, env_table, effective_config)
end

--- Legacy toggle function for backward compatibility
---@param cmd_string string
---@param env_table table
---@param effective_config table
function M.toggle(cmd_string, env_table, effective_config)
  M.simple_toggle(cmd_string, env_table, effective_config)
end

---@return number?
function M.get_active_bufnr()
  -- External terminals don't have associated Neovim buffers
  return nil
end

--- No-op function for external terminals since we can't ensure visibility of external windows
function M.ensure_visible() end

---@return boolean
function M.is_available()
  -- Availability is checked by terminal.lua before this provider is selected
  return true
end

---@return table?
function M._get_terminal_for_test()
  -- For testing purposes, return job info if available
  if is_valid() then
    return { jobid = jobid }
  end
  return nil
end

return M
