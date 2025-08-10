---@brief [[
--- Manages configuration for the Claude Code Neovim integration.
--- Provides default settings, validation, and application of user-defined configurations.
---@brief ]]
---@module 'claudecode.config'

local M = {}

---@type ClaudeCodeConfig
M.defaults = {
  port_range = { min = 10000, max = 65535 },
  auto_start = true,
  terminal_cmd = nil,
  env = {}, -- Custom environment variables for Claude terminal
  log_level = "info",
  track_selection = true,
  visual_demotion_delay_ms = 50, -- Milliseconds to wait before demoting a visual selection
  connection_wait_delay = 200, -- Milliseconds to wait after connection before sending queued @ mentions
  connection_timeout = 10000, -- Maximum time to wait for Claude Code to connect (milliseconds)
  queue_timeout = 5000, -- Maximum time to keep @ mentions in queue (milliseconds)
  diff_opts = {
    layout = "vertical",
    open_in_new_tab = false, -- Open diff in a new tab (false = use current tab)
    keep_terminal_focus = false, -- If true, moves focus back to terminal after diff opens
    hide_terminal_in_new_tab = false, -- If true and opening in a new tab, do not show Claude terminal there
    on_new_file_reject = "keep_empty", -- "keep_empty" leaves an empty buffer; "close_window" closes the placeholder split
  },
  models = {
    { name = "Claude Opus 4.1 (Latest)", value = "opus" },
    { name = "Claude Sonnet 4 (Latest)", value = "sonnet" },
    { name = "Claude Haiku 3.5 (Latest)", value = "haiku" },
  },
  terminal = nil, -- Will be lazy-loaded to avoid circular dependency
}

---Validates the provided configuration table.
---Throws an error if any validation fails.
---@param config table The configuration table to validate.
---@return boolean true if the configuration is valid.
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

  -- Validate terminal config
  assert(type(config.terminal) == "table", "terminal must be a table")

  -- Validate provider_opts if present
  if config.terminal.provider_opts then
    assert(type(config.terminal.provider_opts) == "table", "terminal.provider_opts must be a table")

    -- Validate external_terminal_cmd in provider_opts
    if config.terminal.provider_opts.external_terminal_cmd then
      assert(
        type(config.terminal.provider_opts.external_terminal_cmd) == "string",
        "terminal.provider_opts.external_terminal_cmd must be a string"
      )
      if config.terminal.provider_opts.external_terminal_cmd ~= "" then
        assert(
          config.terminal.provider_opts.external_terminal_cmd:find("%%s"),
          "terminal.provider_opts.external_terminal_cmd must contain '%s' placeholder for the Claude command"
        )
      end
    end
  end

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
  assert(
    config.diff_opts.layout == "vertical" or config.diff_opts.layout == "horizontal",
    "diff_opts.layout must be 'vertical' or 'horizontal'"
  )
  assert(type(config.diff_opts.open_in_new_tab) == "boolean", "diff_opts.open_in_new_tab must be a boolean")
  assert(type(config.diff_opts.keep_terminal_focus) == "boolean", "diff_opts.keep_terminal_focus must be a boolean")
  assert(
    type(config.diff_opts.hide_terminal_in_new_tab) == "boolean",
    "diff_opts.hide_terminal_in_new_tab must be a boolean"
  )
  assert(
    type(config.diff_opts.on_new_file_reject) == "string"
      and (config.diff_opts.on_new_file_reject == "keep_empty" or config.diff_opts.on_new_file_reject == "close_window"),
    "diff_opts.on_new_file_reject must be 'keep_empty' or 'close_window'"
  )

  -- Validate env
  assert(type(config.env) == "table", "env must be a table")
  for key, value in pairs(config.env) do
    assert(type(key) == "string", "env keys must be strings")
    assert(type(value) == "string", "env values must be strings")
  end

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

---Applies user configuration on top of default settings and validates the result.
---@param user_config table|nil The user-provided configuration table.
---@return ClaudeCodeConfig config The final, validated configuration table.
function M.apply(user_config)
  local config = vim.deepcopy(M.defaults)

  -- Lazy-load terminal defaults to avoid circular dependency
  if config.terminal == nil then
    local terminal_ok, terminal_module = pcall(require, "claudecode.terminal")
    if terminal_ok and terminal_module.defaults then
      config.terminal = terminal_module.defaults
    end
  end

  if user_config then
    -- Use vim.tbl_deep_extend if available, otherwise simple merge
    if vim.tbl_deep_extend then
      config = vim.tbl_deep_extend("force", config, user_config)
    else
      -- Simple fallback for testing environment
      for k, v in pairs(user_config) do
        config[k] = v
      end
    end
  end

  M.validate(config)

  return config
end

return M
