# Claude Code 调试日志

## 日志文件位置
```
/Users/pittcat/.vim/plugged/claudecode.nvim/log/debug.log
```

## 已添加的调试日志

### 1. **终端提供者选择日志** (terminal.lua)
- `[GET-PROVIDER]` - 记录提供者加载和选择过程
- 记录配置的类型和值
- 记录回退到 native 提供者的原因

### 2. **snacks 提供者日志** (terminal/snacks.lua)
- `[GET-JOB-CHANNEL]` - 记录 job_id 获取过程
- 尝试从多个位置获取 job_id:
  - terminal.job_id, terminal.jobid, terminal._job_id, terminal._jobid
  - 缓冲区变量: terminal_job_id, job_id, jobid
  - 缓冲区选项: channel
  - 终端方法: get_job_id()
- 记录所有可用的终端属性用于调试

### 3. **队列处理日志** (init.lua)
- `[CHANSEND-TAB]` - 记录 tab 模式下的 chansend 操作
- 记录提供者获取
- 记录 job_channel 获取
- 记录 chansend 调用结果

### 4. **立即广播日志** (init.lua)
- `[CHANSEND-TAB]` - 记录立即发送 @mention 的过程
- 与队列处理相同的日志级别

## 测试步骤

1. **启动 Neovim**
2. **配置 tab 模式**:
   ```lua
   require("claudecode").setup({
     terminal = {
       session_scope = "tab"
     },
     log_level = "debug"
   })
   ```
3. **打开两个标签页**
4. **在每个标签页启动 Claude Code**
5. **在不同标签页触发 @mention**
6. **检查日志文件**:
   ```bash
   tail -f /Users/pittcat/.vim/plugged/claudecode.nvim/log/debug.log
   ```

## 预期日志示例

### 正常情况 (成功)
```
[10:30:45.123] [ClaudeCode] [terminal] [GET-PROVIDER] Requesting provider, configured provider: string auto
[10:30:45.124] [ClaudeCode] [terminal] [GET-PROVIDER] Provider is 'auto', trying snacks first...
[10:30:45.125] [ClaudeCode] [terminal] [GET-PROVIDER] Snacks provider available, using it
[10:30:45.126] [ClaudeCode] [snacks] [GET-JOB-CHANNEL] scope_key: 1 terminal: true
[10:30:45.127] [ClaudeCode] [snacks] [GET-JOB-CHANNEL] Terminal buffer is valid
[10:30:45.128] [ClaudeCode] [snacks] [GET-JOB-CHANNEL] Found job_id at terminal.job_id: 12345
[10:30:45.129] [ClaudeCode] [queue] [CHANSEND-TAB] Processing @ mention in tab mode, tab: 1
[10:30:45.130] [ClaudeCode] [queue] [CHANSEND-TAB] Provider: found
[10:30:45.131] [ClaudeCode] [queue] [CHANSEND-TAB] get_job_channel method exists, calling it...
[10:30:45.132] [ClaudeCode] [queue] [CHANSEND-TAB] Job channel: 12345 type: number
[10:30:45.133] [ClaudeCode] [queue] [CHANSEND-TAB] About to send via chansend: @test.txt
[10:30:45.134] [ClaudeCode] [queue] [CHANSEND-TAB] Job channel value: 12345
[10:30:45.135] [ClaudeCode] [queue] [CHANSEND-TAB] chansend result - ok: true err: nil
[10:30:45.136] [ClaudeCode] [queue] [CHANSEND-TAB] SUCCESS: Sent @ mention via chansend to tab: 1 file: test.txt
```

### 错误情况 (job_id 未找到)
```
[10:30:45.123] [ClaudeCode] [terminal] [GET-PROVIDER] Requesting provider, configured provider: string auto
[10:30:45.124] [ClaudeCode] [terminal] [GET-PROVIDER] Provider is 'auto', trying snacks first...
[10:30:45.125] [ClaudeCode] [terminal] [GET-PROVIDER] Snacks provider available, using it
[10:30:45.126] [ClaudeCode] [snacks] [GET-JOB-CHANNEL] scope_key: 1 terminal: true
[10:30:45.127] [ClaudeCode] [snacks] [GET-JOB-CHANNEL] Terminal buffer is valid
[10:30:45.128] [ClaudeCode] [snacks] [GET-JOB-CHANNEL] Available terminal properties:
[10:30:45.129] [ClaudeCode] [snacks] [GET-JOB-CHANNEL]    buf = 3
[10:30:45.130] [ClaudeCode] [snacks] [GET-JOB-CHANNEL]    win = 1001
[10:30:45.131] [ClaudeCode] [snacks] [GET-JOB-CHANNEL]    toggle = function
[10:30:45.132] [ClaudeCode] [snacks] [GET-JOB-CHANNEL]    close = function
[10:30:45.133] [ClaudeCode] [snacks] [GET-JOB-CHANNEL] No job_id found, returning nil
[10:30:45.134] [ClaudeCode] [queue] [CHANSEND-TAB] Processing @ mention in tab mode, tab: 1
[10:30:45.135] [ClaudeCode] [queue] [CHANSEND-TAB] Provider: found
[10:30:45.136] [ClaudeCode] [queue] [CHANSEND-TAB] get_job_channel method exists, calling it...
[10:30:45.137] [ClaudeCode] [queue] [CHANSEND-TAB] Job channel: nil type: nil
[10:30:45.138] [ClaudeCode] [queue] [CHANSEND-TAB] ERROR: No job channel found for tab: 1
```

## 常见问题诊断

### 问题 1: job_id 为空
- **原因**: snacks.terminal 存储 job_id 的位置不在我们尝试的位置
- **解决**: 查看 "Available terminal properties" 日志，找到正确的 job_id 位置并更新代码

### 问题 2: 提供者为空
- **原因**: 配置错误或依赖缺失
- **解决**: 查看 "[GET-PROVIDER]" 日志了解具体原因

### 问题 3: chansend 失败
- **原因**: job_channel 无效或 vim.fn.chansend 调用错误
- **解决**: 查看 "[CHANSEND-TAB] chansend result" 日志
