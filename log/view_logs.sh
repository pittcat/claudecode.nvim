#!/bin/bash

# 查看 Claude Code 调试日志的脚本

LOG_FILE="/Users/pittcat/.vim/plugged/claudecode.nvim/log/debug.log"

echo "=== Claude Code 调试日志查看器 ==="
echo "日志文件: $LOG_FILE"
echo ""

if [ ! -f "$LOG_FILE" ]; then
    echo "日志文件不存在，请先运行 Neovim 和 Claude Code"
    exit 1
fi

# 显示最后50行
echo "最后 50 行日志:"
echo "=========================================="
tail -n 50 "$LOG_FILE"
echo "=========================================="
echo ""
echo "要实时查看日志，请运行:"
echo "  tail -f $LOG_FILE"
