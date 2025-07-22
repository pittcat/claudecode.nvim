# ClaudeCode.nvim 与 Claude 进程交互分析报告

## 概述

ClaudeCode.nvim 是一个纯 Lua 实现的 Neovim 插件，通过 WebSocket 协议实现与 Claude CLI 的通信。本报告深入分析了该插件的架构设计、通信机制以及断连问题的根本原因。

## 目录

1. [架构概览](#架构概览)
2. [通信机制详解](#通信机制详解)
3. [断连问题分析](#断连问题分析)
4. [关键技术实现](#关键技术实现)
5. [建议和改进方案](#建议和改进方案)

## 架构概览

### 核心组件

```
┌─────────────────────────────────────────────────────────────┐
│                         Neovim                              │
├─────────────────────────────────────────────────────────────┤
│  ┌─────────────────┐    ┌─────────────────┐               │
│  │  ClaudeCode     │    │   WebSocket     │               │
│  │  Plugin Core    │────│    Server       │               │
│  └─────────────────┘    └─────────────────┘               │
│           │                      │                          │
│           │                      │ (JSON-RPC/MCP)          │
│           ↓                      ↓                          │
│  ┌─────────────────┐    ┌─────────────────┐               │
│  │    Terminal     │    │   Lock File     │               │
│  │   Integration   │    │    System       │               │
│  └─────────────────┘    └─────────────────┘               │
└─────────────────────────────────────────────────────────────┘
                     │              │
                     │              │ (~/.claude/ide/[port].lock)
                     ↓              ↓
             ┌─────────────────────────────┐
             │      Claude CLI Process     │
             └─────────────────────────────┘
```

### 启动流程

1. **用户执行 `:ClaudeCodeStart`**
2. **WebSocket 服务器启动**：
   - 在配置的端口范围内随机选择可用端口
   - 生成 UUID v4 格式的认证令牌
   - 创建 TCP 服务器监听 `127.0.0.1:[port]`
3. **锁文件创建**：
   - 路径：`~/.claude/ide/[port].lock`
   - 内容：包含认证令牌、PID、工作目录等信息
4. **终端启动 Claude CLI**：
   - 设置环境变量：`ENABLE_IDE_INTEGRATION=true`
   - 传递端口信息：`CLAUDE_CODE_SSE_PORT=[port]`
5. **Claude CLI 连接**：
   - 读取锁文件获取认证信息
   - 建立 WebSocket 连接并完成握手

## 通信机制详解

### WebSocket 实现

插件使用纯 Neovim 内置功能（`vim.loop`）实现了完整的 WebSocket 服务器：

#### 1. TCP 服务器 (`server/tcp.lua`)
```lua
-- 端口分配策略：随机选择可用端口
function M.find_available_port(min_port, max_port)
  local ports = {}
  for i = min_port, max_port do
    table.insert(ports, i)
  end
  utils.shuffle_array(ports)  -- 随机化端口顺序
  
  for _, port in ipairs(ports) do
    local test_server = vim.loop.new_tcp()
    if test_server:bind("127.0.0.1", port) then
      test_server:close()
      return port
    end
  end
end
```

#### 2. WebSocket 握手 (`server/handshake.lua`)
- 实现 RFC 6455 标准的 WebSocket 握手
- 验证 `x-claude-code-ide-authorization` 头部的认证令牌
- 生成正确的 `Sec-WebSocket-Accept` 响应

#### 3. 帧处理 (`server/frame.lua`)
- 支持文本帧、二进制帧、关闭帧、Ping/Pong 帧
- 实现帧的解析和构造
- 处理掩码和负载数据

### MCP 协议实现

MCP (Model Context Protocol) 使用 JSON-RPC 2.0 格式进行通信：

#### 请求格式
```json
{
  "jsonrpc": "2.0",
  "id": 123,
  "method": "tools/call",
  "params": {
    "name": "openFile",
    "arguments": {
      "path": "/path/to/file.lua",
      "line": 42
    }
  }
}
```

#### 响应格式
```json
{
  "jsonrpc": "2.0",
  "id": 123,
  "result": {
    "success": true
  }
}
```

#### 支持的工具
- `openFile`: 打开文件并跳转到指定行
- `getCurrentSelection`: 获取当前选中的文本
- `getOpenEditors`: 获取已打开的文件列表
- `openDiff`: 打开 diff 视图

### 认证机制

#### 认证令牌生成 (`lockfile.lua:25-61`)
```lua
function generate_auth_token()
  -- UUID v4 格式: xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx
  local template = "xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx"
  local uuid = template:gsub("[xy]", function(c)
    local v = (c == "x") and math.random(0, 15) or math.random(8, 11)
    return string.format("%x", v)
  end)
  return uuid
end
```

#### 锁文件格式
```json
{
  "pid": 12345,
  "workspaceFolders": ["/path/to/project"],
  "ideName": "Neovim",
  "transport": "ws",
  "authToken": "550e8400-e29b-41d4-a716-446655440000"
}
```

## 断连问题分析

### 断连原因

1. **Ping/Pong 超时**
   - 默认 30 秒发送一次 Ping
   - 60 秒无响应则判定连接超时
   - 代码位置：`server/tcp.lua:245-266`

2. **Claude CLI 进程退出**
   - 正常退出：用户关闭终端
   - 异常退出：进程崩溃或被终止
   - 处理位置：`terminal/native.lua:93-119`

3. **网络层面断开**
   - TCP 连接中断
   - 读取错误或 EOF
   - 处理位置：`server/tcp.lua:122-134`

### 断连检测机制

#### 1. WebSocket 层心跳检测
```lua
-- server/tcp.lua:249-262
timer:start(interval, interval, function()
  for _, client in pairs(server.clients) do
    if client.state == "connected" then
      if client_manager.is_client_alive(client, interval * 2) then
        client_manager.send_ping(client, "ping")
      else
        -- 客户端超时，关闭连接
        server.on_error("Client " .. client.id .. " appears dead, closing")
        client_manager.close_client(client, 1006, "Connection timeout")
        M._remove_client(server, client)
      end
    end
  end
end)
```

#### 2. 终端进程监控
```lua
-- terminal/native.lua:93-119
on_exit = function(job_id, _, _)
  vim.schedule(function()
    if job_id == jobid then
      logger.debug("terminal", "Terminal process exited, cleaning up")
      cleanup_state()
      if config.auto_close and current_winid_for_job then
        vim.api.nvim_win_close(current_winid_for_job, true)
      end
    end
  end)
end
```

### 连接状态管理

#### 客户端状态机
```
connecting → connected → closing → closed
    ↓           ↓           ↓
  (失败)     (超时)      (正常)
```

#### @ Mention 队列系统
当 Claude 未连接时，插件会将请求加入队列：
- 连接超时：10 秒
- 队列超时：5 秒
- 连接后延迟：200ms（等待稳定）

## 关键技术实现

### 1. 纯 Lua WebSocket 实现

插件完全使用 Neovim 内置功能，无外部依赖：
- `vim.loop`: TCP 网络操作
- `vim.json`: JSON 编解码
- `vim.schedule`: 异步调度

### 2. 防闪烁优化

终端窗口切换时的优化：
```lua
-- terminal.lua:126-150
local function apply_display_fixes(bufnr, winid)
  if not config.fix_display_corruption then
    return
  end
  vim.schedule(function()
    if vim.api.nvim_buf_is_valid(bufnr) then
      vim.api.nvim_buf_set_option(bufnr, "scrollback", 1000)
      vim.api.nvim_buf_call(bufnr, function()
        vim.opt_local.number = false
        vim.opt_local.relativenumber = false
        vim.opt_local.cursorline = false
        vim.opt_local.signcolumn = "no"
      end)
    end
  end)
end
```

### 3. 延迟响应处理

对于需要用户交互的工具调用：
```lua
-- 使用全局变量避免模块重载问题
_G.claude_deferred_responses = _G.claude_deferred_responses or {}
```

## 建议和改进方案

### 1. 增强断连恢复能力

**现状问题**：
- 无自动重连机制
- Claude 进程退出后需要手动重启

**改进方案**：
```lua
-- 建议添加自动重连功能
function M.auto_reconnect()
  local retry_count = 0
  local max_retries = 3
  local retry_delay = 2000  -- 2秒
  
  local function attempt_reconnect()
    if retry_count >= max_retries then
      logger.error("auto_reconnect", "Max reconnection attempts reached")
      return
    end
    
    retry_count = retry_count + 1
    logger.info("auto_reconnect", "Attempting reconnection " .. retry_count .. "/" .. max_retries)
    
    -- 重新打开终端
    M.terminal.open()
    
    -- 检查连接状态
    vim.defer_fn(function()
      if not M.is_claude_connected() then
        attempt_reconnect()
      else
        logger.info("auto_reconnect", "Successfully reconnected")
        retry_count = 0
      end
    end, retry_delay)
  end
  
  attempt_reconnect()
end
```

### 2. 改进连接监控

**建议添加连接质量指标**：
```lua
-- 连接健康度监控
local connection_health = {
  last_activity = vim.loop.now(),
  ping_latency = 0,
  message_count = 0,
  error_count = 0,
}

-- 定期报告连接状态
function M.report_connection_health()
  local now = vim.loop.now()
  local idle_time = now - connection_health.last_activity
  
  if idle_time > 60000 then  -- 1分钟无活动
    logger.warn("connection", "Connection idle for " .. idle_time .. "ms")
  end
  
  return connection_health
end
```

### 3. 优化日志记录

**建议增加结构化日志**：
```lua
-- 添加连接事件日志
local connection_events = {
  { timestamp = os.time(), event = "connected", details = {} },
  { timestamp = os.time(), event = "disconnected", reason = "timeout" },
}

-- 导出连接历史供调试
function M.export_connection_history()
  local log_file = vim.fn.expand("~/.claude/connection_history.json")
  local file = io.open(log_file, "w")
  file:write(vim.json.encode(connection_events))
  file:close()
end
```

### 4. 增强错误提示

**为用户提供更清晰的错误信息**：
```lua
-- 断连原因映射
local disconnect_reasons = {
  [1000] = "正常关闭",
  [1001] = "服务器关闭",
  [1002] = "协议错误",
  [1003] = "不支持的数据类型",
  [1006] = "连接超时（无响应）",
  [1011] = "服务器内部错误",
}

-- 用户友好的错误提示
function M.notify_disconnect(code, reason)
  local friendly_reason = disconnect_reasons[code] or "未知原因"
  vim.notifyre("which-key").show("\3", {mode = "n", auto = true})
    (
    string.format("Claude 连接已断开：%s (%d)\n%s", friendly_reason, code, reason),
    vim.log.levels.WARN
  )
end
```

## 结论

ClaudeCode.nvim 的设计架构清晰，实现了完整的 WebSocket 服务器和 MCP 协议支持。断连问题主要源于：

1. **心跳超时机制**：60 秒无响应即断开连接
2. **进程生命周期管理**：Claude CLI 退出时的清理机制
3. **缺少自动重连**：需要手动干预恢复连接

通过实施上述改进方案，可以显著提升插件的稳定性和用户体验。特别是自动重连机制和连接健康监控，将大大减少断连对用户工作流的影响。
