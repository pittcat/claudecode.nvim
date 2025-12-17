-- luacheck: globals expect
require("tests.busted_setup")

describe("client close race condition", function()
  local client_manager = require("claudecode.server.client")

  -- Create a stateful mock TCP handle for race condition testing
  local function create_mock_tcp_handle()
    local handle = {
      _is_closing = false,
      _write_callbacks = {},
      write = function(self, data, callback)
        table.insert(self._write_callbacks, callback)
        return true
      end,
      close = function(self)
        if self._is_closing then
          error("handle is already closing")
        end
        self._is_closing = true
      end,
      is_closing = function(self)
        return self._is_closing
      end,
    }
    return handle
  end

  it("should not raise 'handle is already closing' on close", function()
    local tcp_handle = create_mock_tcp_handle()
    local client = client_manager.create_client(tcp_handle)

    -- Simulate handshake complete
    client.handshake_complete = true
    client.state = "connected"

    -- Call close_client which should set state to closing
    client_manager.close_client(client, 1000, "Normal closure")

    -- Verify state is set to closing
    expect(client.state).to_be("closing")

    -- Simulate write callback execution (this is where the race condition would occur)
    if #tcp_handle._write_callbacks > 0 then
      local callback = tcp_handle._write_callbacks[1]
      -- This should not raise an error now because we added is_closing() check
      callback()
    end

    -- Verify final state
    expect(client.state).to_be("closed")
    expect(tcp_handle:is_closing()).to_be_true()
  end)

  it("should handle multiple simultaneous close attempts without error", function()
    local tcp_handle = create_mock_tcp_handle()
    local client = client_manager.create_client(tcp_handle)

    client.handshake_complete = true
    client.state = "connected"

    -- First close attempt
    client_manager.close_client(client, 1000, "First closure")
    expect(client.state).to_be("closing")

    -- Second close attempt should be ignored (already closing)
    -- This should not raise an error
    client_manager.close_client(client, 1000, "Second closure")
    expect(client.state).to_be("closing")

    -- Execute the write callback
    if #tcp_handle._write_callbacks > 0 then
      local callback = tcp_handle._write_callbacks[1]
      callback() -- Should not error
    end

    expect(client.state).to_be("closed")
  end)

  it("should handle close on non-handshake-complete connection safely", function()
    local tcp_handle = create_mock_tcp_handle()
    local client = client_manager.create_client(tcp_handle)

    -- Connection not yet established
    client.handshake_complete = false
    client.state = "connecting"

    -- This should safely close the connection without errors
    client_manager.close_client(client, 1000, "Connection failed")

    expect(client.state).to_be("closed")
    expect(tcp_handle:is_closing()).to_be_true()
  end)

  it("should track state transitions correctly", function()
    local tcp_handle = create_mock_tcp_handle()
    local client = client_manager.create_client(tcp_handle)

    -- Initial state
    expect(client.state).to_be("connecting")

    -- After connection established
    client.state = "connected"
    client.handshake_complete = true

    -- Close
    client_manager.close_client(client, 1000, "Normal")

    -- Should be in closing state immediately
    expect(client.state).to_be("closing")

    -- After callback
    if #tcp_handle._write_callbacks > 0 then
      tcp_handle._write_callbacks[1]()
    end

    -- Should be in closed state
    expect(client.state).to_be("closed")
  end)
end)
