# TRACE vs DEBUG 日志级别对比示例

## 场景：处理断连事件

### 使用 DEBUG 级别
```lua
logger.debug("reconnect", "Auto-reconnect disabled")
logger.debug("reconnect", "Already in reconnection process")
logger.debug("reconnect", "Disconnect code 1000 is not reconnectable")
logger.debug("reconnect", "Terminal exited too quickly, likely user action")
```

**输出示例：**
```
[14:32:15.124] [ClaudeCode] [reconnect] [DEBUG] Auto-reconnect disabled
[14:32:15.125] [ClaudeCode] [reconnect] [DEBUG] Disconnect code 1000 is not reconnectable
```

### 使用 TRACE 级别
```lua
logger.trace("reconnect", "handle_disconnect() called: code=1006, reason='Connection timeout', source=websocket, enabled=true")
logger.trace("reconnect", "Checking if code 1006 should trigger reconnection")
logger.trace("reconnect", "Code 1006 is in reconnectable list")
logger.trace("reconnect", "Code 1006 reconnectable: true")
logger.trace("reconnect", "Time since last connect: 45230ms")
logger.trace("reconnect", "Scheduling reconnection attempt in 1000ms")
```

**输出示例：**
```
[14:32:15.123] [ClaudeCode] [reconnect] [TRACE] handle_disconnect() called: code=1006, reason='Connection timeout', source=websocket, enabled=true
[14:32:15.124] [ClaudeCode] [reconnect] [TRACE] Checking if code 1006 should trigger reconnection
[14:32:15.124] [ClaudeCode] [reconnect] [TRACE] Code 1006 is in reconnectable list
[14:32:15.124] [ClaudeCode] [reconnect] [TRACE] Code 1006 reconnectable: true
[14:32:15.125] [ClaudeCode] [reconnect] [TRACE] Time since last connect: 45230ms
[14:32:15.125] [ClaudeCode] [reconnect] [TRACE] Scheduling reconnection attempt in 1000ms
```

## 重连过程的完整日志对比

### DEBUG 级别输出
```
[INFO] Handling disconnect: code=1006, reason='Connection timeout', source=websocket
[INFO] Attempting reconnection 1/3
[DEBUG] Connection not established, retrying in 2000ms
[INFO] Attempting reconnection 2/3
[INFO] Successfully reconnected to Claude
```

### TRACE 级别输出
```
[TRACE] handle_disconnect() called: code=1006, reason='Connection timeout', source=websocket, enabled=true
[TRACE] Checking if code 1006 should trigger reconnection
[TRACE] Code 1006 reconnectable: true
[INFO] Handling disconnect: code=1006, reason='Connection timeout', source=websocket
[TRACE] Time since last connect: 45230ms
[TRACE] Scheduling reconnection attempt in 1000ms
[TRACE] Initial delay completed, starting reconnection
[TRACE] attempt_reconnect() called, enabled=true
[TRACE] Current state: retry_count=0, max_retries=3, is_reconnecting=false
[INFO] Attempting reconnection 1/3
[TRACE] Opening terminal to launch Claude CLI
[TRACE] Scheduling connection check in 5000ms
[TRACE] Connection check result: false
[DEBUG] Connection not established, retrying in 2000ms
[TRACE] Calculated retry delay: base=2000ms, attempt=1, multiplier=1.5, raw=3000ms, final=3000ms
[TRACE] Starting retry timer with delay 3000ms
[TRACE] Retry timer fired, scheduling next attempt
[TRACE] attempt_reconnect() called, enabled=true
[TRACE] Current state: retry_count=1, max_retries=3, is_reconnecting=true
[INFO] Attempting reconnection 2/3
[TRACE] Opening terminal to launch Claude CLI
[TRACE] Scheduling connection check in 5000ms
[TRACE] Connection check result: true
[INFO] Successfully reconnected to Claude
[TRACE] Recording successful connection at 1234567890
[TRACE] Resetting reconnection state
[TRACE] State reset complete: retry_count 2->0, is_reconnecting true->false, timer true->nil
```

## 使用建议

### 何时使用 DEBUG
- 日常开发调试
- 生产环境问题排查
- 了解程序的主要流程
- 查看关键决策点

### 何时使用 TRACE
- 深度调试复杂问题
- 需要了解完整执行路径
- 性能分析（查看函数调用频率）
- 重现难以复现的 bug
- 验证算法逻辑

### 性能影响
- **DEBUG**: 较小的性能影响
- **TRACE**: 显著的性能影响（大量日志写入）

### 日志文件大小
- **DEBUG**: 适中
- **TRACE**: 可能快速增长（建议定期清理）

## 在 ClaudeCode 中的应用

```lua
-- 设置不同日志级别
require("claudecode").setup({
  log_level = "debug",  -- 一般调试
  -- log_level = "trace",  -- 深度调试
})
```

### 查看特定级别的日志
```bash
# 只看 DEBUG 级别
grep "\[DEBUG\]" /tmp/claudecode_debug.log

# 只看 TRACE 级别
grep "\[TRACE\]" /tmp/claudecode_debug.log

# 看 DEBUG 及以上（不包括 TRACE）
grep -E "\[(DEBUG|INFO|WARN|ERROR)\]" /tmp/claudecode_debug.log
```