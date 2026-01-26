# 合并冲突报告（origin/main -> add-unsafe-command）

状态：合并进行中（尚未解决冲突，也未生成合并提交）。

## 概要
- 冲突文件：2 个
  - `lua/claudecode/server/init.lua`
  - `lua/claudecode/server/tcp.lua`
- 未跟踪文件：`debug_log.txt`（不属于本次合并内容）

## 问题点与建议

### 1) `lua/claudecode/server/init.lua`
**冲突范围**
- `ServerState` 字段（`clients`、`clients_by_session`）以及连接/断开时的维护逻辑。

**如果选择 `origin/main` 的风险**
- 当前分支在 `_handle_message` 中使用 `clients_by_session` 进行会话映射。
- 删除这些字段会导致 nil 访问或会话初始化、断开清理逻辑回退。

**建议**
- 保留当前分支的会话追踪字段与逻辑。
- 日志部分两边兼容，可保留现有实现。

**建议的解决方式**
- `clients` / `clients_by_session` 及连接/断开维护逻辑以当前分支为准。

### 2) `lua/claudecode/server/tcp.lua`
**冲突范围**
- EOF 断开处理方式。

**如果选择当前分支的风险**
- 当前分支直接调用 `on_disconnect` 与 `_remove_client`，而 main 已统一通过 `_disconnect_client` 做幂等与一致清理。
- 可能出现重复回调或清理路径不一致。

**建议**
- 使用 `origin/main` 的方式：EOF 路径走 `_disconnect_client`。
- reason 文本可用 "EOF"（仅影响日志）。

**建议的解决方式**
- EOF 分支改为 `M._disconnect_client(server, client, 1006, "EOF")`。

## 需要你确认的决策
请选择一种策略后我再继续处理冲突并完成合并：
1) 保留会话追踪（当前分支）+ EOF 走 `_disconnect_client`（推荐）
2) 完全对齐 main（去掉会话追踪逻辑）
3) 中止合并，改用更保守路径（如分批 cherry-pick 或分阶段合并）

