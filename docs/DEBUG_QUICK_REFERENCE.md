# ClaudeCode.nvim 调试快速参考

## 🚀 快速启用日志

### DEBUG 级别（推荐）
```vim
:lua require("claudecode.logger").setup({ log_level = "debug" })
```

### TRACE 级别（详细）
```vim
:lua require("claudecode.logger").setup({ log_level = "trace" })
```

## 📍 日志位置
```
/tmp/claudecode_debug.log
```

## 🔍 常用查看命令

```bash
# 实时查看所有日志
tail -f /tmp/claudecode_debug.log

# 查看重连日志
tail -f /tmp/claudecode_debug.log | grep reconnect

# 查看最近的错误
grep ERROR /tmp/claudecode_debug.log | tail -20

# 查看 TRACE 日志
grep TRACE /tmp/claudecode_debug.log | tail -50
```

## 🛠️ 使用工具

### 1. 日志查看器
```bash
cd ~/.vim/plugged/claudecode.nvim/scripts/
./view_trace_logs.sh
```

选项：
- `1` - 查看重连日志
- `2` - 查看 TRACE 日志
- `3` - 查看重连 TRACE
- `4` - 实时监控（彩色）
- `5` - 状态变化
- `6` - 清空日志

### 2. 测试重连
```bash
./test_reconnect.sh
```

### 3. 在 Neovim 中测试
```vim
:source ~/.vim/plugged/claudecode.nvim/scripts/test_reconnect_command.vim
:ClaudeCodeTestReconnect
```

## 📊 日志级别对比

| 操作 | DEBUG 输出 | TRACE 输出 |
|------|------------|------------|
| 断连 | `Disconnect code 1006 is reconnectable` | `+ 函数调用参数 + 状态检查过程` |
| 重连 | `Attempting reconnection 1/3` | `+ 计时器详情 + 每步状态变化` |
| 成功 | `Successfully reconnected` | `+ 连接检查细节 + 状态重置过程` |

## 🎯 调试场景

### 场景 1：连接经常断开
```vim
" 1. 启用 DEBUG
:lua require("claudecode.logger").setup({ log_level = "debug" })

" 2. 查看断连原因
:!grep "disconnect" /tmp/claudecode_debug.log | tail -20
```

### 场景 2：重连失败
```vim
" 1. 启用 TRACE
:lua require("claudecode.logger").setup({ log_level = "trace" })

" 2. 触发测试
:ClaudeCodeTestDisconnect

" 3. 查看详细过程
:!grep -E "reconnect.*attempt" /tmp/claudecode_debug.log
```

### 场景 3：查看连接健康
```vim
" 查看健康状态
:ClaudeCodeConnectionHealth

" 生成详细报告
:ClaudeCodeConnectionReport

" 查看断连历史
:!tail -20 ~/.claude/logs/disconnects.log
```

## 💡 小技巧

### 1. 在 Neovim 中实时查看
```vim
" 垂直分屏打开日志
:vsplit /tmp/claudecode_debug.log

" 跳到末尾
:normal G

" 设置自动刷新
:set autoread | au CursorHold * checktime
```

### 2. 过滤特定模块
```bash
# 只看服务器日志
grep "\[server\]" /tmp/claudecode_debug.log

# 只看终端日志
grep "\[terminal\]" /tmp/claudecode_debug.log

# 组合过滤
grep -E "\[(server|terminal)\].*\[DEBUG\]" /tmp/claudecode_debug.log
```

### 3. 清理日志
```bash
# 方法 1：使用工具
./view_trace_logs.sh  # 选择 6

# 方法 2：手动清空
> /tmp/claudecode_debug.log

# 方法 3：保留最近 500 行
tail -500 /tmp/claudecode_debug.log > /tmp/claude_trim.log
mv /tmp/claude_trim.log /tmp/claudecode_debug.log
```

## ⚠️ 注意事项

1. **TRACE 会影响性能**，用完记得改回 INFO 或 DEBUG
2. **日志文件会快速增长**，定期清理
3. **生产环境用 WARN**，开发用 DEBUG，深度调试用 TRACE

## 🆘 需要帮助？

1. 查看完整指南：`docs/DEBUG_LOGGING_GUIDE.md`
2. 查看测试指南：`TEST_RECONNECT_GUIDE.md`
3. 报告问题时附上：
   - 日志文件相关部分
   - `:ClaudeCodeConnectionReport` 的输出
   - 你的配置