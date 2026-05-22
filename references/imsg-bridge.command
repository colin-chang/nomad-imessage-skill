#!/bin/bash
# ==============================================================================
# imsg-bridge.command — iMessage 桥接守护进程启动器
# ==============================================================================
#
# 【它是干什么的】
#   在后台启动一个 imsg JSON-RPC → TCP 桥接服务，让没有 Full Disk Access
#   权限的程序（如 AI Agent）也能通过 localhost:8899 发送 iMessage。
#
# 【背景 — 为什么需要这个】
#   macOS 的完全磁盘访问（FDA）只能授予 .app bundle 或 Homebrew 安装的
#   独立可执行文件。AI Agent 以 Python/Node 进程运行，无法被 macOS 系统设置
#   加入 FDA 白名单。但 Terminal.app 可以拥有 FDA，从 Terminal.app 启动
#   的子进程会继承 FDA。
#
#   本脚本利用这一机制：通过 .command 文件 → Terminal.app → bash → tmux →
#   socat → imsg rpc 的链条，让 imsg rpc 继承 Terminal.app 的 FDA，从而
#   可以合法读取 ~/Library/Messages/chat.db 并通过 Messages.app 发送消息。
#
#   参考：OpenClaw/openclaw #5116（同一问题的已验证解决方案）
#
# 【架构】
#   Terminal.app (FDA ✅)
#     └─ bash (本脚本)
#          └─ tmux new-session -d (后台会话, 不占窗口)
#               └─ socat TCP-LISTEN:8899 (接收 TCP 连接)
#                    └─ imsg rpc (JSON-RPC on stdin/stdout, FDA ✅)
#
# 【如何使用 — 三种启动方式，等效】
#
#   方式1：双击运行
#     Finder 中双击本文件 → Terminal.app 窗口闪一下自动关闭
#
#   方式2：终端指令
#     open <SKILL_DIR>/references/imsg-bridge.command
#     适用于：自动化工具触发、SSH 远程触发、自动化脚本调用
#
#   方式3：自动化检测与启动（推荐 — 无需手动管理）
#     skill 的发送流程内置检测逻辑，bridge 未运行时自动调用 open 启动
#     无需设置开机自启
#
# 【何时使用】
#   ✅ Mac 开机/重启后 → 手动运行一次，后续由 skill 自动检测
#   ✅ Agent 首次调用 iMessage 发送时 → skill 自动检测并启动
#   ❌ 已运行时无需重复调用（脚本内置判重逻辑）
#
# 【前置条件】
#   1. brew install socat              # 网络 → 标准输入输出的双向转发器
#   2. brew install steipete/tap/imsg  # iMessage 命令行工具
#   3. Terminal.app 拥有完全磁盘访问权限
#       系统设置 → 隐私与安全性 → 完全磁盘访问权限 →
#       添加 /System/Applications/Utilities/Terminal.app
#
# 【验证】
#   # 查进程是否活着
#   pgrep -f "imsg rpc"
#
#   # 发测试消息
#   echo '{"jsonrpc":"2.0","id":"1","method":"chats.list","params":{"limit":1}}' | nc -w 3 127.0.0.1 8899
#
# 【日常管理】
#   tmux attach -t imsg-bridge        # 查看运行状态和日志
#   tmux kill-session -t imsg-bridge  # 停止 bridge
#   tail -f /tmp/imsg-bridge.log      # 只看日志
#
# 【调用示例】
#   # 发送纯文本
#   echo '{"jsonrpc":"2.0","id":"1","method":"send","params":{"to":"recipient@example.com","text":"内容..."}}' | nc -w 5 127.0.0.1 8899
#
#   # 查最近聊天
#   echo '{"jsonrpc":"2.0","id":"1","method":"chats.list","params":{"limit":10}}' | nc -w 5 127.0.0.1 8899
#
# 【故障排查】
#   - imsg-bridge 启动失败 → 检查 socat 是否安装：brew list socat
#   - 发送返回 ok 但对方收不到 → 检查 Terminal.app 是否有 FDA
#   - 发送报 permission denied → TCC 权限链断裂，尝试从 Terminal.app 内直接跑
#   - 端口 8899 被占用 → 修改脚本中的端口号
# ==============================================================================

# 幂等启动：已存在则跳过
if tmux has-session -t imsg-bridge 2>/dev/null; then
    echo "imsg-bridge tmux 会话已存在，跳过启动"
    exit 0
fi

# 在后台 tmux 会话中启动 socat 桥接
tmux new-session -d -s imsg-bridge \
    "socat TCP-LISTEN:8899,reuseaddr,fork EXEC:'imsg rpc' 2>&1 | tee /tmp/imsg-bridge.log"

echo "✅ imsg bridge 已在后台启动（端口 8899）"
echo "日志: /tmp/imsg-bridge.log"
echo "可以关闭此窗口了"
