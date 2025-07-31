# Claude Code 闪烁检测系统

## 概述

Claude Code Neovim 插件的闪烁检测系统提供了一个量化分析终端闪烁问题的解决方案。该系统能够客观地测量模式变化频率、重绘事件和闪烁模式，帮助诊断和解决终端窗口的视觉闪烁问题。

**v1.1 准确性改进**: 基于用户反馈，系统集成了 anti-flicker 状态验证和多条件综合判断算法，显著提高了检测准确性，减少假阳性和假阴性。

## 功能特性

### 🔍 量化检测能力

- **模式变化监控**: 检测 Neovim 模式的快速切换 (n → nt → t)
- **重绘事件跟踪**: 监控窗口重绘频率和模式
- **闪烁严重程度评分**: 基于频率和影响程度的 1-10 分评分系统
- **实时统计**: 提供当前检测状态和事件计数

### ⚙️ 智能分析算法

- **Anti-flicker 状态验证**: 集成 anti-flicker 系统状态作为验证信号，减少误判
- **多条件综合判断**: 5个条件的评分系统，需满足4/5条件才确认闪烁
- **智能模式识别**: 区分正常终端操作和真实闪烁模式
- **时序集中度分析**: 检测事件在短时间内的集中程度
- **自适应阈值**: 可配置的检测阈值以适应不同环境
- **去抖动机制**: 防止正常光标移动被误判为闪烁
- **内存管理**: 自动清理历史数据以防止内存泄漏

### 📊 详细报告系统

- **实时状态监控**: 获取当前检测状态和统计信息
- **综合分析报告**: 包含检测概要、建议和历史数据
- **事件历史记录**: 保留最近的闪烁事件用于分析

## 配置选项

在您的 Neovim 配置中启用闪烁检测：

```lua
require("claudecode").setup({
  flicker_detection = {
    enabled = true,          -- 启用闪烁检测系统
    auto_start = false,      -- 进入终端时自动开始检测
    auto_fix = false,        -- 检测到闪烁时自动应用修复
    thresholds = {
      rapid_mode_changes = 12,   -- 每秒模式变化次数阈值
      excessive_redraws = 25,    -- 每秒重绘次数阈值
      flicker_window = 2.0,      -- 检测时间窗口（秒）
      debounce_interval = 50,    -- 去抖动间隔（毫秒）
    },
  },
})
```

### 配置参数说明

| 参数 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `enabled` | boolean | false | 是否启用闪烁检测系统 |
| `auto_start` | boolean | false | 进入终端缓冲区时自动开始检测 |
| `auto_fix` | boolean | false | 检测到闪烁时自动应用修复措施 |
| `rapid_mode_changes` | number | 12 | 触发闪烁警报的每秒模式变化次数 |
| `excessive_redraws` | number | 25 | 触发重绘警报的每秒重绘次数 |
| `flicker_window` | number | 2.0 | 分析闪烁模式的时间窗口（秒） |
| `debounce_interval` | number | 50 | 光标移动去抖动间隔（毫秒） |

## 用户命令

### 基本控制命令

#### `:ClaudeCodeFlickerStart`
开始闪烁检测分析。

```vim
:ClaudeCodeFlickerStart
```

#### `:ClaudeCodeFlickerStop`
停止闪烁检测并显示简要报告。

```vim
:ClaudeCodeFlickerStop
```

### 状态查询命令

#### `:ClaudeCodeFlickerStatus`
显示当前检测状态和实时统计。

```vim
:ClaudeCodeFlickerStatus
```

输出示例：
```
闪烁检测运行中 (15.3秒) - 事件: 2闪烁, 45模式变化, 120重绘
```

#### `:ClaudeCodeFlickerReport`
生成详细的闪烁检测报告。

```vim
:ClaudeCodeFlickerReport
```

输出示例：
```
=== Claude Code 闪烁检测报告 ===
检测状态: 激活
运行时间: 30.5 秒

检测概要:
  闪烁事件: 3
  模式变化: 78
  重绘事件: 245
  平均严重程度: 6.33

建议:
  • Moderate flicker detected - enable anti-flicker optimizations
  • Use :ClaudeCodeFlickerFix to apply targeted fixes
```

## 检测机制详解

### 闪烁检测算法

#### 1. 模式变化检测
监控 Neovim 模式变化事件，特别关注：
- 正常模式 (n) 到终端正常模式 (nt) 的切换
- 终端正常模式 (nt) 到终端模式 (t) 的切换
- 快速的往返切换模式

#### 2. 重绘频率分析
跟踪以下重绘事件：
- 窗口大小调整 (`VimResized`)
- 缓冲区进入/离开 (`BufEnter`/`BufLeave`)
- 窗口焦点变化 (`WinEnter`/`WinLeave`)
- 光标移动 (`CursorMoved` - 经过去抖动处理)

#### 3. 严重程度评分
基于以下因素计算闪烁严重程度（1-10分）：
- **基础严重程度**:
  - 快速模式变化: 8分（高严重程度）
  - 过度重绘: 6分（中高严重程度）
- **频率加权**: 根据最近2秒内的闪烁频率增加评分
- **上限控制**: 最高评分限制为10分

### 时间窗口分析

系统使用滑动时间窗口来分析闪烁模式：

```lua
-- 默认时间窗口配置
flicker_window = 2.0  -- 2秒时间窗口
```

在这个时间窗口内：
- 统计模式变化次数
- 统计重绘事件次数
- 计算每秒平均频率
- 与配置阈值进行比较

### 去抖动机制

为防止正常操作被误判为闪烁：

```lua
debounce_interval = 50  -- 50毫秒去抖动间隔
```

该机制确保：
- 光标移动事件不会过于频繁地触发检测
- 快速连续的模式变化会被适当过滤
- 减少误报率，提高检测准确性

## 使用场景

### 1. 诊断终端闪烁问题

当您在使用 Claude Code 时遇到终端闪烁：

```vim
" 1. 开始检测
:ClaudeCodeFlickerStart

" 2. 进行正常的终端操作（重现闪烁）
" 3. 一段时间后查看状态
:ClaudeCodeFlickerStatus

" 4. 停止检测并查看报告
:ClaudeCodeFlickerStop
:ClaudeCodeFlickerReport
```

### 2. 配置优化验证

在调整配置后验证改进效果：

```vim
" 应用配置更改前
:ClaudeCodeFlickerStart
" ... 测试操作 ...
:ClaudeCodeFlickerReport  " 记录基线数据

" 应用配置更改后
:ClaudeCodeFlickerStart
" ... 相同测试操作 ...
:ClaudeCodeFlickerReport  " 比较改进效果
```

### 3. 性能监控

长期监控终端性能：

```lua
-- 启用自动检测
require("claudecode").setup({
  flicker_detection = {
    enabled = true,
    auto_start = true,  -- 自动开始检测
  },
})
```

## 技术实现细节

### 事件监听器

检测系统使用 Neovim 的 autocommand 系统监听相关事件：

```lua
-- 模式变化监听
vim.api.nvim_create_autocmd("ModeChanged", {
  group = "FlickerDetection",
  callback = function(args)
    M.on_mode_changed(args.match)
  end,
})

-- 重绘事件监听
vim.api.nvim_create_autocmd({"WinEnter", "WinLeave", "BufEnter", "BufLeave"}, {
  group = "FlickerDetection",
  callback = function(args)
    M.on_window_event(args.event)
  end,
})
```

### 数据结构

#### 事件记录结构
```lua
local event = {
  type = "mode_change",           -- 事件类型
  timestamp = 1234567890.123,     -- 高精度时间戳
  transition = "n:nt",            -- 模式转换
  from_mode = "n",                -- 源模式
}
```

#### 闪烁事件结构
```lua
local flicker_event = {
  type = "rapid_mode_changes",    -- 闪烁类型
  timestamp = 1234567890.123,     -- 检测时间
  trigger = event,                -- 触发事件
  severity = 8.5,                 -- 严重程度评分
}
```

### 内存管理

系统实现了自动内存管理机制：

```lua
-- 历史记录限制
history_limit = 100

-- 自动清理函数
function M.trim_history(history)
  while #history > thresholds.history_limit do
    table.remove(history, 1)  -- 移除最旧的记录
  end
end
```

## 故障排除

### 常见问题

#### 1. 检测系统不可用

**错误**: "Flicker detection not available"

**解决方案**:
```lua
-- 确保在配置中启用闪烁检测
require("claudecode").setup({
  flicker_detection = {
    enabled = true,  -- 必须设置为 true
  },
})
```

#### 2. 检测过于敏感

**症状**: 大量误报闪烁事件

**解决方案**: 调整检测阈值
```lua
require("claudecode").setup({
  flicker_detection = {
    thresholds = {
      rapid_mode_changes = 20,   -- 增加阈值
      excessive_redraws = 35,    -- 增加阈值
      debounce_interval = 100,   -- 增加去抖动间隔
    },
  },
})
```

#### 3. 检测不够敏感

**症状**: 明显的闪烁未被检测到

**解决方案**: 降低检测阈值
```lua
require("claudecode").setup({
  flicker_detection = {
    thresholds = {
      rapid_mode_changes = 8,    -- 降低阈值
      excessive_redraws = 15,    -- 降低阈值
      flicker_window = 1.5,      -- 缩短时间窗口
    },
  },
})
```

### 调试技巧

#### 1. 启用详细日志
```lua
require("claudecode").setup({
  log_level = "debug",  -- 启用调试日志
})
```

#### 2. 查看日志文件
```bash
tail -f /tmp/claudecode_debug.log
```

#### 3. 手动测试检测
```vim
:ClaudeCodeFlickerStart
" 手动触发一些可能导致闪烁的操作
:ClaudeCodeFlickerStatus
:ClaudeCodeFlickerReport
```

## 高级配置

### 环境特定配置

```lua
-- 针对不同终端的配置
local config = {
  flicker_detection = {
    enabled = true,
    thresholds = {},
  },
}

-- 根据终端类型调整
if vim.env.TERM_PROGRAM == "iTerm.app" then
  config.flicker_detection.thresholds.rapid_mode_changes = 15
elseif vim.env.TERM_PROGRAM == "Apple_Terminal" then
  config.flicker_detection.thresholds.rapid_mode_changes = 10
end

require("claudecode").setup(config)
```

### 条件启用

```lua
-- 仅在特定条件下启用闪烁检测
local should_enable_flicker_detection = function()
  -- 仅在 macOS 上启用
  if vim.fn.has('mac') == 0 then return false end
  
  -- 仅在使用 snacks 终端时启用
  local has_snacks = pcall(require, 'snacks')
  return has_snacks
end

require("claudecode").setup({
  flicker_detection = {
    enabled = should_enable_flicker_detection(),
  },
})
```

## API 参考

### 核心函数

#### `start_detection(custom_thresholds)`
开始闪烁检测

**参数**:
- `custom_thresholds` (table, optional): 自定义检测阈值

**返回**: 无

#### `stop_detection()`
停止闪烁检测

**返回**: 
- `table`: 最终检测报告

#### `get_flicker_report()`
获取当前检测报告

**返回**:
- `table`: 详细检测报告，包含以下字段：
  - `detection_active`: 检测状态
  - `detection_duration`: 检测持续时间
  - `summary`: 检测概要统计
  - `recent_activity`: 最近活动统计
  - `thresholds`: 当前使用的阈值
  - `recommendations`: 基于检测结果的建议

#### `get_current_stats()`
获取实时统计信息

**返回**:
- `table`: 当前统计信息，包含：
  - `active`: 检测是否激活
  - `uptime`: 运行时间
  - `events`: 事件计數
  - `recent_flickers`: 最近闪烁事件数

## 版本历史

### v1.1.0 (当前版本)
- ✅ **准确性重大改进**: Anti-flicker 状态验证集成
- ✅ **多条件判断算法**: 5条件评分系统（需4/5条件确认）
- ✅ **智能模式识别**: 区分正常操作与真实闪烁
- ✅ **时序分析**: 事件集中度检测
- ✅ **优化阈值**: 平衡准确性的检测参数

### v1.0.0
- ✅ 初始发布
- ✅ 量化闪烁检测算法
- ✅ 用户命令界面
- ✅ 配置系统集成
- ✅ 详细报告生成
- ✅ 内存管理机制

### 未来计划
- 🔄 自动修复机制增强
- 🔄 机器学习优化检测算法
- 🔄 用户反馈集成系统
- 🔄 统计分析报告

## 贡献指南

如果您想为闪烁检测系统贡献代码或反馈：

1. **报告问题**: 在 GitHub Issues 中详细描述遇到的闪烁问题
2. **提供配置**: 分享您的系统配置和终端环境信息
3. **测试反馈**: 尝试不同的阈值配置并分享效果
4. **代码贡献**: 提交 Pull Request 改进检测算法

## 相关文档

- [CLAUDE.md](./CLAUDE.md) - 项目主要文档
- [README.md](./README.md) - 项目介绍
- [CONFIG.md](./CONFIG.md) - 完整配置指南

---

*该文档版本: v1.0.0*  
*最后更新: 2024-07-31*  
*作者: Claude Code Development Team*