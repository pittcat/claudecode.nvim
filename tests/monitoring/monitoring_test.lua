--- Claude Code 监控系统基础测试
-- 测试监控系统的配置、加载和基本命令功能
-- @module tests.monitoring.monitoring_test

-- 确保测试环境正确设置
require("tests.busted_setup")

describe("Claude Code Monitoring System - Basic Tests", function()
  local monitoring

  before_each(function()
    -- 清理之前的测试状态
    package.loaded["claudecode.monitoring.init"] = nil
    
    -- 重新加载模块
    monitoring = require("claudecode.monitoring.init")
  end)

  after_each(function()
    if monitoring and monitoring.is_initialized and monitoring.is_initialized() then
      if monitoring.shutdown then
        monitoring.shutdown()
      end
    end
  end)

  describe("Module Loading", function()
    it("should load monitoring module successfully", function()
      assert.is_not_nil(monitoring)
      assert.is_function(monitoring.setup)
    end)

    it("should have required functions", function()
      assert.is_function(monitoring.setup)
      assert.is_function(monitoring.is_initialized)
      assert.is_function(monitoring.get_status)
    end)
  end)

  describe("Basic Configuration", function()
    it("should initialize with default config", function()
      local success = monitoring.setup()

      assert.is_true(success)
      assert.is_true(monitoring.is_initialized())
    end)

    it("should accept custom config", function()
      local custom_config = {
        enabled = false,  -- 基础配置测试
      }

      local success = monitoring.setup(custom_config)
      assert.is_true(success)
      assert.is_true(monitoring.is_initialized())
    end)

    it("should handle re-initialization", function()
      monitoring.setup()
      local success = monitoring.setup()

      -- 应该处理重复初始化而不出错
      assert.is_true(success)
      assert.is_true(monitoring.is_initialized())
    end)
  end)

  describe("Basic Commands", function()
    before_each(function()
      monitoring.setup()
    end)

    it("should provide status information", function()
      local status = monitoring.get_status()
      assert.is_not_nil(status)
      assert.is_boolean(status.initialized)
    end)

    it("should handle shutdown gracefully", function()
      local success = pcall(function()
        monitoring.shutdown()
      end)
      assert.is_true(success)
    end)
  end)

  describe("Error Handling", function()
    it("should handle uninitialized access gracefully", function()
      -- 测试未初始化时的访问
      local status = monitoring.get_status()
      assert.is_not_nil(status)
      
      -- 基础错误处理检查
      if status.error then
        assert.is_string(status.error)
      end
    end)

    it("should handle invalid configurations", function()
      local invalid_config = {
        invalid_field = "invalid_value"
      }
      
      -- 应该能处理无效配置而不崩溃
      local success = pcall(function()
        monitoring.setup(invalid_config)
      end)
      
      assert.is_true(success)
    end)
  end)
end)
