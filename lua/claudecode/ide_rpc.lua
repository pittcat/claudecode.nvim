--- IDE RPC Client for ClaudeIsland integration
--- Communicates with ClaudeIsland app via Unix domain socket
--- @module 'claudecode.ide_rpc'

local M = {}

local logger = require("claudecode.logger")

--- RPC client state
---@class IDERPCState
---@field socket_path string Path to the Unix domain socket
---@field connected boolean Whether the client is connected
local state = {
  socket_path = nil,
  connected = false,
}

--- Initialize the IDE RPC client
---@return boolean success Whether initialization was successful
function M.setup()
  -- Determine socket path (same as server)
  local runtime_dir = vim.env.XDG_RUNTIME_DIR or "/tmp"
  state.socket_path = runtime_dir .. "/claude-island-ide.sock"

  return true
end

--- Check if ClaudeIsland is available
---@return boolean available Whether ClaudeIsland RPC server is available
function M.is_available()
  if not state.socket_path then
    return false
  end

  -- Check if socket file exists
  local stat = vim.loop.fs_stat(state.socket_path)
  return stat ~= nil and stat.type == "socket"
end

--- Send a request to ClaudeIsland
---@param request table The request to send
---@param callback function? Optional callback for response
---@return boolean success Whether the request was sent successfully
function M.send_request(request, callback)
  if not M.is_available() then
    return false
  end

  -- Create socket connection
  local socket = vim.loop.new_pipe(false)
  if not socket then
    return false
  end

  -- Connect to server
  socket:connect(state.socket_path, function(err)
    if err then
      socket:close()
      if callback then
        callback(false, "Connection failed: " .. err)
      end
      return
    end

    -- Encode request as JSON
    local ok, json = pcall(vim.json.encode, request)
    if not ok then
      socket:close()
      if callback then
        callback(false, "Encoding failed")
      end
      return
    end

    -- Send request
    socket:write(json, function(write_err)
      if write_err then
        socket:close()
        if callback then
          callback(false, "Write failed: " .. write_err)
        end
        return
      end

      -- Read response
      local response_data = ""
      socket:read_start(function(read_err, chunk)
        if read_err then
          socket:close()
          if callback then
            callback(false, "Read failed: " .. read_err)
          end
          return
        end

        if chunk then
          response_data = response_data .. chunk
        else
          -- EOF - parse response
          socket:read_stop()
          socket:close()

          local decode_ok, response = pcall(vim.json.decode, response_data)
          if not decode_ok then
            if callback then
              callback(false, "Decode failed")
            end
            return
          end

          if callback then
            vim.schedule(function()
              callback(true, response)
            end)
          end
        end
      end)
    end)
  end)

  return true
end

--- Send an @ mention to ClaudeIsland
---@param file_path string The file path to mention
---@param session_id string? Optional session ID to target
---@param line_start number? Optional start line
---@param line_end number? Optional end line
---@param callback function? Optional callback for response
---@return boolean success Whether the request was sent
function M.send_at_mention(file_path, session_id, line_start, line_end, callback)
  local request = {
    method = "at_mention",
    session_id = session_id,
    file_path = file_path,
    line_start = line_start,
    line_end = line_end,
  }

  return M.send_request(request, function(success, response)
    if success and response and response.success then
      if callback then
        callback(true, response)
      end
    else
      local error_msg = response and response.message or "Unknown error"
      if callback then
        callback(false, error_msg)
      end
    end
  end)
end

--- Send a command to Claude session
---@param content string The command content
---@param session_id string? Optional session ID to target
---@param callback function? Optional callback for response
---@return boolean success Whether the request was sent
function M.send_command(content, session_id, callback)
  local request = {
    method = "send_command",
    session_id = session_id,
    content = content,
  }

  return M.send_request(request, callback)
end

--- Get list of Claude sessions
---@param callback function Callback to receive session list
---@return boolean success Whether the request was sent
function M.get_sessions(callback)
  local request = {
    method = "get_sessions",
  }

  return M.send_request(request, function(success, response)
    if success and response and response.success then
      local sessions = response.data and response.data.sessions or {}
      if callback then
        vim.schedule(function()
          callback(true, sessions)
        end)
      end
    else
      if callback then
        vim.schedule(function()
          callback(false, {})
        end)
      end
    end
  end)
end

--- Ping ClaudeIsland to check if it's alive
---@param callback function? Optional callback for response
---@return boolean success Whether the request was sent
function M.ping(callback)
  local request = {
    method = "ping",
  }

  return M.send_request(request, callback)
end

return M
