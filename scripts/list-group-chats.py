#!/usr/bin/env python3
"""列出 iMessage 中的所有群组对话（participants > 1），输出 chat_id。

Usage:
    python3 list-group-chats.py

依赖: imsg bridge 必须已运行在 localhost:8899
"""

import socket, json, time, sys

HOST, PORT = '127.0.0.1', 8899

def rpc(method, params=None, timeout=5):
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.settimeout(timeout)
    s.connect((HOST, PORT))
    s.sendall((json.dumps({
        'jsonrpc': '2.0', 'id': '1', 'method': method,
        'params': params or {}
    }) + '\n').encode())
    time.sleep(1.5)
    buf = b''
    while True:
        try:
            d = s.recv(8192)
            if not d: break
            buf += d
        except socket.timeout: break
    s.close()
    return json.loads(buf.decode())

try:
    resp = rpc('chats.list', {'limit': 50})
except ConnectionRefusedError:
    print("❌ imsg bridge 未运行。请先启动：")
    print("   open ~/.hermes/skills/custom/nomad-imessage/references/imsg-bridge.command")
    sys.exit(1)

if 'error' in resp:
    print(f"❌ {resp['error']['message']}")
    sys.exit(1)

chats = resp['result']['chats']
groups = [c for c in chats if len(c.get('participants', [])) > 1]
singles = [c for c in chats if len(c.get('participants', [])) <= 1]

print(f"\n📊 总计 {len(chats)} 个对话 | 群组 {len(groups)} | 单人 {len(singles)}\n")

if groups:
    print("=" * 60)
    for c in groups:
        name = c.get('display_name', '(未命名群组)')
        cid = c.get('chat_id')
        handles = [p.get('handle', '?') for p in c.get('participants', [])]
        print(f"🔵 {name}")
        print(f"   chat_id: {cid}")
        print(f"   participants ({len(handles)}): {', '.join(handles)}")
        print()
else:
    print("没有找到群组对话。")
