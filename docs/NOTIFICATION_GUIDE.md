# Claude Code 通知功能使用指南

## 概述

Claude Code 通知功能可以在任务完成时自动发送 macOS 系统通知，让您无需手动检查终端状态就能及时了解任务进展。

## 功能特性

- **自动检测任务完成**：当 Claude Code 从执行状态转为空闲状态时自动触发
- **智能过滤**：仅在任务正常完成时发送通知，用户主动中断时不会发送
- **项目信息**：通知中包含当前项目名称和路径
- **可配置选项**：支持自定义通知声音、内容格式等
- **macOS 原生支持**：使用 AppleScript 调用系统通知中心

## 配置选项

在 `require("claudecode").setup({})` 中配置通知选项：

```lua
require("claudecode").setup({
  notification = {
    enabled = true,                    -- 是否启用通知（默认：true）
    sound = "Glass",                   -- 通知声音（默认："Glass"）
    include_project_path = true,       -- 是否在通知中包含项目路径（默认：true）
    title_prefix = "Claude Code",      -- 通知标题前缀（默认："Claude Code"）
  },
  -- 其他配置...
})
```

### 配置参数详解

| 参数 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `enabled` | boolean | `true` | 是否启用通知功能 |
| `sound` | string | `"Glass"` | 通知声音名称（macOS 系统声音） |
| `include_project_path` | boolean | `true` | 是否在通知内容中包含项目完整路径 |
| `title_prefix` | string | `"Claude Code"` | 通知标题前缀（当不显示项目路径时使用） |

### 可用的 macOS 通知声音

常用的 macOS 系统通知声音包括：
- `"Glass"` - 默认，清脆的玻璃声
- `"Basso"` - 低沉的提示音
- `"Blow"` - 吹气声
- `"Bottle"` - 瓶子声
- `"Frog"` - 青蛙声
- `"Funk"` - 放克音效
- `"Hero"` - 英雄音效
- `"Morse"` - 摩斯电码声
- `"Ping"` - 乒乓声
- `"Pop"` - 弹出声
- `"Purr"` - 猫咪呼噜声
- `"Sosumi"` - 经典 Mac 声音
- `"Submarine"` - 潜水艇声
- `"Tink"` - 叮当声

## 通知触发时机

通知会在以下情况下自动发送：

✅ **会发送通知的情况**：
- Claude Code 执行命令、分析代码等任务后正常完成
- 任务执行过程中没有用户主动中断
- 智能状态分析器检测到从 `executing` 状态转为 `idle` 状态

❌ **不会发送通知的情况**：
- 用户主动中断任务（如按 Ctrl+C 或 `[Request interrupted by user]`）
- 通知功能被禁用（`enabled = false`）
- 非 macOS 系统或缺少 `osascript` 命令
- 任务状态没有发生变化（如一直处于空闲状态）

## 通知内容格式

### 默认格式（include_project_path = true）
```
标题：项目名称（如：claudecode.nvim）
内容：Claude Code 任务已完成
     路径: /Users/pittcat/.vim/plugged/claudecode.nvim
声音：Glass
```

### 简化格式（include_project_path = false）
```
标题：Claude Code
内容：Claude Code 任务已完成
声音：Glass
```

## 使用示例

### 基本使用
```lua
-- 使用默认配置启用通知
require("claudecode").setup({
  notification = {
    enabled = true,
  }
})
```

### 自定义配置
```lua
-- 自定义通知设置
require("claudecode").setup({
  notification = {
    enabled = true,
    sound = "Hero",                    -- 使用英雄音效
    include_project_path = false,      -- 不显示完整路径
    title_prefix = "AI Assistant",     -- 自定义标题前缀
  }
})
```

### 禁用通知
```lua
-- 完全禁用通知功能
require("claudecode").setup({
  notification = {
    enabled = false,
  }
})
```

## 故障排除

### 通知不显示

1. **检查系统支持**：
   ```vim
   :lua print(require("claudecode.utils.notification").is_supported())
   ```
   应该返回 `true`。如果返回 `false`，检查：
   - 是否为 macOS 系统
   - `osascript` 命令是否可用

2. **检查配置**：
   ```vim
   :lua print(vim.inspect(require("claudecode.utils.notification").get_config()))
   ```
   确认 `enabled = true`

3. **检查日志**：
   设置调试日志级别查看详细信息：
   ```lua
   require("claudecode").setup({
     log_level = "debug",
     notification = { enabled = true }
   })
   ```

### 通知声音不播放

- 检查 macOS 系统偏好设置中的通知声音设置
- 确认指定的声音名称在系统中存在
- 尝试使用其他声音名称（如 `"Glass"` 或 `"Basso"`）

### 通知内容显示异常

- 检查项目路径是否包含特殊字符
- 如果路径过长，考虑设置 `include_project_path = false`

## 高级用法

### 编程方式发送通知

您也可以在代码中直接调用通知功能：

```lua
local notification = require("claudecode.utils.notification")

-- 发送任务完成通知
notification.send_task_completion_notification({
  message = "自定义任务完成消息",
  include_project = true
})

-- 发送自定义通知
notification.send_notification("自定义标题", "自定义内容", "Basso")
```

### 检查通知支持状态

```lua
local notification = require("claudecode.utils.notification")

if notification.is_supported() then
  print("系统支持通知功能")
else
  print("系统不支持通知功能")
end
```

## 系统要求

- **操作系统**：macOS（其他系统暂不支持）
- **依赖命令**：`osascript`（macOS 自带）
- **Neovim 版本**：>= 0.8.0

## 相关文件

- `lua/claudecode/utils/notification.lua` - 通知功能实现
- `lua/claudecode/config.lua` - 配置选项定义
- `lua/claudecode/monitoring/intelligent_state_analyzer.lua` - 状态分析和通知触发
- `lua/claudecode/init.lua` - 模块初始化

## 更多信息

- 通知功能基于 Claude Code 的智能状态分析系统
- 状态检测间隔默认为 4 秒，可在监控配置中调整
- 所有通知操作都会记录在日志中，可通过设置 `log_level = "debug"` 查看详细信息