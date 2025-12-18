#!/bin/bash

# 清理 Claude Code 调试日志的脚本

LOG_FILE="/Users/pittcat/.vim/plugged/claudecode.nvim/log/debug.log"

echo "清理 Claude Code 调试日志..."
echo "日志文件: $LOG_FILE"

if [ -f "$LOG_FILE" ]; then
    # 备份当前日志
    BACKUP_FILE="${LOG_FILE}.backup.$(date -u +%Y%m%d_%H%M%S)"
    cp "$LOG_FILE" "$BACKUP_FILE"
    echo "已备份旧日志到: $BACKUP_FILE"

    # 清空日志文件
    > "$LOG_FILE"
    echo "已清空日志文件"

    # 在日志文件中写入新的开始标记
    echo "=== ClaudeCode Debug Session Started at $(date -u +"%Y-%m-%d %H:%M:%S") ===" > "$LOG_FILE"
    echo "日志已清空，可以开始新的调试会话"
else
    echo "日志文件不存在，创建新文件"
    mkdir -p "$(dirname "$LOG_FILE")"
    echo "=== ClaudeCode Debug Session Started at $(date -u +"%Y-%m-%d %H:%M:%S") ===" > "$LOG_FILE"
fi
