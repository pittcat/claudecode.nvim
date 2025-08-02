---@brief [[
--- Claude session management utilities
--- This module provides functionality to list and manage Claude CLI sessions
---@brief ]]

---@module 'claudecode.session_manager'
local M = {}

local logger = require("claudecode.logger")

--- @class SessionInfo
--- @field id string Session ID (UUID)
--- @field summary string Session summary
--- @field modified_time number Last modified timestamp
--- @field created_time number Created timestamp
--- @field git_branch string|nil Git branch
--- @field message_count number Number of messages in session
--- @field file_path string Path to the session file

--- Get Claude config directory path
--- @return string|nil config_dir Path to Claude config directory or nil if not found
local function get_claude_config_dir()
  local claude_config_dir = os.getenv("CLAUDE_CONFIG_DIR")
  if claude_config_dir then
    return claude_config_dir
  end
  
  local home = os.getenv("HOME")
  if home then
    local claude_dir = home .. "/.claude"
    -- Check if the directory exists
    local stat = vim.loop.fs_stat(claude_dir)
    if stat and stat.type == "directory" then
      return claude_dir
    end
  end
  
  return nil
end

--- Parse session file to extract metadata
--- @param file_path string Path to the session .jsonl file
--- @return SessionInfo|nil session_info Parsed session information or nil if failed
local function parse_session_file(file_path)
  local file = io.open(file_path, "r")
  if not file then
    logger.warn("session_manager", "Failed to open session file: " .. file_path)
    return nil
  end
  
  local session_info = {
    id = "",
    summary = "",
    modified_time = 0,
    created_time = 0,
    git_branch = nil,
    message_count = 0,
    file_path = file_path
  }
  
  -- Get file modification time
  local stat = vim.loop.fs_stat(file_path)
  if stat then
    session_info.modified_time = stat.mtime.sec
  end
  
  local line_count = 0
  local first_user_message = nil
  local has_summary = false
  
  for line in file:lines() do
    line_count = line_count + 1
    
    local ok, data = pcall(vim.json.decode, line)
    if ok and data then
      -- Check for summary line (usually first line)
      if data.type == "summary" and data.summary then
        session_info.summary = data.summary
        has_summary = true
      elseif data.sessionId then
        session_info.id = data.sessionId
        if data.timestamp then
          local timestamp = data.timestamp:gsub("Z$", ""):gsub("T", " ")
          -- Convert ISO timestamp to epoch (simplified)
          if session_info.created_time == 0 then
            session_info.created_time = session_info.modified_time
          end
        end
        if data.gitBranch then
          session_info.git_branch = data.gitBranch
        end
        
        -- Extract first meaningful user message as fallback summary
        if not first_user_message and data.type == "user" and data.message and data.message.content and not data.isMeta then
          local content_text = ""
          if type(data.message.content) == "string" then
            content_text = data.message.content
          elseif type(data.message.content) == "table" and data.message.content[1] and data.message.content[1].text then
            content_text = data.message.content[1].text
          end
          
          -- Skip auto-generated messages like caveats and IDE commands
          if content_text and 
             not content_text:find("Caveat:") and 
             not content_text:find("<command%-name>") and
             not content_text:find("DO NOT respond to these messages") and
             #content_text > 10 then
            first_user_message = content_text
          end
        end
      end
    end
  end
  
  -- If no summary found, use first user message or default
  if not has_summary then
    if first_user_message then
      -- Truncate long messages and clean up
      session_info.summary = first_user_message:gsub("\n", " "):sub(1, 100)
      if #first_user_message > 100 then
        session_info.summary = session_info.summary .. "..."
      end
    else
      session_info.summary = "No summary available"
    end
  end
  
  session_info.message_count = line_count
  file:close()
  
  return session_info
end

--- Get list of all Claude sessions from current project directory
--- @return SessionInfo[] sessions List of session information
function M.get_session_list()
  local claude_config_dir = get_claude_config_dir()
  if not claude_config_dir then
    logger.error("session_manager", "Claude config directory not found")
    return {}
  end
  
  local cwd = vim.fn.getcwd()
  
  -- Convert path to Claude projects format (replace / with -)
  -- Claude CLI also converts ".hidden" to "-hidden" (extra dash for dot prefixes)
  local project_path = cwd:gsub("/", "-"):gsub("%-%.([^-]*)", "--%1")
  local projects_dir = claude_config_dir .. "/projects/" .. project_path
  
  local stat = vim.loop.fs_stat(projects_dir)
  if not stat or stat.type ~= "directory" then
    -- Try to find similar directory names in case of naming mismatches
    local claude_projects_dir = claude_config_dir .. "/projects/"
    local projects_handle = vim.loop.fs_scandir(claude_projects_dir)
    local found_alternative = nil
    
    if projects_handle then
      local base_name = project_path:match("[^-]*-[^-]*-[^-]*-[^-]*-(.+)$") -- Extract last part
      if base_name then
        while true do
          local dir_name, dir_type = vim.loop.fs_scandir_next(projects_handle)
          if not dir_name then break end
          
          if dir_type == "directory" then
            -- Try both underscore and hyphen variations
            local base_with_hyphens = base_name:gsub("_", "-")
            local base_with_underscores = base_name:gsub("-", "_")
            
            if dir_name:find(base_with_hyphens, 1, true) or dir_name:find(base_with_underscores, 1, true) then
              found_alternative = claude_projects_dir .. dir_name
              break
            end
          end
        end
      end
    end
    
    if found_alternative then
      projects_dir = found_alternative
      stat = vim.loop.fs_stat(projects_dir)
    end
    
    if not stat or stat.type ~= "directory" then
      return {}
    end
  end
  
  local sessions = {}
  local handle = vim.loop.fs_scandir(projects_dir)
  if handle then
    while true do
      local name, type = vim.loop.fs_scandir_next(handle)
      if not name then break end
      
      if type == "file" and name:match("%.jsonl$") then
        local file_path = projects_dir .. "/" .. name
        local session_info = parse_session_file(file_path)
        if session_info and session_info.id ~= "" then
          table.insert(sessions, session_info)
        end
      end
    end
  end
  
  -- Sort sessions by modification time (newest first)
  table.sort(sessions, function(a, b)
    return a.modified_time > b.modified_time
  end)
  
  return sessions
end

--- Convert timestamp to human-readable relative time
--- @param timestamp number Unix timestamp
--- @return string relative_time Human-readable relative time
local function format_relative_time(timestamp)
  local now = os.time()
  local diff = now - timestamp
  
  if diff < 3600 then -- Less than 1 hour
    local minutes = math.floor(diff / 60)
    if minutes < 1 then
      return "now"
    elseif minutes == 1 then
      return "1m ago"
    else
      return string.format("%dm ago", minutes)
    end
  elseif diff < 86400 then -- Less than 1 day
    local hours = math.floor(diff / 3600)
    if hours == 1 then
      return "1h ago"
    else
      return string.format("%dh ago", hours)
    end
  elseif diff < 604800 then -- Less than 1 week
    local days = math.floor(diff / 86400)
    if days == 1 then
      return "1 day ago"
    else
      return string.format("%d days ago", days)
    end
  elseif diff < 2419200 then -- Less than 4 weeks
    local weeks = math.floor(diff / 604800)
    if weeks == 1 then
      return "1 week ago"
    else
      return string.format("%d weeks ago", weeks)
    end
  else
    local months = math.floor(diff / 2419200)
    if months == 1 then
      return "1 month ago"
    else
      return string.format("%d months ago", months)
    end
  end
end

--- Format session info for display in selection list
--- @param session SessionInfo Session information
--- @return string formatted Formatted string for display
function M.format_session_for_display(session)
  local modified_time = format_relative_time(session.modified_time)
  local created_time = format_relative_time(session.created_time)
  local branch = session.git_branch or "main"
  local summary = session.summary
  
  -- Don't truncate summary in the new UI, let fzf handle it
  return string.format("%-12s %-12s %3d %-15s %s", 
    modified_time, created_time, session.message_count, branch, summary)
end

--- Format session list for vim.ui.select
--- @param sessions SessionInfo[] List of sessions
--- @return string[] formatted List of formatted session strings
--- @return SessionInfo[] sessions Original session list for reference
function M.format_sessions_for_select(sessions)
  if #sessions == 0 then
    return {"No sessions found for current project"}, {}
  end
  
  local formatted = {}
  -- Add header
  table.insert(formatted, string.format("%-12s %-12s %3s %-15s %s", 
    "Modified", "Created", "#", "Git Branch", "Summary"))
  table.insert(formatted, string.rep("-", 100))
  
  for _, session in ipairs(sessions) do
    table.insert(formatted, M.format_session_for_display(session))
  end
  
  return formatted, sessions
end

--- Format sessions for fzf-lua
--- @param sessions SessionInfo[] List of sessions
--- @return table fzf_entries List of entries for fzf-lua
function M.format_sessions_for_fzf(sessions)
  if #sessions == 0 then
    return {}
  end
  
  local entries = {}
  
  for i, session in ipairs(sessions) do
    local modified_time = format_relative_time(session.modified_time)
    local created_time = format_relative_time(session.created_time) 
    local branch = session.git_branch or "main"
    local summary = session.summary
    
    -- Create fzf entry with structured data
    table.insert(entries, {
      -- Display text for fzf
      string.format("%-12s %-12s %3d %-15s %s", 
        modified_time, created_time, session.message_count, branch, summary),
      -- Associated session data
      session = session,
      index = i
    })
  end
  
  return entries
end

return M