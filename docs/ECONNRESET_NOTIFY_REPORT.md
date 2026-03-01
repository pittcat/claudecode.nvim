# ClaudeCode WebSocket `ECONNRESET` 报错定位报告

## 结论摘要
- 你在 `notify` 里看到的这条日志：
  - `[ClaudeCode] [server] [ERROR] WebSocket server error: Client read error: ECONNRESET`
- 不是在 `notify` 模块里原生产生的，而是 **TCP 读回调里的错误被上抛后，由 logger 统一转发到 `vim.notify`**。
- 触发点在：`lua/claudecode/server/tcp.lua:125-130`（`read_start` 回调收到 `err`）。
- `ECONNRESET` 语义是“对端重置连接”（peer reset），通常是客户端进程异常退出、被 kill、网络栈主动复位等导致，**多数场景属于连接断开事件，不一定是插件逻辑 bug**。

## 证据链（从源头到 notify）

### 1) 源头：TCP 读错误被构造成 `Client read error: ...`
文件：`lua/claudecode/server/tcp.lua`

- `client_tcp:read_start(function(err, data)` 在读事件里处理错误。
- 当 `err` 非空时，拼接：`"Client read error: " .. err`。
- 随后调用：
  - `server.on_error(error_msg)`
  - `M._disconnect_client(server, client, 1006, error_msg)`

关键位置：
- `lua/claudecode/server/tcp.lua:125`
- `lua/claudecode/server/tcp.lua:127`
- `lua/claudecode/server/tcp.lua:128`
- `lua/claudecode/server/tcp.lua:129`

### 2) 中转：`on_error` 回调写成 server 级 ERROR 日志
文件：`lua/claudecode/server/init.lua`

- `on_error = function(error_msg)` 中直接调用：
  - `logger.error("server", "WebSocket server error:", error_msg)`

关键位置：
- `lua/claudecode/server/init.lua:98-99`

### 3) 最终显示：ERROR 级日志走 `vim.notify`
文件：`lua/claudecode/logger.lua`

- `logger.error(...)` 最终进入 `log()`。
- 在 `level == ERROR` 分支中执行：
  - `vim.notify(prefix .. " " .. message, vim.log.levels.ERROR, { title = "ClaudeCode Error" })`

关键位置：
- `lua/claudecode/logger.lua:114-117`

因此你看到的 `notify` 文案，是上述链路拼接后的结果，而非单独 notify 模块直接抛错。

## 该报错是否说明“插件内部异常”？

当前代码语义下：
- 所有 TCP 读错误都会被当成 `server error` 记录为 ERROR。
- 但 `ECONNRESET` 常见于对端主动/异常断开，和 EOF 一样本质是“连接终止类事件”。

这意味着：
- 出现该日志 **不必然** 代表插件实现有 bug。
- 更可能是客户端连接生命周期中的断连（例如 Claude CLI 进程退出、重启、崩溃、被中断）。

## 单元测试佐证
文件：`tests/unit/server/tcp_spec.lua`

已有测试明确把“读错误”当作断连路径处理：
- 用 `client.tcp_handle._read_cb("boom", nil)` 模拟读错误。
- 断言 `on_error("Client read error: boom")` 被调用。
- 同时断言 `on_disconnect(..., 1006, "Client read error: boom")` 被调用。

关键位置：
- `tests/unit/server/tcp_spec.lua:48-72`

这说明当前行为是“设计如此”，不是偶发路径。

## 可改进点（如果你想减少 notify 噪声）

1. 对 `ECONNRESET` 这类预期断连降级
- 在 `tcp.lua` 里识别 `err == "ECONNRESET"`：
  - 不走 `logger.error`，改为 `logger.debug` 或 `logger.warn`。
  - 仍保留 `_disconnect_client(...)` 清理逻辑。

2. 区分“连接生命周期事件”与“真正服务异常”
- 生命周期断连（EOF/ECONNRESET/timeout）记录为 disconnect 日志。
- bind/listen/协议解析失败等才保留 ERROR + notify。

3. 在日志文案中明确来源
- 把 `WebSocket server error` 改成更精确的 `WebSocket client disconnected (read error)`，避免误导成服务端故障。

## 建议排查方向（若你怀疑频繁断连）
- 查看触发前后是否有 Claude CLI 进程退出/重启。
- 检查是否存在主动 kill、shell 退出、会话重建。
- 对照断连统计（项目内有 reconnect/monitoring 文档与模块）。

---

报告生成时间：`2026-03-01 18:48:20 CST`
