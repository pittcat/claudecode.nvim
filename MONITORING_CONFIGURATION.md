# Claude Code 监控系统配置指南

## 智能状态分析器配置

智能状态分析器支持灵活的配置选项，可以根据需要调整检查频率和状态确认阈值。

### 基本配置示例

```lua
require("claudecode").setup({
  monitoring = {
    enabled = true,
    auto_start = true,
    intelligent_analyzer = {
      -- 基本检查参数
      check_interval = 4000,                -- 检查间隔时间（毫秒），多久检查一次状态
      executing_timeout = 10000,            -- 执行状态超时时间（毫秒）
      lines_to_check = 30,                  -- 检查终端末尾行数
      
      -- 状态确认阈值配置
      idle_confirmation_threshold = 3,      -- idle状态确认次数，连续检测到N次才确认为idle
      executing_confirmation_threshold = 1, -- executing状态确认次数
      disconnected_confirmation_threshold = 2, -- disconnected状态确认次数
      waiting_confirmation_threshold = 1,   -- waiting状态确认次数
    },
  },
})
```

### 配置选项详细说明

#### 基本检查参数

- **check_interval** (默认: 4000)
  - 状态检查间隔时间，单位毫秒
  - 值越小检查越频繁，但会消耗更多资源
  - 建议范围：1000-10000毫秒

- **executing_timeout** (默认: 10000)
  - 执行状态超时时间，单位毫秒
  - 如果超过这个时间没有检测到执行活动，可能会判断为其他状态
  - 建议范围：5000-30000毫秒

- **lines_to_check** (默认: 30)
  - 检查终端缓冲区末尾行数
  - 值越大检查越全面，但处理速度可能更慢
  - 建议范围：10-100行

#### 状态确认阈值配置

这些配置控制需要连续检测到多少次相同状态才确认状态变化：

- **idle_confirmation_threshold** (默认: 3)
  - idle状态确认次数
  - 连续检测到N次内容无变化才确认为idle状态
  - 值越大越稳定，但响应较慢
  - 建议范围：1-10次

- **executing_confirmation_threshold** (默认: 1)
  - executing状态确认次数  
  - 检测到执行标识后立即确认为执行状态
  - 通常设为1以快速响应

- **disconnected_confirmation_threshold** (默认: 2)
  - disconnected状态确认次数
  - 连续检测到断开连接标识N次才确认
  - 避免网络波动造成的误判

- **waiting_confirmation_threshold** (默认: 1)
  - waiting状态确认次数
  - 内容还在变化时的状态确认次数

### 使用场景配置

#### 快速响应配置
适用于需要快速检测状态变化的场景：

```lua
intelligent_analyzer = {
  check_interval = 2000,                -- 2秒检查一次
  idle_confirmation_threshold = 2,      -- 2次确认idle
  executing_confirmation_threshold = 1,
  disconnected_confirmation_threshold = 1,
  waiting_confirmation_threshold = 1,
}
```

#### 稳定保守配置
适用于避免频繁状态切换的场景：

```lua
intelligent_analyzer = {
  check_interval = 6000,                -- 6秒检查一次
  idle_confirmation_threshold = 5,      -- 5次确认idle（30秒无变化）
  executing_confirmation_threshold = 2, -- 2次确认执行状态
  disconnected_confirmation_threshold = 3, -- 3次确认断开
  waiting_confirmation_threshold = 2,
}
```

#### 性能优化配置
适用于资源受限的环境：

```lua
intelligent_analyzer = {
  check_interval = 8000,                -- 8秒检查一次，减少CPU使用
  lines_to_check = 20,                  -- 只检查末尾20行
  idle_confirmation_threshold = 3,
  executing_confirmation_threshold = 1,
  disconnected_confirmation_threshold = 2,
  waiting_confirmation_threshold = 1,
}
```

### 配置验证

启动监控系统后，可以通过日志查看配置是否生效：

```
[ClaudeCode] [intelligent_analyzer] [INFO] Intelligent state analyzer started (interval: 4000ms, timeout: 10000ms, lines: 30, idle_threshold: 3)
[ClaudeCode] [intelligent_analyzer] [DEBUG] State confirmation thresholds: idle=3, executing=1, disconnected=2, waiting=1
```

### 监控命令

启用监控后，可以使用以下命令查看状态：

- `:ClaudeCodeMonitoringStatus` - 查看当前监控状态
- `:ClaudeCodeMonitoringStats` - 查看详细统计信息
- `:ClaudeCodeMonitoringHistory` - 查看状态变化历史
- `:ClaudeCodeMonitoringHealth` - 健康检查
- `:ClaudeCodeMonitoringAnalyzeNow` - 手动触发状态分析

### 注意事项

1. **检查间隔与确认次数的关系**：
   - 实际确认时间 = check_interval × confirmation_threshold
   - 例如：4秒间隔 × 3次确认 = 12秒确认idle状态

2. **资源消耗**：
   - 检查间隔越小，CPU使用率越高
   - 检查行数越多，内存使用越多

3. **响应性 vs 稳定性**：
   - 低阈值 = 快速响应，但可能不稳定
   - 高阈值 = 稳定但响应较慢

4. **中断检测**：
   - interrupted状态检测基于idle状态，受idle_confirmation_threshold影响
   - 只有在确认为idle后才会检查是否为interrupted类型