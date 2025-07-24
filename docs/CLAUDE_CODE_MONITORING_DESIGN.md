# Claude Code 交互监控系统设计方案

## 概述

本文档描述了一个用于监控 Claude Code 与 Neovim 插件交互状态的系统设计方案。该系统能够实时跟踪四种核心状态：正在执行、执行完成、空闲状态和连接断开。

## 需求分析

### 核心监控状态

1. **执行中 (EXECUTING)**: Claude Code 正在执行工具调用或处理请求
2. **已完成 (COMPLETED)**: Claude Code 完成了一个任务，但连接仍然活跃
3. **空闲 (IDLE)**: Claude Code 已连接但没有活跃的任务执行
4. **断开连接 (DISCONNECTED)**: Claude Code 未连接或终端进程已退出

### 功能需求

- 实时状态追踪和更新
- 状态变化事件通知
- 历史状态记录
- 性能监控指标
- 用户界面展示
- API 接口提供状态查询

## 架构设计

### 系统架构图

```
┌─────────────────────────────────────────────────────────────┐
│                    Claude Code 监控系统                       │
├─────────────────────────────────────────────────────────────┤
│  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐ │
│  │   状态管理器     │  │   事件监听器     │  │   UI 显示层     │ │
│  │  StateManager   │  │ EventListener   │  │  UIProvider     │ │
│  └─────────────────┘  └─────────────────┘  └─────────────────┘ │
│           │                    │                    │         │
│           └────────────────────┼────────────────────┘         │
│                               │                               │
├─────────────────────────────────────────────────────────────┤
│                        监控适配器层                            │
│  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐ │
│  │  WebSocket监控   │  │   工具调用监控   │  │   终端进程监控   │ │
│  │ WebSocketMonitor│  │  ToolCallMonitor│  │ TerminalMonitor │ │
│  └─────────────────┘  └─────────────────┘  └─────────────────┘ │
│           │                    │                    │         │
├─────────────────────────────────────────────────────────────┤
│                         现有系统                              │
│  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐ │
│  │ WebSocket服务器  │  │    工具系统      │  │   终端管理器     │ │
│  │   server/init   │  │   tools/init    │  │   terminal.lua  │ │
│  └─────────────────┘  └─────────────────┘  └─────────────────┘ │
└─────────────────────────────────────────────────────────────┘
```

### 核心组件设计

#### 1. 状态管理器 (StateManager)

```lua
-- lua/claudecode/monitoring/state_manager.lua

local StateManager = {}

-- 状态枚举
StateManager.States = {
  DISCONNECTED = "disconnected",
  IDLE = "idle", 
  EXECUTING = "executing",
  COMPLETED = "completed"
}

-- 状态数据结构
StateManager.state = {
  current = StateManager.States.DISCONNECTED,
  last_changed = 0,
  execution_count = 0,
  current_operation = nil,
  history = {},
  metrics = {
    total_executions = 0,
    avg_execution_time = 0,
    last_execution_time = 0
  }
}
```

#### 2. 事件监听器 (EventListener)

```lua
-- lua/claudecode/monitoring/event_listener.lua

local EventListener = {}

-- 事件类型
EventListener.Events = {
  STATE_CHANGED = "state_changed",
  EXECUTION_STARTED = "execution_started", 
  EXECUTION_COMPLETED = "execution_completed",
  CONNECTION_ESTABLISHED = "connection_established",
  CONNECTION_LOST = "connection_lost"
}

-- 回调管理
EventListener.callbacks = {}

function EventListener.on(event, callback)
  -- 注册事件回调
end

function EventListener.emit(event, data)
  -- 触发事件回调
end
```

#### 3. 监控适配器

**WebSocket 监控器**
```lua
-- lua/claudecode/monitoring/websocket_monitor.lua

local WebSocketMonitor = {}

function WebSocketMonitor.setup(server_module)
  -- 监听客户端连接/断开
  -- 监听消息处理状态
  -- 集成到现有的 server/init.lua
end
```

**工具调用监控器**
```lua
-- lua/claudecode/monitoring/tool_call_monitor.lua

local ToolCallMonitor = {}

function ToolCallMonitor.setup(tools_module)
  -- 监听工具调用开始
  -- 监听工具调用完成
  -- 监听延迟响应状态
  -- 集成到现有的 tools/init.lua
end
```

**终端进程监控器**
```lua
-- lua/claudecode/monitoring/terminal_monitor.lua

local TerminalMonitor = {}

function TerminalMonitor.setup(terminal_module)
  -- 监听终端进程状态
  -- 监听进程退出事件
  -- 集成到现有的 terminal.lua
end
```

## 实现方案

### 阶段一：核心状态管理

1. **创建状态管理器**
   - 实现状态枚举和转换逻辑
   - 添加状态历史记录
   - 实现性能指标收集

2. **集成事件系统**
   - 设计事件触发机制
   - 实现回调管理系统
   - 添加状态变化通知

### 阶段二：监控适配器实现

1. **WebSocket 监控集成**
   ```lua
   -- 在 server/init.lua 中的集成点
   
   -- 客户端连接时
   on_connect = function(client)
     M.state.clients[client.id] = client
     -- 新增: 通知监控系统连接建立
     monitoring.notify_connection_established(client)
   end
   
   -- 客户端断开时
   on_disconnect = function(client, code, reason)
     M.state.clients[client.id] = nil
     -- 新增: 通知监控系统连接断开
     monitoring.notify_connection_lost(client, code, reason)
   end
   
   -- 消息处理开始时
   function M._handle_request(client, parsed)
     -- 新增: 通知监控系统开始处理请求
     monitoring.notify_request_started(parsed.method, parsed.id)
     
     -- 原有逻辑...
     
     -- 新增: 通知监控系统请求处理完成
     monitoring.notify_request_completed(parsed.method, parsed.id, result)
   end
   ```

2. **工具调用监控集成**
   ```lua
   -- 在 tools/init.lua 中的集成点
   
   function M.handle_invoke(client, params)
     local tool_name = params.name
     
     -- 新增: 通知监控系统工具调用开始
     monitoring.notify_tool_execution_started(tool_name, params)
     
     -- 原有工具执行逻辑...
     local result = tool_data.handler(params.arguments)
     
     -- 新增: 通知监控系统工具调用完成
     monitoring.notify_tool_execution_completed(tool_name, result)
     
     return result
   end
   ```

3. **终端进程监控集成**
   ```lua
   -- 在 terminal/native.lua 中的集成点
   
   jobid = vim.fn.termopen(term_cmd_arg, {
     env = env_table,
     on_exit = function(job_id, exit_code, _)
       vim.schedule(function()
         if job_id == jobid then
           -- 新增: 通知监控系统终端进程退出
           monitoring.notify_terminal_process_exited(job_id, exit_code)
           
           -- 原有清理逻辑...
           cleanup_state()
         end
       end)
     end,
   })
   ```

### 阶段三：用户界面和 API

1. **状态显示组件**
   ```lua
   -- lua/claudecode/monitoring/ui.lua
   
   local UI = {}
   
   function UI.create_status_line()
     -- 创建状态栏显示
   end
   
   function UI.create_floating_window()
     -- 创建浮动窗口显示详细状态
   end
   
   function UI.update_display(state)
     -- 更新显示内容
   end
   ```

2. **用户命令**
   ```lua
   -- 新增用户命令
   vim.api.nvim_create_user_command("ClaudeCodeStatus", function()
     local status = monitoring.get_current_status()
     print(vim.inspect(status))
   end, { desc = "显示 Claude Code 当前状态" })
   
   vim.api.nvim_create_user_command("ClaudeCodeMonitor", function()
     monitoring.toggle_monitor_window()
   end, { desc = "切换监控窗口显示" })
   ```

3. **API 接口**
   ```lua
   -- lua/claudecode/monitoring/api.lua
   
   local API = {}
   
   function API.get_status()
     -- 返回当前状态
   end
   
   function API.get_metrics()
     -- 返回性能指标
   end
   
   function API.get_history()
     -- 返回状态历史
   end
   
   function API.subscribe_events(callback)
     -- 订阅状态变化事件
   end
   ```

## 状态转换逻辑

### 状态转换图

```
DISCONNECTED ←--→ IDLE ←--→ EXECUTING ←--→ COMPLETED
     ↑                                        ↓
     └────────────────────────────────────────┘
```

### 转换条件

1. **DISCONNECTED → IDLE**
   - 条件: WebSocket 客户端连接建立
   - 触发器: `on_connect` 回调

2. **IDLE → EXECUTING**
   - 条件: 接收到工具调用请求
   - 触发器: `tools/call` 处理开始

3. **EXECUTING → COMPLETED**
   - 条件: 工具调用完成并发送响应
   - 触发器: 响应发送完成

4. **COMPLETED → IDLE**
   - 条件: 无新的工具调用，等待超时
   - 触发器: 定时器检查（例如 2 秒后）

5. **任何状态 → DISCONNECTED**
   - 条件: 客户端断开连接或终端进程退出
   - 触发器: `on_disconnect` 回调或进程退出事件

## 性能考虑

### 内存管理
- 限制状态历史记录数量（默认保留最近 100 条）
- 使用轻量级事件系统，避免内存泄漏
- 定期清理过期的监控数据

### CPU 优化
- 状态更新使用 `vim.schedule` 异步处理
- 避免在关键路径上增加过多开销
- 可配置的监控粒度级别

### 可配置性
```lua
-- 监控系统配置选项
local monitoring_config = {
  enabled = true,
  history_limit = 100,
  status_check_interval = 2000, -- 毫秒
  show_performance_metrics = true,
  ui_update_throttle = 100, -- 毫秒
}
```

## 测试策略

### 单元测试
- 状态管理器核心逻辑测试
- 事件系统测试
- 状态转换逻辑测试

### 集成测试
- WebSocket 连接/断开场景测试
- 工具调用执行流程测试
- 终端进程生命周期测试

### 端到端测试
- 完整的 Claude Code 交互流程测试
- 状态监控准确性验证
- 性能影响评估

## 发布计划

### 第一版 (MVP)
- 基础状态管理和事件系统
- WebSocket 连接状态监控
- 简单的命令行状态查询

### 第二版
- 完整的工具调用监控
- 终端进程监控集成
- 基础 UI 显示

### 第三版
- 高级 UI 功能（浮动窗口、状态栏）
- 性能指标和历史记录
- 可配置的监控选项

## 风险评估

### 技术风险
- **性能影响**: 监控系统可能影响核心功能性能
  - 缓解: 异步处理、可配置开关、性能测试

- **状态同步**: 多个监控点的状态可能不一致
  - 缓解: 中心化状态管理、原子操作

### 兼容性风险
- **现有代码修改**: 需要修改多个现有模块
  - 缓解: 最小化侵入性修改、向后兼容设计

## 总结

这个监控系统设计提供了一个完整的解决方案来跟踪 Claude Code 的执行状态。通过分层架构和事件驱动的设计，系统能够准确地监控四种核心状态，同时保持良好的性能和可扩展性。

实现将分三个阶段进行，从核心功能开始，逐步添加高级特性。这种渐进式的开发方法能够确保系统的稳定性和可维护性。