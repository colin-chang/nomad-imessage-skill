---
name: nomad-imessage
description: "🧩 macOS 通用 Agent Skill — 通过 imsg Bridge Daemon（JSON-RPC over TCP）让任何 AI Agent 获得 iMessage/SMS 发送能力。解决 macOS Full Disk Access 限制，提供可靠的送达确认。适用于 Hermes Agent、Claude Code、OpenCode、Codex 及任何 macOS 自动化脚本。"
version: 2.0.0
author: Colin Chang
license: MIT
platforms: [macos]
metadata:
  hermes:
    tags: [iMessage, SMS, messaging, macOS, Apple, bridge, FDA]
prerequisites:
  commands: [tmux, socat, python3, imsg]
---

# iMessage Bridge — 通过 TCP 桥接发送 iMessage

> 🧩 **macOS 通用 Agent Skill** — 平台无关，任何能跑 Python 的 AI Agent 均可使用。
> 核心机制：imsg Bridge Daemon（socat + JSON-RPC over TCP），继承 Terminal.app 的 FDA 权限链。

通过 **imsg Bridge Daemon**（socat + JSON-RPC over TCP）发送 iMessage/SMS，
具备可靠的送达确认（数据库级 `guid` 验证）。

## 为什么需要这个

macOS 的"完全磁盘访问"（FDA）仅接受 `.app` bundle，AI Agent（Python/Node 进程）
**无法**被授予 FDA。但 Terminal.app 可拥有 FDA，其子进程自动继承。

**本方案**：从 Terminal.app 启动 TCP 桥接守护进程，Agent 通过 Python socket
发 JSON-RPC → `localhost:8899`，桥接进程继承 FDA，可完整读写 `chat.db`。

参考：OpenClaw #5116 — FDA 通过终端进程链继承的原理验证。

## 架构

```
Agent (无 FDA)
    │  Python socket 127.0.0.1:8899  ← JSON-RPC
    ▼
socat TCP-LISTEN:8899 (tmux 后台)
    │  fork + exec
    ▼
imsg rpc (FDA ✅ 继承自 Terminal.app)
    ├─ ~/Library/Messages/chat.db
    └─ AppleScript → Messages.app 发送
```

## 前置条件（一次性）

1. `brew install socat`
2. `brew install steipete/tap/imsg`
3. Terminal.app（`/System/Applications/Utilities/Terminal.app`）在
   **系统设置 → 隐私与安全性 → 完全磁盘访问权限** 中已授权
4. Messages.app 已登录 iMessage

## 快速开始

### 1. 启动 Bridge

```bash
open <SKILL_DIR>/references/imsg-bridge.command
```

> 你需要在使用前手动启动一次 bridge（Mac 重启后也需要）。自动化场景请用下方的「自包含模式」——代码内部会自动检测并启动 bridge。

### 2. 发送消息

```python
import socket, json, time

s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
s.connect(('127.0.0.1', 8899))
s.settimeout(10)

payload = json.dumps({
    'jsonrpc': '2.0',
    'id': '1',
    'method': 'send',
    'params': {
        'to': 'recipient@example.com',
        'text': '你好，这是一条测试消息'
    }
}) + '\n'

s.sendall(payload.encode())
time.sleep(1)

try:
    resp = s.recv(4096).decode()
    print(resp)
except socket.timeout:
    print('TIMEOUT — 消息通常已发出，严禁重试')

s.close()
```

### 3. 判断结果

```
✅ 成功
   {"jsonrpc":"2.0","id":"1","result":{"ok":true,"transport":"applescript","id":1979,"guid":"8DF..."}}
   → 有 "guid" 字段 = 数据库已确认。停止，不重试。

⚠️ 提交但未确认
   {"jsonrpc":"2.0","id":"1","result":{"ok":true}}
   → 无 "guid" 字段。消息已提交但未在数据库中观测到。不重试。

⚠️ 空响应 / TIMEOUT
   → 连接在收到响应前断开，但消息通常已经发出去了。严禁重试！

❌ 失败
   {"jsonrpc":"2.0","id":"1","error":{"code":-32000,"message":"..."}}
   → 连接被拒绝。检查 bridge 是否在运行。
```

## 长文本 / Markdown 发送

当消息包含换行、Markdown、emoji 时：

```python
import socket, json, time

report = """<完整内容，直接内联，保留所有 Markdown 格式>"""

s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
s.connect(('127.0.0.1', 8899))
s.settimeout(10)

payload = json.dumps({
    'jsonrpc': '2.0',
    'id': '1',
    'method': 'send',
    'params': {
        'to': 'recipient@example.com',
        'text': report
    }
}) + '\n'

s.sendall(payload.encode())
time.sleep(1)

try:
    resp = s.recv(4096).decode()
    print(resp)
except socket.timeout:
    print('TIMEOUT — 消息通常已发出，严禁重试')

s.close()
```

## 可用 JSON-RPC 方法

| 方法 | 用途 |
|------|------|
| `send` | 发送文本/文件（支持 `to` 单人 + `chat_id` 群组两种目标） |
| `chats.list` | 列出最近对话（含群组，群聊特征 `participants.length > 1`） |
| `messages.history` | 查聊天历史 |
| `watch.subscribe` | 实时监听新消息 |
| `react` | Tapback 快捷回复 |

协议文档：https://imsg.sh/rpc.html

## 发送到群组

`imsg` **支持向已存在的群组发送消息**，但不能创建新群组。通过 `chat_id` 目标模式实现。

> 💡 **快速查群组 chat_id**：直接在 Terminal 跑 `imsg chats list`，方括号里的数字就是 `chat_id`。
> 发送必须走 JSON-RPC bridge，不要用 `imsg send` CLI（会绕过 bridge 架构，且 `imsg` 二进制需 FDA）。

### Step 1：获取群组 chat_id

通过 bridge 的 `chats.list`，群聊特征是 `participants.length > 1`：

```python
import socket, json, time

s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
s.settimeout(5)
s.connect(('127.0.0.1', 8899))
s.sendall((json.dumps({
    'jsonrpc': '2.0', 'id': '1', 'method': 'chats.list',
    'params': {'limit': 30}
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

data = json.loads(buf.decode())
for c in data['result']['chats']:
    p = c.get('participants', [])
    cid = c.get('chat_id')
    name = c.get('display_name', '?')
    handles = [x.get('handle', '?') for x in p]
    if len(p) > 1:
        print(f'[GROUP] chat_id={cid}  "{name}"  → {handles}')
```

### Step 2：用 `chat_id` 通过 bridge 发送

```python
s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
s.settimeout(10)
s.connect(('127.0.0.1', 8899))
s.sendall((json.dumps({
    'jsonrpc': '2.0', 'id': '2', 'method': 'send',
    'params': {
        'chat_id': 12,              # ← 群组 chat_id
        'text': '大家好，这是一条群发消息'
    }
}) + '\n').encode())
time.sleep(1)

try:
    resp = s.recv(4096).decode()
    print(resp)
except socket.timeout:
    print('TIMEOUT — 消息通常已发出，严禁重试')
s.close()
```

> ⚠️ **transport 说明**：默认 `transport: "auto"`，优先 IMCore bridge → 回退 AppleScript。
> `transport: "bridge"` 需要 **关闭 SIP**（`imsg launch` 注入 Messages.app），普通用户无需指定。
> SIP 开启时 AppleScript 是唯一可用 transport，不影响消息送达。

### 两种发送模式对比

| 模式 | 参数 | 适用场景 | 能否群发 |
|------|------|---------|---------|
| Direct send | `to`（单人邮箱/号码） | 一对一私聊 | ❌ |
| Chat target | `chat_id` / `chat_identifier` / `chat_guid` | 已有对话（含群组） | ✅ |

> ⚠️ **限制**：`imsg` 不能创建新群组，只能往 Messages.app 中已有的群聊发送。
> 群聊的 `chat_id` 是稳定的整数，找到后可以记下来直接复用，无需每次 `chats.list`。

## ⚠️ 媒体发送：视频压缩警告

通过 iMessage 发送视频时，**Apple 服务器会强制将视频转码为 720p**（无论源文件质量如何）。
图片在正常大小范围内不受影响，超大图片会缩减至 2048px 长边。

- iCloud Link（Photos → Share → 拷贝链接）可保留原始画质
- AirDrop 零压缩
- 「低质量图片模式」仅影响图片，对视频无效

> 📌 **视频压缩要点**：Apple 服务器强制将视频转码为 720p，超大图片缩减至 2048px 长边。iCloud Link 和 AirDrop 可规避压缩。

## 配置收件人

| 姓名 | 标识符 | 类型 |
|------|--------|------|
| 张三 | `zhangsan@icloud.com` | 邮箱 |
| 李四 | `+8613800138000` | 手机号 |

> ⚠️ **优先用邮箱**：macOS 可能脱敏显示电话号码（如 `+138****1912`），脱敏号码会导致静默失败。

## Bridge 管理

### 启动

```bash
open <SKILL_DIR>/references/imsg-bridge.command
```

### 状态检查

```bash
pgrep -f "imsg rpc"                     # 查进程
lsof -i :8899                           # 查端口
echo '{"jsonrpc":"2.0","id":"1","method":"chats.list","params":{"limit":1}}' | nc -w 3 127.0.0.1 8899
tail -f /tmp/imsg-bridge.log            # 查看日志
```

### 停止

```bash
tmux kill-session -t imsg-bridge
```

## 故障排查

| 症状 | 原因 | 解决 |
|------|------|------|
| `ConnectionRefusedError` | bridge 未启动 | `open <SKILL_DIR>/references/imsg-bridge.command` |
| `ConnectionRefusedError` 持续 | tmux 会话被杀 | 检查 `pgrep -f "imsg rpc"`，重新启动 bridge |
| `ConnectionRefusedError`（自动化/Cron 环境） | bridge 未运行 | 在发送代码中嵌入自动启动逻辑（见下方「自包含模式」），用主动轮询替代固定 sleep |
| `ConnectionRefusedError`（bridge 启动后仍失败） | 竞态条件：`open .command` 异步返回，固定等待时间不足以让 bridge 就绪 | 使用主动轮询：每秒尝试 connect 8899，确认端口就绪后再发送，最多等 15s |
| `ConnectionRefusedError`（LaunchAgent 已部署） | bridge 进程被杀或启动失败 | `launchctl list \| grep imsg-bridge` 检查状态，查看 `/tmp/imsg-bridge-launchd*.log`；若 exit code 非 0 则检查 socat/imsg 安装路径 |
| `authorization denied (code: 23)`（LaunchAgent 环境） | FDA 权限链断裂（launchd 不继承 Terminal.app FDA） | `send` 走 AppleScript transport 不需要 FDA；`chats.list` 等操作需改用 `.command` 启动（Terminal.app → FDA 继承) |
| `permission denied (code: 23)` | 终端没有 FDA | 给 Terminal.app 加 FDA |
| `permission denied` 且 bridge 是 tmux 直接启动的 | FDA 链断裂：Agent 运行环境 ≠ Terminal.app | 必须用 `open .command` 启动，不能直接 `tmux new-session` |
| `socat: command not found` | socat 未装 | `brew install socat` |
| `imsg: command not found` | imsg 未装 | `brew install steipete/tap/imsg` |
| 返回 `ok` 有 `guid` 但对方没收到 | Messages.app 未登录 | 确认 Messages.app 已登录 iMessage |
| 返回 `ok` 无 `guid` | 已提交但 DB 未确认 | 不重试 |
| 空响应 / TIMEOUT | 连接在响应前断开 | 严禁重试！消息通常已发出 |

## ⛔ 已弃用：AppleScript 直接调用

`osascript send` 永远返回 exit 0，无法判断消息是否送达，自动化中使用会导致假阳性重复发送。

```bash
# ⛔ 弃用 — 禁止在任何自动化流程中使用
osascript -e 'tell application "Messages" to send "消息" to buddy "recipient@example.com"'
```

## ⛔ 已弃用：nc 管道发送

macOS 的 `nc` 在 stdin EOF 后立即关闭连接，`imsg rpc` 的 JSON-RPC 响应被丢弃。必须用 Python socket 接收响应。

```bash
# ⛔ 弃用 — 响应被丢弃，100% 触发空响应→误判→重试循环
echo '{"jsonrpc":"2.0",...}' | nc 127.0.0.1 8899
```

## ⛔ 已废弃：LaunchAgent 部署

**2026-05-30 起不推荐使用 LaunchAgent。**

LaunchAgent 通过 `launchd` 启动 bridge → **不继承 Terminal.app 的 FDA** → `imsg rpc` 的 `send` 方法因无法访问 `chat.db` 返回 `authorization denied (code: 23)`，即使走 AppleScript transport 也无法获取 guid 确认。

**替代方案**：见下方 [自动化集成](#自动化集成) 中的自包含模式——bridge 检测、自动启动、发送、响应判断全部内嵌在单个 Python 函数中。

## 自动化集成

### 推荐：自包含模式（一次脚本调用完成全部工作）

把 bridge 检测 → 自动启动 → 发送 → 响应判断**全部内嵌到一个 Python 函数中**。

**为什么这样做**：在多步骤自动化流程中，LLM 可能在长上下文末端跳过前置步骤（如"先检测 bridge 再发送"），导致 `ConnectionRefusedError`。将 auto-start 嵌入 send 代码内部，消除了对 LLM 的串行执行依赖。

```python
import socket, json, time, subprocess

def send_imessage(to, text):
    """发送 iMessage，内部处理 bridge 自动启动"""

    for attempt in range(2):
        try:
            s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            s.settimeout(10)
            s.connect(('127.0.0.1', 8899))
            s.sendall((json.dumps({
                'jsonrpc': '2.0', 'id': '1', 'method': 'send',
                'params': {'to': to, 'text': text}
            }) + '\n').encode())
            time.sleep(2)
            try:
                resp = s.recv(4096).decode()
                s.close()
                return resp
            except socket.timeout:
                s.close()
                return 'TIMEOUT'
        except (ConnectionRefusedError, OSError):
            if attempt == 0:
                # 自动启动 bridge：open .command 继承 Terminal.app FDA
                # 注意：不能用 tmux new-session -d（可能被安全策略拦截），必须用 open
                cmd_path = '<SKILL_DIR>/references/imsg-bridge.command'
                subprocess.run(['open', cmd_path], check=False)
                # 轮询等待 bridge 就绪（open 异步 + Terminal.app 冷启动 ≥3s，固定 sleep 不够）
                ready = False
                for i in range(15):
                    time.sleep(1)
                    try:
                        test = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
                        test.settimeout(2)
                        test.connect(('127.0.0.1', 8899))
                        test.close()
                        ready = True
                        break
                    except (ConnectionRefusedError, OSError):
                        continue
                if not ready:
                    return 'BRIDGE_START_FAILED'
            else:
                return 'BRIDGE_START_FAILED'

result = send_imessage('recipient@example.com', '消息内容')
print(result)
```

**响应判断：**
- 含 `"guid"` → ✅ 数据库级送达确认
- 含 `"ok"` 无 `"guid"` / `TIMEOUT` → ⚠️ 已提交未确认，严禁重试
- `BRIDGE_START_FAILED` / 含 `"error"` → bridge 自动启动也失败了，报告失败不重试

### 旧版（分步模式，仅交互式场景可用）

仅当你在交互式聊天中手动操作且能记住串行步骤时使用：

```bash
# Step 1: 确保 bridge 在运行（幂等）
tmux has-session -t imsg-bridge 2>/dev/null || {
    open <SKILL_DIR>/references/imsg-bridge.command
    sleep 2
}
```

```python
# Step 2: Python socket 发送（完整代码见上方"发送消息"）
```

> ⚠️ **自动化/Cron 场景必须用自包含模式**。分步模式在自动化中不可靠——LLM 可能跳过 Step 1。

## 参考

- [imsg 官方文档](https://imsg.sh/rpc.html)
- [FDA Bridge 原理](references/imessage-fda-bridge.md)
- [iMessage 自动化能力边界调研](references/imessage-automation-research.md)
- [BlueBubbles 深度调研](references/bluebubbles-research.md)
- [发送调试指南](references/send-debugging-guide.md)
- [LaunchAgent 部署指南](references/imsg-bridge-launchagent.md)
- [群聊 chat_id 查询脚本](scripts/list-group-chats.py) — 一键列出所有群组及 chat_id
