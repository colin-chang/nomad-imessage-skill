# iMessage 自动化能力边界调研

> 结论：Apple 没有提供 iMessage Bot API，所有自动化方案都需要一个真实 Apple ID + 运行中的 Mac。

---

## 一、自发送（Send to Self）

| 发送方式 | 能否送达 | 备注 |
|---------|---------|------|
| 主 iCloud 邮箱 → 主 iCloud 邮箱 | ❌ 系统拦截 | AppleScript 报错 `Can't send a message to yourself` |
| 邮箱 → 自己的手机号 | ✅ 可行 | 系统视为不同身份 |
| 手机号 → 自己的邮箱 | ✅ 可行 | 同上 |
| 使用 `me` 关键字 | ❌ 禁止 | AppleScript 保留字 |

### 通知问题

通过别名自发送成功后，若 Mac 上 Messages.app 在前台，消息会立刻标为"已读"，手机端不弹通知。

---

## 二、Bot 机制对比

| 平台 | Bot API | 独立 Bot 身份 | 无需个人账号 |
|------|---------|-------------|------------|
| Discord | ✅ | Bot Token | ✅ |
| Telegram | ✅ BotFather | `@xxx_bot` | ✅ |
| Slack | ✅ Bolt SDK | Bot User | ✅ |
| **iMessage** | ❌ | ❌ | ❌ |

Apple 提供的两个接口都不符合需求：
- **iMessage Extension SDK** — 贴纸/小游戏/支付插件，不能发消息
- **Apple Business Chat** — 仅限注册企业，不开放给个人

---

## 三、替代方案

| 方案 | 需要个人 Apple ID？ | 接收方看到谁？ | 代价 |
|------|-------------------|-------------|------|
| imsg Bridge | ✅ 是 | 你本人 | 需部署 socat + tmux，一次配置 |
| 第二 Apple ID + Jared | ❌ | 新账号 | 需注册第二个 ID |
| Sendblue / blooio | ❌ | 陌生美国号码 | 付费 $25/月起 |
| Apple Business Chat | ❌ | 企业品牌名 | 需企业资质 |

---

## 四、结论

对个人/家庭场景，**imsg Bridge** 是当前最优解：
- 消息来源清晰（接收方看到的是你的名字）
- 具备真正的送达确认（JSON-RPC `guid` 响应）
- 零额外成本
- 一次配置后可持续使用

⚠️ **已弃用 AppleScript 直接发送**：`osascript send` 永远返回 exit 0 但无法区分成功/失败，导致假阳性重复发送。

核心限制：**永远需要一台运行中的 Mac + Messages.app**。

---

## 五、商业 Relay 方案（参考）

### Claw Messenger + Linq Partner API

- 使用 Linq Partner API（Apple 官方企业消息网关）
- WebSocket relay，无需本地 Mac、无 FDA 问题
- 每用户 $5-25/月
- 状态：社区插件
