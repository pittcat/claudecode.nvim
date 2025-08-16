# claudecode.nvim Cursor 规则

这个目录包含了为 claudecode.nvim 项目生成的 Cursor AI 规则，旨在帮助开发人员理解项目结构、编码约定和最佳实践。

## 已创建的规则

### 1. [project-structure.mdc](./project-structure.mdc)
- **应用范围**: 所有文件 (`alwaysApply: true`)
- **内容**: 项目整体架构、模块组织、设计原则
- **用途**: 帮助理解代码库的总体结构和各模块间的关系

### 2. [lua-conventions.mdc](./lua-conventions.mdc)
- **应用范围**: 所有 Lua 文件 (`globs: *.lua`)
- **内容**: Lua 编码风格、模块结构、类型注解、错误处理模式
- **用途**: 确保新代码遵循项目的 Lua 编程约定

### 3. [testing-patterns.mdc](./testing-patterns.mdc)
- **应用范围**: 测试文件 (`globs: tests/**/*.lua,*_spec.lua`)
- **内容**: Busted 测试框架、三层测试策略、Mock 对象模式
- **用途**: 指导测试编写和测试架构设计

### 4. [neovim-plugin-development.mdc](./neovim-plugin-development.mdc)
- **应用范围**: 手动触发 (`description`)
- **内容**: Neovim 插件开发模式、用户命令、异步编程、终端集成
- **用途**: Neovim 插件特定的开发模式和最佳实践

### 5. [configuration-and-types.mdc](./configuration-and-types.mdc)
- **应用范围**: 手动触发 (`description`)
- **内容**: 类型系统设计、配置管理、验证模式、状态管理
- **用途**: 配置系统和类型定义的模式指南

### 6. [websocket-mcp-patterns.mdc](./websocket-mcp-patterns.mdc)
- **应用范围**: 手动触发 (`description`)
- **内容**: WebSocket 服务器实现、MCP 协议、帧处理、连接管理
- **用途**: 协议实现和网络编程的特定模式

## 如何使用这些规则

### 自动应用的规则
- `project-structure.mdc` 会自动应用到所有对话中
- `lua-conventions.mdc` 会在处理 Lua 文件时自动应用
- `testing-patterns.mdc` 会在处理测试文件时自动应用

### 手动调用的规则
其他规则可以通过在 Cursor 中引用来手动应用：
```
@neovim-plugin-development 我需要添加一个新的用户命令
@configuration-and-types 如何验证新的配置选项？
@websocket-mcp-patterns 实现新的 MCP 工具时需要注意什么？
```

## 规则的价值

这些规则基于对 claudecode.nvim 代码库的深入分析，包含了：

1. **真实代码模式**: 从实际代码中提取的模式和约定
2. **架构理解**: 对 WebSocket、MCP 协议、Neovim 插件架构的深度理解
3. **最佳实践**: 测试策略、错误处理、资源管理等最佳实践
4. **类型安全**: LuaLS 类型注解和配置验证模式
5. **性能考虑**: 异步编程、内存管理、批处理等性能优化模式

## 维护和更新

当项目架构或约定发生变化时，应相应更新这些规则以保持其相关性和准确性。

---

*这些规则是通过分析 claudecode.nvim 代码库自动生成的，旨在帮助开发人员更好地理解和贡献代码。*
