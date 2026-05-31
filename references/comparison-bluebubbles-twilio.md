# nomad-imessage vs Hermes BlueBubbles vs Twilio SMS 对比

## 架构对比

| | nomad-imessage | BlueBubbles (Hermes Adapter) | SMS (Twilio) |
|--|:--:|:--:|:--:|
| 消息类型 | 🔵 iMessage | 🔵 iMessage | 🟢 SMS/MMS |
| 集成方式 | Skill（LLM 知识文档） | Platform Adapter（原生集成） | Platform Adapter（原生集成） |
| 发送机制 | Python socket → TCP bridge | HTTP REST API | HTTP REST API |
| 接收消息 | ❌（仅发送） | ✅ Webhook 双向 | ✅ Webhook 双向 |
| FDA 解决 | Terminal.app 进程继承链 | BlueBubbles Helper.app | 不需要（云服务） |
| 对话管理 | 无 session | 按 chat_id 独立 session | 按号码独立 session |
| 多设备 | 仅本机 | BlueBubbles 私有服务器 | 云服务 |
| 费用 | 🆓 免费 | 🆓 免费 | 💰 按条付费 |
| Mac 必须开机 | ✅ 是 | ✅ 是（BlueBubbles 所在 Mac） | ❌ 否 |

## 适用场景

| 场景 | 推荐 |
|------|:--:|
| 偶尔发一条 iMessage（如通知老婆） | nomad-imessage |
| 把 iMessage 作为常规聊天渠道（替代 Mattermost） | BlueBubbles |
| 收到 iMessage 后自动回复 | BlueBubbles（需要 webhook 入站） |
| 跨国发短信给非 iPhone 用户 | Twilio |
| 自动化工作流中发 iMessage（cron 通知等） | nomad-imessage |
| 出门在外用手机 iMessage 操控 Hermes | BlueBubbles |
| 不信任第三方 App 获取 Messages 权限 | nomad-imessage |

## 结论

**不需要替换。两者可共存。** nomad-imessage 覆盖出站场景（Mattermost 触发→发 iMessage），BlueBubbles 覆盖入站场景（别人 iMessage Hermes→自动回复）。当前使用场景下 nomad-imessage 完全足够，BlueBubbles 作为未来双向交互的补充选项。

## 相关

- nomad-imessage SKILL.md：`<SKILL_DIR>/SKILL.md`
- BlueBubbles 官方文档：https://hermes-agent.nousresearch.com/docs/user-guide/messaging/bluebubbles
- BlueBubbles 源码：`~/.hermes/hermes-agent/gateway/platforms/bluebubbles.py`
- SMS (Twilio) 源码：`~/.hermes/hermes-agent/gateway/platforms/sms.py`
