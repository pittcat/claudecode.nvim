# add-unsafe-command 分支功能文档

## 概述

本文档记录了 `add-unsafe-command` 分支中新增的所有功能和设计细节，用于指导未来从 main 分支合并时保护这些功能。

## 核心新增功能

### 1. 监控系统 (Monitoring System)

#### 功能描述
完整的状态监控系统，用于追踪 Claude Code 的运行状态和性能。

#### 关键文件
- `lua/claudecode/monitoring/` - 监控系统核心目录
  - `init.lua` - 监控系统主模块
  - `intelligent_state_analyzer.lua` - 智能状态分析器
  - `state_manager.lua` - 状态管理器
  - `modules/` - 各种监控模块

#### 新增命令
- `ClaudeCodeMonitoringStatus` - 显示监控状态
- `ClaudeCodeMonitoringStats` - 显示详细统计
- `ClaudeCodeMonitoringHistory` - 显示状态历史
- `ClaudeCodeMonitoringHealth` - 健康检查
- `ClaudeCodeMonitoringAnalyzeNow` - 手动触发分析

#### 设计要点
- 使用状态机管理连接状态（disconnected、idle、executing、completed）
- 智能分析器可以检测异常模式
- 支持历史记录和统计分析

### 2. 通知系统 (Notification System)

#### 功能描述
macOS 原生通知支持，在 Claude 完成任务时发送系统通知。

#### 配置结构
```lua
notification = {
  enabled = true,
  sound = "Glass",
  include_project_path = true,
  title_prefix = "Claude Code",
}
```

#### 关键文件
- `lua/claudecode/config.lua` - 包含 notification 配置
- `lua/claudecode/notification.lua` - 通知系统实现

#### 设计要点
- 使用 AppleScript 实现 macOS 原生通知
- 支持自定义声音和标题前缀
- 可以在通知中包含项目路径

### 3. 防闪烁优化 (Anti-Flicker Optimizations)

#### 功能描述
解决终端窗口切换时的红色闪烁问题。

#### 关键配置
- `fix_display_corruption = true` - 终端配置选项
- `auto_insert_mode = true` - 自动进入插入模式

#### 关键文件
- `lua/claudecode/terminal.lua` - 包含防闪烁逻辑
- `lua/claudecode/terminal/snacks.lua` - Snacks 提供器的防闪烁设置

#### 优化细节
```lua
-- 防闪烁的窗口选项
style = "minimal",
border = "none",
scrollback = 1000, -- 减少从 10000 到 1000

-- 窗口渲染选项
wo = {
  number = false,
  relativenumber = false,
  cursorline = false,
  cursorcolumn = false,
  signcolumn = "no",
}
```

### 4. ClaudeCodeUnsafe 和 ClaudeCodeContinue 命令

#### 功能描述
特殊的 Claude 启动命令，用于不同的使用场景。

#### 命令实现
- `ClaudeCodeUnsafe` - 使用 --unsafe 参数启动 Claude
- `ClaudeCodeContinue` - 使用 --continue 参数继续之前的会话

### 5. 缓冲区刷新功能

#### 功能描述
在保存文件后自动刷新所有相关缓冲区，确保视图同步。

#### 关键代码
```lua
-- lua/claudecode/tools/save_document.lua
local utils = require("claudecode.utils")
utils.refresh_buffers(params.filePath)
```

## 合并时的注意事项

### 1. 配置文件冲突处理

**文件**: `lua/claudecode/config.lua`

**策略**: 保留两边的配置
- ✅ 保持 `notification` 配置块
- ✅ 添加 main 分支的 `models` 配置块
- ✅ 在验证函数中包含两套配置的验证逻辑

### 2. 初始化文件命令冲突

**文件**: `lua/claudecode/init.lua`

**策略**: 合并所有命令
- ✅ 保持所有 `ClaudeCodeMonitoring*` 命令
- ✅ 添加 main 分支的 `ClaudeCodeSelectModel` 命令
- ✅ 保持 `M.open_with_model` 函数

### 3. 终端配置冲突

**文件**: `lua/claudecode/terminal.lua`

**策略**: 合并所有配置选项
- ✅ 保持 `fix_display_corruption` 配置
- ✅ 保持 `auto_insert_mode` 配置
- ✅ 添加 main 分支的 `snacks_win_opts` 配置

### 4. Snacks 提供器优化

**文件**: `lua/claudecode/terminal/snacks.lua`

**策略**: 保持防闪烁优化并支持自定义配置
- ✅ 保持所有防闪烁的窗口和缓冲区选项
- ✅ 使用 `vim.tbl_deep_extend` 合并用户的 `snacks_win_opts`

### 5. 工具返回格式

**文件**: `lua/claudecode/tools/save_document.lua`

**策略**: 同时支持两种功能
- ✅ 保持 `utils.refresh_buffers` 调用
- ✅ 返回 MCP 兼容的 JSON 格式

## 测试清单

合并后需要验证的功能：

1. **监控系统**
   - [ ] 所有监控命令正常工作
   - [ ] 状态转换正确记录
   - [ ] 智能分析器能正常运行

2. **通知系统**
   - [ ] macOS 通知能正常发送
   - [ ] 配置选项生效

3. **终端功能**
   - [ ] 无红色闪烁
   - [ ] 自动进入插入模式
   - [ ] 自定义 snacks 配置生效

4. **特殊命令**
   - [ ] ClaudeCodeUnsafe 正常工作
   - [ ] ClaudeCodeContinue 正常工作

5. **文件保存**
   - [ ] 保存后缓冲区正确刷新
   - [ ] 返回正确的 MCP 格式

## 合并步骤建议

1. **创建备份分支**
   ```bash
   git checkout -b backup-$(date +%Y%m%d)
   ```

2. **更新 main 分支**
   ```bash
   git checkout main
   git pull origin main
   ```

3. **合并时使用 no-commit**
   ```bash
   git checkout add-unsafe-command
   git merge --no-commit main
   ```

4. **手动解决冲突**
   - 按照上述策略处理每个冲突文件
   - 确保保留所有现有功能

5. **测试验证**
   - 运行测试套件
   - 手动测试关键功能

6. **提交合并**
   ```bash
   git commit -m "合并main分支: 保持[具体功能列表]"
   ```

## 关键原则

1. **功能保护**: 绝不删除或修改现有功能
2. **增量合并**: 只添加新功能，不替换现有功能
3. **配置兼容**: 确保新旧配置可以共存
4. **测试优先**: 合并后立即测试所有功能

---

**最后更新**: 2025-07-28
**维护者**: @pittcat