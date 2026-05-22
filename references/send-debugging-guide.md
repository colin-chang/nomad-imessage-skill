# 发送调试指南 — 真实事故与排查路径

> 来源：imessage-nomad v3.2.0 开发过程中踩过的坑

---

## 场景一：用 `nc` 发送，返回空但对方收到多条

### 现象

```bash
echo '{"jsonrpc":"2.0",...}' | nc -w 5 127.0.0.1 8899
# 输出：空
# exit：0
# 结果：对方收到了消息
```

### 为什么会重试 4 次

```
nc 空响应 → agent 判定"失败" → 重试
  → nc 空响应 → agent 再次判定"失败" → 重试
    → nc 空响应 → agent 再次判定"失败" → 重试
      → nc 空响应 → agent 放弃
结果：4 条相同消息全部送达
```

### 根因

macOS 的 `nc` 在 stdin EOF 后立即发送 FIN 关闭写端。`imsg rpc` 处理完 send 请求、写出 JSON-RPC 响应时，连接已断，响应被丢弃。

### 修复

用 Python socket 替代 `nc`，显式 `recv()` 等待响应：

```python
s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
s.connect(('127.0.0.1', 8899))
s.settimeout(10)
s.sendall(payload.encode())
time.sleep(1)
resp = s.recv(4096).decode()  # 拿到响应
```

### 为什么不直接用 `nc -q` 或 `nc -N`

macOS 的 `nc` 与 Linux 的 `nc` 行为不同，且 macOS 版本不支持 `-q` 等保持连接的选项。Python socket 跨平台一致。

---

## 场景二：Shell `|| &&` 优先级导致 ConnectionRefusedError

### 现象

```bash
tmux has-session -t imsg-bridge 2>/dev/null || open <SKILL_DIR>/references/imsg-bridge.command && sleep 2 && nc 127.0.0.1 8899
# bridge 正在运行，但 nc 返回 ConnectionRefusedError
```

### 根因

Shell 的 `&&` 和 `||` 优先级相同（左结合）：

```bash
# 你的意图：
tmux has-session || (open ... && sleep 2 && nc ...)

# Shell 实际执行：
(tmux has-session || open ...) && sleep 2 && nc ...
```

当 `tmux has-session` 失败、`open` 成功后：
- `open` 的退出码 ≠ 0 → `&& sleep 2 && nc ...` 被跳过
- bridge 已启动但消息没发

当 `tmux has-session` 成功、`open` 跳过时：
- `||` 短路，但 `sleep 2 && nc` 仍然执行
- 但此时 bridge 已经在监听，`nc` 应该成功——但 nc 发送后立即断连，响应丢失

### 修复

用 `{ }` 分组，检测和发送分两步：

```bash
# Step 1: 仅负责确保 bridge 运行
tmux has-session -t imsg-bridge 2>/dev/null || {
    open <SKILL_DIR>/references/imsg-bridge.command
    sleep 2
}

# Step 2: 仅负责发送
python3 -c "..."
```

---

## 场景三：bridge 进程在运行但 `imsg rpc` 无响应

### 排查步骤

```bash
# 1. 确认进程存活
pgrep -f "imsg rpc"

# 2. 确认端口监听
lsof -i :8899

# 3. 发一个轻量请求测试连通性
echo '{"jsonrpc":"2.0","id":"1","method":"chats.list","params":{"limit":1}}' | nc -w 3 127.0.0.1 8899

# 4. 查看 bridge 日志
tail -30 /tmp/imsg-bridge.log
```

### 常见原因

| 原因 | 症状 | 解决 |
|------|------|------|
| FDA 未授予 | `permission denied (code: 23)` | 给 Terminal.app 加 FDA |
| Messages.app 未登录 | `ok` 有 `guid` 但对方收不到 | 确认 Messages.app 已登录 iMessage |
| socat 未安装 | `socat: command not found` | `brew install socat` |
| tmux 会话被杀 | `pgrep` 无结果 | 重新 `open` bridge 脚本 |
