#!/usr/bin/env python3
"""
Neovim RPC Helper for Claude Island
使用 pynvim 库通过 msgpack-rpc 调用 Neovim
"""
import sys
import json
import msgpack
from pynvim import attach

def call_rpc(servername, lua_code, args=None):
    """
    通过 RPC 调用 Neovim Lua 函数
    
    Args:
        servername: Neovim socket 地址
        lua_code: 要执行的 Lua 代码
        args: 传递给 Lua 的参数列表
    
    Returns:
        执行结果的 JSON 字符串
    """
    try:
        # 连接到 Neovim
        nvim = attach('socket', path=servername)
        
        # 执行 Lua 代码
        result = nvim.api.exec_lua(lua_code, args or [])
        
        # 输出结果
        print(json.dumps(result, ensure_ascii=False))
        return 0
        
    except Exception as e:
        # 输出错误信息
        error_result = {
            "ok": False,
            "error": str(e),
            "trace_id": args[0].get("trace_id", "unknown") if args else "unknown"
        }
        print(json.dumps(error_result, ensure_ascii=False))
        return 1

def main():
    if len(sys.argv) < 3:
        print(json.dumps({"ok": False, "error": "Usage: rpc_helper.py <servername> <lua_code> [args_json]"}))
        return 1
    
    servername = sys.argv[1]
    lua_code = sys.argv[2]
    args = json.loads(sys.argv[3]) if len(sys.argv) > 3 else None

    return call_rpc(servername, lua_code, [args] if args else None)

if __name__ == "__main__":
    sys.exit(main())
