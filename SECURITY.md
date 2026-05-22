# Security

## Architecture

The bridge daemon listens on `127.0.0.1:8899` (localhost only). No external network interface is bound. Only processes running on the same machine can connect.

## Attack Surface

| Vector | Risk | Mitigation |
|--------|------|------------|
| Local process connects to port 8899 | Low | Any process on the machine can send iMessages as you — but only if they already have code execution on your Mac, which is game over anyway. |
| Bridge process reads `chat.db` | Expected | This is the core mechanism — the bridge needs FDA to read the iMessage database for delivery confirmation. |
| `socat` TCP listener | Low | `socat` is a well-audited Unix tool. No known CVEs for basic TCP forwarding. |
| Plaintext JSON-RPC | Acceptable | Traffic never leaves localhost. TLS would add complexity with no real benefit for a loopback-only service. |

## What the Bridge Can Do

- **Read** `~/Library/Messages/chat.db` (iMessage database) — for delivery confirmation, chat listing, history
- **Send** iMessage/SMS via AppleScript → Messages.app — as the logged-in Apple ID
- **Monitor** incoming messages via `watch.subscribe`

## What the Bridge Cannot Do

- Accept connections from other machines (bound to `127.0.0.1` only)
- Send messages from a different Apple ID than the one logged into Messages.app
- Access other databases or system files beyond `chat.db`

## Recommendations

1. **Keep the port local.** Do not change the bind address from `127.0.0.1` to `0.0.0.0`.
2. **Keep your Mac secure.** If someone can run arbitrary code on your machine, port 8899 is the least of your worries.
3. **Use LaunchAgent for production.** The provided LaunchAgent plist keeps the bridge alive and auto-restarts on crash.
4. **Review the bridge script.** `references/imsg-bridge.command` is ~90 lines of bash. Read it before deploying.
