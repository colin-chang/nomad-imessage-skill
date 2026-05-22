# iMessage FDA Bridge — 原理与参考

> 核心发现：OpenClaw #5116 已验证 FDA 不通过 LaunchAgent 传播，但可通过终端进程链继承。

---

## 问题

macOS TCC 按**责任进程链**判定 FDA。AI Agent（Python/Node 进程）无法加入 FDA 白名单，`imsg` CLI 继承"无 FDA"状态，chat.db 读取返回 `authorization denied (code: 23)`。

## 原理

FDA 沿进程链向下传播。只要根进程（终端 app）有 FDA，所有子进程自动获得：

```
Terminal.app (FDA ✅)
  └─ bash (.command)
      └─ tmux（后台会话）
          └─ socat TCP-LISTEN:8899
              └─ imsg rpc  ← 继承 FDA ✅
```

## 备选方案

| 方案 | 需要个人 Apple ID | 代价 |
|------|-----------------|------|
| imsg Bridge | ✅ | 一次配置 socat + tmux |
| 第二 Apple ID + Jared | ❌ | 需注册新 ID，Jared 已停更 |
| Sendblue / blooio | ❌ | 付费 $25/月，陌生美国号码 |
| Apple Business Chat | ❌ | 需企业资质 |

## JSON-RPC 协议

imsg rpc 文档：https://imsg.sh/rpc.html

| 方法 | 用途 |
|------|------|
| `send` | 发送文本/文件 |
| `chats.list` | 列出对话 |
| `messages.history` | 查历史 |
| `watch.subscribe` | 实时监听 |

## 参考

- OpenClaw #5116 — FDA 不通过 LaunchAgent 传播
- OpenClaw #44406 — iMessage relay 架构讨论
