--- Performance optimization module for claudecode.nvim
-- Provides functions to reduce screen flickering and improve terminal performance
local M = {}

--- Apply performance optimizations to reduce screen flickering
-- @param opts table Optional configuration overrides
function M.setup_anti_flicker_config(opts)
  opts = opts or {}

  -- Default anti-flicker settings
  local config = {
    -- Reduce Neovim update frequency
    updatetime = opts.updatetime or 300, -- Increased from default 250ms

    -- Disable some visual features that cause redraws
    lazyredraw = opts.lazyredraw ~= false, -- Default true, can be disabled

    -- Terminal-specific optimizations
    terminal = {
      scrollback = opts.terminal_scrollback or 1000, -- Reduced from default 10000
      redraw_throttle_ms = opts.redraw_throttle_ms or 200, -- Minimum time between redraws
      disable_auto_redraw = opts.disable_auto_redraw or false, -- Completely disable auto-redraw
    },

    -- Syntax highlighting optimizations
    syntax = {
      maxcol = opts.syntax_maxcol or 200, -- Limit syntax highlighting column
      disable_in_large_files = opts.disable_syntax_large_files ~= false,
      large_file_threshold = opts.large_file_threshold or 5000, -- Lines
    },
  }

  -- Apply Neovim-wide optimizations
  vim.opt.updatetime = config.updatetime
  vim.opt.lazyredraw = config.lazyredraw
  vim.opt.synmaxcol = config.syntax.maxcol

  -- Set up autocmd for large file detection
  if config.syntax.disable_in_large_files then
    vim.api.nvim_create_autocmd("BufRead", {
      group = vim.api.nvim_create_augroup("ClaudeCodePerformance", { clear = true }),
      callback = function()
        local lines = vim.fn.line("$")
        if lines > config.syntax.large_file_threshold then
          -- Disable syntax highlighting for large files
          vim.cmd("syntax off")
          if vim.treesitter then
            pcall(vim.cmd, "TSBufDisable highlight")
          end
        end
      end,
    })
  end

  -- Return config for further customization
  return config
end

--- Create optimized terminal autocmds to reduce flickering
-- @param bufnr number Terminal buffer number
-- @param redraw_throttle_ms number Minimum milliseconds between redraws
function M.setup_terminal_anti_flicker(bufnr, redraw_throttle_ms)
  redraw_throttle_ms = redraw_throttle_ms or 200

  local last_redraw = 0

  -- Remove any existing autocmds for this buffer
  pcall(vim.api.nvim_clear_autocmds, {
    group = "ClaudeCodeTerminalFlicker",
    buffer = bufnr,
  })

  -- Create new autocmd group
  local group = vim.api.nvim_create_augroup("ClaudeCodeTerminalFlicker", { clear = false })

  -- Terminal-specific optimizations
  vim.api.nvim_create_autocmd("TermOpen", {
    group = group,
    buffer = bufnr,
    callback = function()
      -- Disable visual elements that cause redraws
      vim.opt_local.number = false
      vim.opt_local.relativenumber = false
      vim.opt_local.cursorline = false
      vim.opt_local.signcolumn = "no"
      vim.opt_local.foldcolumn = "0"
      vim.opt_local.colorcolumn = ""

      -- Disable some events that trigger redraws
      vim.opt_local.eventignore = "FocusGained,FocusLost,CursorHold,CursorHoldI"
    end,
  })

  -- Throttled redraw on buffer enter
  vim.api.nvim_create_autocmd("BufEnter", {
    group = group,
    buffer = bufnr,
    callback = function()
      local now = vim.loop.hrtime() / 1000000 -- Convert to milliseconds
      if now - last_redraw > redraw_throttle_ms then
        vim.schedule(function()
          if vim.api.nvim_get_current_buf() == bufnr then
            -- Only redraw if there are visible corruption signs
            local lines = vim.api.nvim_buf_get_lines(bufnr, -5, -1, false)
            local needs_redraw = false

            for _, line in ipairs(lines) do
              -- Check for incomplete ANSI escape sequences
              if line:match("\27%[[0-9;]*$") or line:match("\27%[$") then
                needs_redraw = true
                break
              end
            end

            if needs_redraw then
              vim.cmd("redraw") -- Use redraw instead of redraw! for less aggressive refresh
              last_redraw = now
            end
          end
        end)
      end
    end,
  })
end

--- Get recommended performance settings based on terminal emulator
-- @return table Performance recommendations
function M.get_terminal_recommendations()
  local term = os.getenv("TERM_PROGRAM") or os.getenv("TERM")

  local recommendations = {
    general = {
      scrollback = 1000,
      redraw_throttle_ms = 200,
      disable_auto_redraw = false,
    },
  }

  -- Terminal-specific optimizations
  if term == "iTerm.app" then
    recommendations.iterm = {
      scrollback = 2000, -- iTerm handles larger scrollback better
      redraw_throttle_ms = 150,
    }
  elseif term == "Apple_Terminal" then
    recommendations.apple_terminal = {
      scrollback = 500, -- Apple Terminal is slower with large scrollback
      redraw_throttle_ms = 300,
    }
  elseif term:match("kitty") then
    recommendations.kitty = {
      scrollback = 2000, -- Kitty is optimized for performance
      redraw_throttle_ms = 100,
    }
  elseif term:match("alacritty") then
    recommendations.alacritty = {
      scrollback = 1500, -- Alacritty has good performance
      redraw_throttle_ms = 150,
    }
  end

  return recommendations
end

--- Apply emergency anti-flicker mode (disables most visual features)
function M.emergency_anti_flicker_mode()
  -- Disable all non-essential visual features
  vim.opt.lazyredraw = true
  vim.opt.ttyfast = true
  vim.opt.updatetime = 1000
  vim.opt.synmaxcol = 100

  -- Disable cursor line and column highlighting
  vim.opt.cursorline = false
  vim.opt.cursorcolumn = false

  -- Disable some events
  vim.opt.eventignore = "FocusGained,FocusLost,CursorHold,CursorHoldI,WinScrolled"

  -- Show notification
  vim.notify("Emergency anti-flicker mode enabled. Some visual features disabled.", vim.log.levels.INFO)
end

--- Restore normal visual mode
function M.restore_normal_mode()
  -- Restore normal settings
  vim.opt.lazyredraw = false
  vim.opt.updatetime = 250
  vim.opt.synmaxcol = 3000
  vim.opt.eventignore = ""

  vim.notify("Normal visual mode restored.", vim.log.levels.INFO)
end

return M
