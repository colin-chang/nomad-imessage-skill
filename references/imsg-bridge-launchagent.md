# imsg Bridge LaunchAgent — 系统级守护进程部署

> 解决 Hermes Cron/Foreground 环境下无法通过 `open .command` 启动 bridge 的问题。

## 背景

`imsg-bridge.command` 使用 `tmux new-session -d` 启动后台桥接进程。Hermes 的 foreground terminal 安全策略会检测并拒绝此类后台命令（报 `"Foreground command uses '&' backgrounding"`）。Cron 任务无法通过 `open` 启动 bridge，必须在 cron 执行前确保 bridge 已运行。

**LaunchAgent 方案**：macOS 原生守护进程机制，自动管理生命周期——开机自启、崩溃重启、无需手动干预。

## 部署步骤

### Step 1：创建 LaunchAgent plist

```bash
cat > ~/Library/LaunchAgents/com.a-nomad.imsg-bridge.plist << 'PLIST_EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.a-nomad.imsg-bridge</string>
    <key>ProgramArguments</key>
    <array>
        <string>/opt/homebrew/bin/tmux</string>
        <string>new-session</string>
        <string>-d</string>
        <string>-s</string>
        <string>imsg-bridge</string>
        <string>socat TCP-LISTEN:8899,reuseaddr,fork EXEC:'imsg rpc'</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>StandardOutPath</key>
    <string>/tmp/imsg-bridge-launchd.log</string>
    <key>StandardErrorPath</key>
    <string>/tmp/imsg-bridge-launchd-err.log</string>
    <key>EnvironmentVariables</key>
    <dict>
        <key>PATH</key>
        <string>/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin</string>
    </dict>
</dict>
</plist>
PLIST_EOF
```

### Step 2：加载并启动

```bash
launchctl load ~/Library/LaunchAgents/com.a-nomad.imsg-bridge.plist
```

### Step 3：验证

```bash
# 检查进程
pgrep -f "imsg rpc"
# 检查端口
lsof -i :8899
# 发送测试
echo '{"jsonrpc":"2.0","id":"1","method":"chats.list","params":{"limit":1}}' | nc -w 3 127.0.0.1 8899
```

## 日常管理

| 操作 | 命令 |
|------|------|
| 启动 | `launchctl load ~/Library/LaunchAgents/com.a-nomad.imsg-bridge.plist` |
| 停止 | `launchctl unload ~/Library/LaunchAgents/com.a-nomad.imsg-bridge.plist` |
| 重启 | 先 `unload` 再 `load` |
| 查看状态 | `launchctl list \| grep imsg-bridge` |
| 查看日志 | `tail -f /tmp/imsg-bridge-launchd.log` |

## 部署后 Cron 集成

部署 LaunchAgent 后，cron 中的 iMessage 推送流程简化为：

```bash
# 只检测，不启动
if ! tmux has-session -t imsg-bridge 2>/dev/null; then
    # bridge 不在 → 跳过 iMessage 侧送，标注失败
    echo "BRIDGE_DOWN"
else
    # bridge 在 → 正常发送
    python3 -c "..." # JSON-RPC 发送
fi
```

## 与 .command 手动启动的关系

LaunchAgent 和 `.command` 手动启动**互斥且不冲突**：
- LaunchAgent 部署后 bridge 开机即运行
- `.command` 仍可用于手动重启或临时停止 LaunchAgent 后的手动启动
- 若 LaunchAgent 已运行，`.command` 的 `tmux has-session` 幂等检测会自动跳过

## ⚠️ FDA 权限链差异

**LaunchAgent 启动的 bridge 不继承 Full Disk Access：**

```
# LaunchAgent 路径（无 FDA）
launchd → tmux → socat → imsg rpc  ❌ 无 FDA
  └─ chats.list / messages.history → authorization denied (code: 23)

# Terminal.app 路径（有 FDA）
Terminal.app (FDA ✅) → open .command → tmux → socat → imsg rpc ✅ 继承 FDA
```

**对业务的影响：**
- `send` 正常 — 走 AppleScript fallback transport，不依赖 chat.db
- `chats.list` / `messages.history` 失败 — 需要读 chat.db
- 移民日报 cron 只做 `send`，LaunchAgent 路径完全够用

**如需完整 FDA 支持**：在 macOS 登录项中添加 `open .command`，让 Terminal.app 启动的 bridge 在登录后接管 tmux session（`.command` 内置幂等检测，已存在的 session 会跳过）。
