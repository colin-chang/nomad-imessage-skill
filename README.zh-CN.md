# imessage-nomad

> iMessage Bridge Daemon — 通过 JSON-RPC over TCP 发送 iMessage/SMS，具备可靠的送达确认。

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Platform: macOS](https://img.shields.io/badge/platform-macOS-lightgrey.svg)]()

---

[English](README.md)

## 这是什么？

**imessage-nomad** 解决 macOS 一个底层限制：AI Agent 和自动化脚本（Python/Node 进程）**无法**被授予"完全磁盘访问"权限（FDA）——macOS 只允许 `.app` bundle 加入 FDA 白名单。没有 FDA 就无法读取 `~/Library/Messages/chat.db`（iMessage 数据库）。

本项目提供一个 **TCP 桥接守护进程**，通过 Terminal.app 进程链继承 FDA。你的自动化代码只需向 `localhost:8899` 发 JSON-RPC 调用，bridge 负责一切，并通过数据库级 `guid` 验证提供可靠的送达确认。

## 架构

```
你的脚本 / AI Agent（无 FDA）
    │  Python socket → 127.0.0.1:8899  ← JSON-RPC
    ▼
socat TCP-LISTEN:8899（tmux 后台会话）
    │  fork + exec
    ▼
imsg rpc（FDA ✅ 继承自 Terminal.app）
    ├─ ~/Library/Messages/chat.db
    └─ AppleScript → Messages.app
```

## 快速开始

### 前置条件

```bash
brew install socat
brew install steipete/tap/imsg
```

然后给 Terminal.app 授予完全磁盘访问权限：
**系统设置 → 隐私与安全性 → 完全磁盘访问权限 →**
添加 `/System/Applications/Utilities/Terminal.app`

### 启动 Bridge

```bash
open references/imsg-bridge.command
```

> **推荐**：部署为 LaunchAgent 实现开机自启。
> 详见 [references/imsg-bridge-launchagent.md](references/imsg-bridge-launchagent.md)

### 发送消息

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
        'text': '你好，来自 imessage-nomad！'
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

### 判断结果

```
✅ 成功 — 消息已确认写入 chat.db
   {"result":{"ok":true,"guid":"8DF..."}}
   → 有 "guid" 字段 = 数据库已确认。停止，不重试。

⚠️ 已提交但未确认
   {"result":{"ok":true}}
   → 无 "guid" 字段。消息已提交但未在数据库中观测到。不重试。

⚠️ 空响应 / TIMEOUT
   → 连接在收到响应前断开，但消息通常已经发出去了。
   严禁重试！重试 = 重复发送。

❌ 错误
   {"error":{"code":-32000,"message":"..."}}
   → 连接被拒绝。检查 bridge 是否在运行。
```

## 可用方法

| 方法 | 用途 |
|------|------|
| `send` | 发送文本/文件 |
| `chats.list` | 列出最近对话 |
| `messages.history` | 查聊天历史 |
| `watch.subscribe` | 实时监听新消息 |
| `react` | Tapback 快捷回复 |

完整协议文档：https://imsg.sh/rpc.html

## 为什么不直接用 AppleScript？

```bash
# ❌ 禁止在任何自动化中使用
osascript -e 'tell application "Messages" to send "消息" to buddy "..."'
```

`osascript send` **永远**返回 exit 0——你无法区分成功和失败。会导致假阳性重试循环：消息实际已发出，但你的脚本以为失败，于是重发……再重发……

## 为什么不用 `nc`（netcat）？

macOS 的 `nc` 在读取完 stdin EOF 后立即关闭连接，JSON-RPC 响应被丢弃。你收到空响应，以为失败了——但消息已经发出了。然后你重试。对方收重复消息。

**必须用 Python socket**，显式 `recv()` 接收响应。

## 文档

| 文档 | 说明 |
|------|------|
| [SKILL.md](SKILL.md) | 完整参考（bridge 管理、故障排查） |
| [FDA Bridge 原理](references/imessage-fda-bridge.md) | FDA 继承机制原理 |
| [自动化能力调研](references/imessage-automation-research.md) | iMessage 自动化的能力边界 |
| [LaunchAgent 部署](references/imsg-bridge-launchagent.md) | 系统守护进程部署 |
| [调试指南](references/send-debugging-guide.md) | 常见问题排查 |

## 安全性

- **仅监听本地**：bridge 监听 `127.0.0.1:8899`——不对外暴露。
- **FDA 访问**：bridge 读取 `chat.db`（iMessage 数据库）。这是方案的核心——正是通过它获取送达确认。
- **数据不出机器**：所有处理在本地完成，不上传任何数据。
- 详见 [SECURITY.md](SECURITY.md)

## 平台支持

- **仅 macOS** — 需要 Messages.app 和 `chat.db`
- 已在 macOS 15 (Sequoia) 测试，应兼容 macOS 13+
- `imsg` CLI 通过 Homebrew 安装（`steipete/tap/imsg`）

## 许可证

MIT — 详见 [LICENSE](LICENSE)

## 常见问题

**Q: 可以在无头 Mac（无显示器）上运行吗？**
A: 可以——bridge 在 tmux 后台运行。不需要接显示器，但 Messages.app 必须已登录（至少需要一次 GUI 登录）。

**Q: 支持 SMS（绿色气泡）吗？**
A: 支持——`imsg rpc` 通过 iPhone 中继，经 Messages.app 发送 SMS。

**Q: 可以在多台 Mac 上运行吗？**
A: 每台 Mac 需要各自的 bridge 实例。如果登录同一个 Apple ID，共享同一个 iMessage 账户。
