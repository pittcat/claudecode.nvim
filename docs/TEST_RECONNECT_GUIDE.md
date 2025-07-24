# ClaudeCode.nvim 自动重连测试指南

本指南帮助你测试 ClaudeCode.nvim 的自动重连功能。

## 准备工作

1. 确保 ClaudeCode 正在运行：
   ```vim
   :ClaudeCode
   ```

2. 检查连接状态：
   ```vim
   :ClaudeCodeStatus
   :ClaudeCodeConnectionHealth
   ```

3. 确认自动重连已启用：
   ```vim
   :ClaudeCodeReconnectStatus
   ```

## 测试方法

### 方法 1：使用 Shell 脚本（推荐）

在终端中运行测试脚本：

```bash
cd ~/.vim/plugged/claudecode.nvim/scripts/
./test_reconnect.sh
```

脚本提供以下测试选项：
- 测试 WebSocket 超时（代码 1006）
- 测试服务器关闭（代码 1001）
- 测试终端进程终止
- 测试正常关闭（代码 1000）

### 方法 2：在 Neovim 中测试

1. 加载测试命令：
   ```vim
   :source ~/.vim/plugged/claudecode.nvim/scripts/test_reconnect_command.vim
   ```

2. 运行交互式测试：
   ```vim
   :ClaudeCodeTestReconnect
   ```

3. 或使用快速测试命令：
   ```vim
   :ClaudeCodeTestDisconnect   " 强制断开连接
   :ClaudeCodeMonitorHealth     " 监控连接健康状态
   :ClaudeCodeQuickStatus       " 快速状态检查
   ```

### 方法 3：手动测试

1. **模拟网络超时**：
   找到 Claude 进程并发送信号：
   ```bash
   # 找到 Claude 进程
   ps aux | grep claude
   
   # 发送 TERM 信号
   kill -TERM <PID>
   ```

2. **模拟 WebSocket 断开**：
   ```bash
   # 找到 WebSocket 端口
   ls ~/.claude/ide/*.lock
   
   # 使用 nc 发送关闭帧
   printf "\x88\x02\x03\xe8" | nc localhost <PORT>
   ```

## 预期行为

### 应该触发自动重连的情况：
- WebSocket 超时（代码 1006）
- 服务器错误（代码 1001, 1011）
- 终端异常退出（非 0 退出代码）
- 网络中断

### 不应该触发自动重连的情况：
- 正常关闭（代码 1000）
- 用户主动关闭终端（退出代码 0）
- 手动禁用自动重连

## 观察重连过程

1. **查看通知**：
   - 断连时会显示友好的错误信息和原因
   - 重连过程中会显示进度
   - 成功重连后会显示成功通知

2. **查看日志**：
   ```bash
   # 实时查看断连日志
   tail -f ~/.claude/logs/disconnects.log
   
   # 查看连接事件
   cat ~/.claude/logs/connection_events.json | jq
   ```

3. **生成报告**：
   ```vim
   :ClaudeCodeConnectionReport
   ```

## 调试信息

如果重连失败，检查以下内容：

1. **重连状态**：
   ```vim
   :ClaudeCodeReconnectStatus
   ```

2. **连接健康**：
   ```vim
   :ClaudeCodeConnectionHealth
   ```

3. **最近的断连事件**：
   在 Neovim 中运行：
   ```lua
   :lua require("claudecode.connection_tracker").get_recent_disconnects(5)
   ```

## 配置调整

如果需要调整重连行为，修改配置：

```lua
require("claudecode").setup({
  auto_reconnect = {
    enabled = true,      -- 启用/禁用自动重连
    max_retries = 3,     -- 最大重试次数
    retry_delay = 2000,  -- 初始重试延迟（毫秒）
  },
})
```

## 常见问题

**Q: 为什么没有触发自动重连？**
- 检查是否启用了自动重连：`:ClaudeCodeReconnectStatus`
- 确认断连代码是否在可重连列表中
- 查看日志了解具体原因

**Q: 重连失败怎么办？**
- 检查 Claude CLI 是否正常工作
- 确认 WebSocket 服务器仍在运行：`:ClaudeCodeStatus`
- 手动重启：`:ClaudeCodeOpenTerminal`

**Q: 如何临时禁用自动重连？**
```vim
:ClaudeCodeReconnectDisable
```

## 测试完成后

记得查看生成的报告和日志，确认自动重连机制正常工作。如果发现问题，请保存日志文件用于调试。