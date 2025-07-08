--- Tool implementation for saving a document.

--- Handles the saveDocument tool invocation.
-- Saves the specified file (buffer).
-- @param params table The input parameters for the tool.
-- @field params.filePath string Path to the file to save.
-- @return table A table with a message indicating success.
-- @error table A table with code, message, and data for JSON-RPC error if failed.
local function handler(params)
  if not params.filePath then
    error({ code = -32602, message = "Invalid params", data = "Missing filePath parameter" })
  end

  local bufnr = vim.fn.bufnr(params.filePath)

  if bufnr == -1 then
    error({
      code = -32000,
      message = "File operation error",
      data = "File not open in editor: " .. params.filePath,
    })
  end

  local success, err = pcall(vim.api.nvim_buf_call, bufnr, function()
    vim.cmd("write")
  end)

  if not success then
    error({
      code = -32000,
      message = "File operation error",
      data = "Failed to save file " .. params.filePath .. ": " .. tostring(err),
    })
  end

  -- Refresh buffers after successful save to ensure all views are synchronized
  local utils = require("claudecode.utils")
  utils.refresh_buffers(params.filePath)

  return { message = "File saved: " .. params.filePath }
end

return {
  name = "saveDocument",
  schema = nil, -- Internal tool
  handler = handler,
}
