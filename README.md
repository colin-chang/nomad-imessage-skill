# nomad-imessage

> 🧩 **macOS AI Agent Skill** — give any AI agent the ability to send iMessage/SMS via JSON-RPC over TCP, with reliable delivery confirmation.
>
> Works with **Hermes Agent**, **Claude Code**, **OpenCode**, **Codex**, or any automation script running on macOS.

[![Skill](https://img.shields.io/badge/type-Agent%20Skill-blue)](SKILL.md)
[![Platform: macOS](https://img.shields.io/badge/platform-macOS-lightgrey.svg)]()
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

---

[中文版](README.zh-CN.md)

## What is this?

**nomad-imessage** is a **macOS Agent Skill** — a self-contained module that any AI agent or automation script can use to send iMessage/SMS on macOS.

It solves a fundamental macOS limitation: AI agents and automation scripts (Python/Node processes) **cannot** be granted Full Disk Access (FDA) on macOS — only `.app` bundles can. Without FDA, they can't read `~/Library/Messages/chat.db`, the iMessage database.

This Skill provides a **TCP bridge daemon** that inherits FDA through a Terminal.app process chain. Your agent sends JSON-RPC calls to `localhost:8899`, and the bridge handles everything with proper delivery confirmation via database-level `guid` verification.

## Architecture

```
Your Script / AI Agent (No FDA)
    │  Python socket → 127.0.0.1:8899  ← JSON-RPC
    ▼
socat TCP-LISTEN:8899 (tmux background session)
    │  fork + exec
    ▼
imsg rpc (FDA ✅ inherited from Terminal.app)
    ├─ ~/Library/Messages/chat.db
    └─ AppleScript → Messages.app
```

## Quick Start

### Prerequisites

```bash
brew install socat
brew install steipete/tap/imsg
```

Then grant Full Disk Access to Terminal.app:
**System Settings → Privacy & Security → Full Disk Access →**
Add `/System/Applications/Utilities/Terminal.app`

### Start the Bridge

```bash
open references/imsg-bridge.command
```

> **Recommended**: Deploy as a LaunchAgent for auto-start on boot.
> See [references/imsg-bridge-launchagent.md](references/imsg-bridge-launchagent.md)

### Send a Message

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
        'text': 'Hello from nomad-imessage!'
    }
}) + '\n'

s.sendall(payload.encode())
time.sleep(1)

try:
    resp = s.recv(4096).decode()
    print(resp)
except socket.timeout:
    print('TIMEOUT — message was likely sent, do NOT retry')

s.close()
```

### Interpreting Results

```
✅ Success — message confirmed in chat.db
   {"result":{"ok":true,"guid":"8DF..."}}
   → Has "guid" field = database confirmed. Stop, do not retry.

⚠️ Submitted but unconfirmed
   {"result":{"ok":true}}
   → No "guid" field. Message submitted, not yet observed in DB. Do not retry.

⚠️ Empty response / TIMEOUT
   → Connection dropped before response, but message was likely sent.
   NEVER retry — retry = duplicate messages.

❌ Error
   {"error":{"code":-32000,"message":"..."}}
   → Connection refused. Check if bridge is running.
```

## Available Methods

| Method | Description |
|--------|-------------|
| `send` | Send text / file |
| `chats.list` | List recent conversations |
| `messages.history` | Query chat history |
| `watch.subscribe` | Real-time message monitoring |
| `react` | Tapback quick reply |

Full protocol docs: https://imsg.sh/rpc.html

## Why Not AppleScript?

```bash
# ❌ NEVER use this in automation
osascript -e 'tell application "Messages" to send "msg" to buddy "..."'
```

`osascript send` **always** returns exit 0 — you can't tell success from failure.
It causes false-positive retry loops: the message was actually sent but your script
thinks it failed, so it sends again… and again.

## Why Not `nc` (netcat)?

macOS `nc` closes the connection immediately after reading stdin EOF,
discarding the JSON-RPC response. You get an empty response and assume failure —
but the message was already sent. Then you retry. Now the recipient has duplicates.

**Always use Python socket** with explicit `recv()` to capture the response.

## Documentation

| Document | Description |
|----------|-------------|
| [SKILL.md](SKILL.md) | Full reference (bridge management, troubleshooting) |
| [FDA Bridge Principles](references/imessage-fda-bridge.md) | How FDA inheritance works |
| [Automation Capabilities](references/imessage-automation-research.md) | What's possible with iMessage automation |
| [LaunchAgent Setup](references/imsg-bridge-launchagent.md) | Deploy as a system daemon |
| [Debugging Guide](references/send-debugging-guide.md) | Common issues and solutions |

## Security

- **Localhost only**: The bridge listens on `127.0.0.1:8899` — no external network exposure.
- **FDA access**: The bridge reads `chat.db` (iMessage database). This is the entire point — it's how it gets delivery confirmation.
- **No data leaves your machine**: All processing is local. Nothing is uploaded anywhere.
- See [SECURITY.md](SECURITY.md) for details.

## Platform Support

- **macOS only** — requires Messages.app and `chat.db`
- Tested on macOS 15 (Sequoia), should work on macOS 13+
- `imsg` CLI via Homebrew (`steipete/tap/imsg`)

## Agent Compatibility

This Skill is **agent-agnostic** — it communicates via a standard TCP socket at `localhost:8899`. Any agent platform that can run Python can use it:

| Agent / Platform | Integration |
|------------------|-------------|
| **Hermes Agent** | Native Skill — see [`references/hermes/`](references/hermes/) |
| **Claude Code** | Add to `CLAUDE.md`, invoke via `terminal` or custom hook |
| **OpenCode / Codex** | Add to project instructions, invoke via Python subprocess |
| **Any Python script** | `import socket` → `connect(('127.0.0.1', 8899))` |
| **Shell scripts** | Use the Python socket snippet as a helper |

## License

MIT — see [LICENSE](LICENSE)

## FAQ

**Q: Can I use this on a headless Mac (no GUI)?**
A: Yes — the bridge runs in tmux background. You don't need a monitor attached, but Messages.app must be logged in (which requires a GUI session at least once).

**Q: Does this work with SMS (green bubbles)?**
A: Yes — `imsg rpc` handles SMS via iPhone relay through Messages.app.

**Q: Can I run this on multiple Macs?**
A: Each Mac needs its own bridge instance. They share the same iMessage account if logged into the same Apple ID.
