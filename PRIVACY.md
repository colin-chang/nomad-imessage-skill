# Privacy

## Data Location

All data stays on your Mac. Nothing is uploaded to any external server.

| Data | Location | Accessed By |
|------|----------|-------------|
| iMessage database | `~/Library/Messages/chat.db` | `imsg rpc` (bridge process) |
| Bridge logs | `/tmp/imsg-bridge.log` | `socat` + `tee` |
| LaunchAgent logs | `/tmp/imsg-bridge-launchd.log` | `launchd` |

## What the Bridge Reads

- **Chat metadata**: conversation participants, last message timestamps (via `chats.list`)
- **Message content**: message text, sender, timestamp (via `messages.history`, `watch.subscribe`)
- **Delivery confirmation**: `guid` field from `chat.db` after sending

All reads are for functional purposes — delivery confirmation, chat listing, message monitoring.

## What the Bridge Does NOT Do

- ❌ Upload data to any external service
- ❌ Access non-iMessage databases or system files
- ❌ Log message content to disk (bridge logs only record connection events, not message bodies)
- ❌ Phone home or send telemetry

## Full Disk Access (FDA)

The bridge requires Full Disk Access to read `chat.db`. FDA is granted to **Terminal.app** (not the bridge itself), and the bridge inherits it through the process chain:

```
Terminal.app (FDA ✅)
  └─ tmux
      └─ socat
          └─ imsg rpc (inherits FDA)
```

You can revoke FDA from Terminal.app at any time in System Settings, which will prevent the bridge from accessing `chat.db`. All other Terminal.app functionality remains unaffected.

## Message Content in Transit

JSON-RPC messages between your script and the bridge travel over a local TCP socket (`127.0.0.1:8899`). Traffic never leaves the loopback interface. No encryption layer is used — adding TLS for a localhost-only service would provide no meaningful security benefit while adding configuration complexity.

## Deleting Data

To remove all bridge-related data:

```bash
# Stop the bridge
tmux kill-session -t imsg-bridge

# If using LaunchAgent, unload it
launchctl unload ~/Library/LaunchAgents/com.a-nomad.imsg-bridge.plist

# Remove log files
rm -f /tmp/imsg-bridge.log /tmp/imsg-bridge-launchd.log /tmp/imsg-bridge-launchd-err.log

# Remove LaunchAgent plist (if you deployed it)
rm -f ~/Library/LaunchAgents/com.a-nomad.imsg-bridge.plist
```

The `chat.db` iMessage database itself is managed by macOS — the bridge only reads it, never modifies it directly. Your iMessage history remains intact.
