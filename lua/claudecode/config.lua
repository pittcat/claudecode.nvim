--- Manages configuration for the Claude Code Neovim integration.
-- Provides default settings, validation, and application of user-defined configurations.
local M = {}

M.defaults = {
  port_range = { min = 10000, max = 65535 },
  auto_start = true,
  terminal_cmd = nil,
  bin_path = "claude",
  log_level = "info",
  track_selection = true,
  visual_demotion_delay_ms = 50, -- Milliseconds to wait before demoting a visual selection
  connection_wait_delay = 200, -- Milliseconds to wait after connection before sending queued @ mentions
  connection_timeout = 10000, -- Maximum time to wait for Claude Code to connect (milliseconds)
  queue_timeout = 5000, -- Maximum time to keep @ mentions in queue (milliseconds)
  diff_opts = {
    auto_close_on_accept = true,
    show_diff_stats = true,
    vertical_split = true,
    open_in_current_tab = true, -- Use current tab instead of creating new tab
  },
  notification = {
    enabled = true,
    sound = "Glass",
    include_project_path = true,
    title_prefix = "Claude Code",
  },
  models = {
    { name = "Claude Opus 4 (Latest)", value = "opus" },
    { name = "Claude Sonnet 4 (Latest)", value = "sonnet" },
  },
}

--- Validates the provided configuration table.
-- @param config table The configuration table to validate.
-- @return boolean true if the configuration is valid.
-- @error string if any configuration option is invalid.
function M.validate(config)
  assert(
    type(config.port_range) == "table"
      and type(config.port_range.min) == "number"
      and type(config.port_range.max) == "number"
      and config.port_range.min > 0
      and config.port_range.max <= 65535
      and config.port_range.min <= config.port_range.max,
    "Invalid port range"
  )

  assert(type(config.auto_start) == "boolean", "auto_start must be a boolean")

  assert(config.terminal_cmd == nil or type(config.terminal_cmd) == "string", "terminal_cmd must be nil or a string")

  assert(config.bin_path == nil or type(config.bin_path) == "string", "bin_path must be nil or a string")

  local valid_log_levels = { "trace", "debug", "info", "warn", "error" }
  local is_valid_log_level = false
  for _, level in ipairs(valid_log_levels) do
    if config.log_level == level then
      is_valid_log_level = true
      break
    end
  end
  assert(is_valid_log_level, "log_level must be one of: " .. table.concat(valid_log_levels, ", "))

  assert(type(config.track_selection) == "boolean", "track_selection must be a boolean")

  assert(
    type(config.visual_demotion_delay_ms) == "number" and config.visual_demotion_delay_ms >= 0,
    "visual_demotion_delay_ms must be a non-negative number"
  )

  assert(
    type(config.connection_wait_delay) == "number" and config.connection_wait_delay >= 0,
    "connection_wait_delay must be a non-negative number"
  )

  assert(
    type(config.connection_timeout) == "number" and config.connection_timeout > 0,
    "connection_timeout must be a positive number"
  )

  assert(type(config.queue_timeout) == "number" and config.queue_timeout > 0, "queue_timeout must be a positive number")

  assert(type(config.diff_opts) == "table", "diff_opts must be a table")
  assert(type(config.diff_opts.auto_close_on_accept) == "boolean", "diff_opts.auto_close_on_accept must be a boolean")
  assert(type(config.diff_opts.show_diff_stats) == "boolean", "diff_opts.show_diff_stats must be a boolean")
  assert(type(config.diff_opts.vertical_split) == "boolean", "diff_opts.vertical_split must be a boolean")
  assert(type(config.diff_opts.open_in_current_tab) == "boolean", "diff_opts.open_in_current_tab must be a boolean")

  assert(type(config.notification) == "table", "notification must be a table")
  assert(type(config.notification.enabled) == "boolean", "notification.enabled must be a boolean")
  assert(type(config.notification.sound) == "string", "notification.sound must be a string")
  assert(type(config.notification.include_project_path) == "boolean", "notification.include_project_path must be a boolean")
  assert(type(config.notification.title_prefix) == "string", "notification.title_prefix must be a string")

  -- Validate models
  assert(type(config.models) == "table", "models must be a table")
  assert(#config.models > 0, "models must not be empty")

  for i, model in ipairs(config.models) do
    assert(type(model) == "table", "models[" .. i .. "] must be a table")
    assert(type(model.name) == "string" and model.name ~= "", "models[" .. i .. "].name must be a non-empty string")
    assert(type(model.value) == "string" and model.value ~= "", "models[" .. i .. "].value must be a non-empty string")
  end


  return true
end

--- Applies user configuration on top of default settings and validates the result.
-- @param user_config table|nil The user-provided configuration table.
-- @return table The final, validated configuration table.
function M.apply(user_config)
  local config = vim.deepcopy(M.defaults)

  if user_config then
    config = vim.tbl_deep_extend("force", config, user_config)
  end

  M.validate(config)

  return config
end

return M
