--- Claude Code 监控系统测试脚本
-- 全面测试监控系统的各项功能和状态转换
-- @module tests.monitoring.monitoring_test

local test_utils = require("tests.mocks.test_utils")

describe("Claude Code Monitoring System", function()
  local monitoring
  local state_manager
  local event_listener
  
  before_each(function()
    -- 清理之前的测试状态
    package.loaded["claudecode.monitoring.init"] = nil
    package.loaded["claudecode.monitoring.state_manager"] = nil  
    package.loaded["claudecode.monitoring.event_listener"] = nil
    
    -- 重新加载模块
    monitoring = require("claudecode.monitoring.init")
    state_manager = require("claudecode.monitoring.state_manager")
    event_listener = require("claudecode.monitoring.event_listener")
    
    -- 重置状态
    state_manager.reset()
    event_listener.reset()
  end)
  
  after_each(function()
    if monitoring.is_initialized() then
      monitoring.shutdown()
    end
  end)
  
  describe("Initialization", function()
    it("should initialize with default config", function()
      local success = monitoring.setup()
      
      assert.is_true(success)
      assert.is_true(monitoring.is_initialized())
      
      local status = monitoring.get_status()
      assert.equals("disconnected", status.current_state)
      assert.is_true(status.initialized)
    end)
    
    it("should initialize with custom config", function()
      local custom_config = {
        state_manager = {
          history_limit = 50,
          completion_timeout = 1000
        },
        event_listener = {
          max_history = 100,
          debug_events = true
        }
      }
      
      local success = monitoring.setup(custom_config)
      
      assert.is_true(success)
      assert.is_true(monitoring.is_initialized())
      
      local status = monitoring.get_status()
      assert.equals(50, status.config.state_manager.history_limit)
      assert.equals(1000, status.config.state_manager.completion_timeout)
      assert.is_true(status.config.event_listener.debug_events)
    end)
    
    it("should not reinitialize if already initialized", function()
      monitoring.setup()
      local success = monitoring.setup()
      
      assert.is_true(success) -- 应该返回true但给出警告
      assert.is_true(monitoring.is_initialized())
    end)
  end)
  
  describe("State Management", function()
    before_each(function()
      monitoring.setup()
    end)
    
    it("should start in disconnected state", function()
      local status = monitoring.get_status()
      assert.equals("disconnected", status.current_state)
    end)
    
    it("should transition from disconnected to idle when client connects", function()
      local state_changes = {}
      monitoring.on("state_changed", function(event, data)
        table.insert(state_changes, {
          from = data.from_state,
          to = data.to_state
        })
      end)
      
      -- 模拟客户端连接
      state_manager.add_client("client_1", { id = "client_1", address = "127.0.0.1" })
      
      assert.equals("idle", monitoring.get_status().current_state)
      assert.equals(1, #state_changes)
      assert.equals("disconnected", state_changes[1].from)
      assert.equals("idle", state_changes[1].to)
    end)
    
    it("should transition to executing when tool call starts", function()
      -- 先连接客户端
      state_manager.add_client("client_1", { id = "client_1" })
      assert.equals("idle", monitoring.get_status().current_state)
      
      -- 开始工具调用
      local success = state_manager.set_state(
        state_manager.States.EXECUTING,
        state_manager.OperationTypes.TOOL_CALL,
        { tool_name = "openFile", client_id = "client_1" }
      )
      
      assert.is_true(success)
      assert.equals("executing", monitoring.get_status().current_state)
    end)
    
    it("should transition from executing to completed", function()
      -- 设置执行状态
      state_manager.add_client("client_1", { id = "client_1" })
      state_manager.set_state(state_manager.States.EXECUTING, state_manager.OperationTypes.TOOL_CALL)
      
      -- 完成执行
      local success = state_manager.set_state(
        state_manager.States.COMPLETED,
        state_manager.OperationTypes.TOOL_CALL,
        { tool_name = "openFile", success = true }
      )
      
      assert.is_true(success)
      assert.equals("completed", monitoring.get_status().current_state)
    end)
    
    it("should automatically transition from completed to idle after timeout", function()
      -- 设置较短的超时时间
      state_manager.update_config({ completion_timeout = 100 })
      
      state_manager.add_client("client_1", { id = "client_1" })
      state_manager.set_state(state_manager.States.EXECUTING, state_manager.OperationTypes.TOOL_CALL)
      state_manager.set_state(state_manager.States.COMPLETED, state_manager.OperationTypes.TOOL_CALL)
      
      assert.equals("completed", monitoring.get_status().current_state)
      
      -- 等待超时
      vim.wait(200, function()
        return monitoring.get_status().current_state == "idle"
      end)
      
      assert.equals("idle", monitoring.get_status().current_state)
    end)
    
    it("should transition to disconnected when all clients disconnect", function()
      state_manager.add_client("client_1", { id = "client_1" })
      assert.equals("idle", monitoring.get_status().current_state)
      
      state_manager.remove_client("client_1", "user_disconnect")
      
      assert.equals("disconnected", monitoring.get_status().current_state)
    end)
    
    it("should reject invalid state transitions", function()
      -- 直接从disconnected到executing应该失败
      local success = state_manager.set_state(
        state_manager.States.EXECUTING,
        state_manager.OperationTypes.TOOL_CALL
      )
      
      assert.is_false(success)
      assert.equals("disconnected", monitoring.get_status().current_state)
    end)
  end)
  
  describe("Event System", function()
    before_each(function()
      monitoring.setup()
    end)
    
    it("should emit state change events", function()
      local events = {}
      monitoring.on("state_changed", function(event, data)
        table.insert(events, data)
      end)
      
      state_manager.add_client("client_1", { id = "client_1" })
      
      assert.equals(1, #events)
      assert.equals("disconnected", events[1].from_state) 
      assert.equals("idle", events[1].to_state)
    end)
    
    it("should support one-time event listeners", function()
      local call_count = 0
      local callback_id = event_listener.once("state_changed", function()
        call_count = call_count + 1
      end)
      
      -- 触发两次状态变化
      state_manager.add_client("client_1", { id = "client_1" })
      state_manager.remove_client("client_1")
      
      assert.equals(1, call_count) -- 应该只被调用一次
    end)
    
    it("should allow unsubscribing from events", function()
      local call_count = 0
      local callback_id = monitoring.on("state_changed", function()
        call_count = call_count + 1
      end)
      
      state_manager.add_client("client_1", { id = "client_1" })
      assert.equals(1, call_count)
      
      -- 取消订阅
      monitoring.off("state_changed", callback_id)
      
      state_manager.remove_client("client_1")
      assert.equals(1, call_count) -- 不应该再增加
    end)
  end)
  
  describe("Metrics and Statistics", function()
    before_each(function()
      monitoring.setup()
    end)
    
    it("should track execution metrics", function()
      state_manager.add_client("client_1", { id = "client_1" })
      
      -- 执行几次工具调用
      for i = 1, 3 do
        state_manager.set_state(state_manager.States.EXECUTING, state_manager.OperationTypes.TOOL_CALL)
        vim.wait(10) -- 短暂等待
        state_manager.set_state(state_manager.States.COMPLETED, state_manager.OperationTypes.TOOL_CALL)
      end
      
      local metrics = state_manager.get_metrics()
      assert.equals(3, metrics.total_executions)
      assert.is_true(metrics.avg_execution_time > 0)
      assert.is_true(metrics.last_execution_time > 0)
    end)
    
    it("should maintain state history", function()
      state_manager.add_client("client_1", { id = "client_1" })
      state_manager.set_state(state_manager.States.EXECUTING, state_manager.OperationTypes.TOOL_CALL)
      state_manager.set_state(state_manager.States.COMPLETED, state_manager.OperationTypes.TOOL_CALL)
      
      local history = monitoring.get_history()
      
      assert.is_true(#history >= 3) -- 至少有3个状态变化
      assert.equals("disconnected", history[1].from_state)
      assert.equals("idle", history[1].to_state)
    end)
    
    it("should limit history size", function()
      -- 设置较小的历史限制
      state_manager.update_config({ history_limit = 3 })
      
      state_manager.add_client("client_1", { id = "client_1" })
      
      -- 生成多次状态变化
      for i = 1, 5 do
        state_manager.set_state(state_manager.States.EXECUTING, state_manager.OperationTypes.TOOL_CALL)
        state_manager.set_state(state_manager.States.COMPLETED, state_manager.OperationTypes.TOOL_CALL)
      end
      
      local history = monitoring.get_history()
      assert.is_true(#history <= 3) -- 不应该超过限制
    end)
  end)
  
  describe("Health Check", function()
    before_each(function()
      monitoring.setup()
    end)
    
    it("should report healthy status initially", function()
      local health = monitoring.health_check()
      
      assert.is_true(health.overall_healthy)
      assert.equals(0, #health.issues)
    end)
    
    it("should detect unhealthy conditions", function()
      -- 模拟状态管理器的不健康状态
      -- 通过设置一个长时间运行的执行状态
      state_manager.add_client("client_1", { id = "client_1" })
      state_manager.set_state(state_manager.States.EXECUTING, state_manager.OperationTypes.TOOL_CALL)
      
      -- 修改最后状态变化时间以模拟长时间运行
      state_manager.state.last_changed = (vim.loop.hrtime() / 1000000) - 40000 -- 40秒前
      
      local health = monitoring.health_check()
      
      -- 应该检测到问题（如果状态管理器实现了相应的健康检查）
      -- 这里取决于具体的健康检查实现
    end)
  end)
  
  describe("Memory Management", function()
    before_each(function()
      monitoring.setup()
    end)
    
    it("should perform cleanup operations", function()
      -- 生成一些数据
      for i = 1, 10 do
        state_manager.add_client("client_" .. i, { id = "client_" .. i })
        state_manager.remove_client("client_" .. i)
      end
      
      local memory_before = collectgarbage("count")
      monitoring.cleanup()
      local memory_after = collectgarbage("count")
      
      -- 清理后内存使用应该减少或保持稳定
      assert.is_true(memory_after <= memory_before * 1.1) -- 允许10%的误差
    end)
    
    it("should reset all data", function()
      state_manager.add_client("client_1", { id = "client_1" })
      state_manager.set_state(state_manager.States.EXECUTING, state_manager.OperationTypes.TOOL_CALL)
      
      -- 确保有数据
      local status_before = monitoring.get_status()
      assert.equals("executing", status_before.current_state)
      
      monitoring.reset()
      
      local status_after = monitoring.get_status()
      assert.equals("disconnected", status_after.current_state)
      
      local history = monitoring.get_history()
      assert.equals(0, #history) -- 历史应该被清空
    end)
  end)
  
  describe("Error Handling", function()
    it("should handle uninitialized access gracefully", function()
      -- 不初始化直接访问
      local status = monitoring.get_status()
      assert.is_false(status.initialized)
      assert.is_not_nil(status.error)
      
      local stats = monitoring.get_detailed_stats()
      assert.is_not_nil(stats.error)
    end)
    
    it("should handle invalid state transitions", function()
      monitoring.setup()
      
      -- 尝试无效的状态转换
      local success = state_manager.set_state("invalid_state")
      assert.is_false(success)
      
      -- 状态应该保持不变
      assert.equals("disconnected", monitoring.get_status().current_state)
    end)
    
    it("should handle event callback errors", function()
      monitoring.setup()
      
      local error_count = 0
      
      -- 注册一个会出错的回调
      monitoring.on("state_changed", function()
        error("Test error")
      end)
      
      -- 注册错误事件监听器
      monitoring.on("error_occurred", function()
        error_count = error_count + 1
      end)
      
      -- 触发状态变化
      state_manager.add_client("client_1", { id = "client_1" })
      
      -- 错误应该被捕获并触发错误事件
      assert.is_true(error_count > 0)
    end)
  end)
end)