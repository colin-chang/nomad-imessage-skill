# Skill 开源发布清单

> 本文件记录 imessage-nomad v3.3.0 → v4.0.0 开源重构的完整流程。
> 可作为其他 skill 开源化的参考模板。

## 发布流程（6 步）

### 1. 剥离平台特化内容

识别并移除只对特定 Agent 平台（如 Hermes）有意义的内容：

| 信号 | 示例 |
|------|------|
| 工具名选择讨论 | `execute_code` vs `terminal` 的选择 |
| 安全策略规避 | 审批弹窗、`Foreground command uses '&' backgrounding` |
| 内部扫描器行为 | `_scan_assembled_cron_prompt()`、tirith 引擎 |
| 平台特有命名坑 | toolset 名 vs tool 名 (`code_execution` vs `execute_code`) |
| Cron 集成细节 | `enabled_toolsets` 配置、子代理限制 |

**原则**：如果一段内容 80% 的读者不需要关心，它就不该在主文档里。

### 2. 平台特化内容归档

在主 skill 目录下创建 `references/<platform>/` 子目录，将剥离的内容整理成独立文档。

```
references/
├── hermes/                    # 仅 Hermes 用户需要
│   ├── hermes-integration.md  # 特殊注意事项
│   └── cron-delivery-pattern.md  # Cron 发送模式
```

主 SKILL.md 只保留一句引用链接，不内联平台细节。

### 3. 脱敏

搜索并替换所有本机/个人信息：

```bash
grep -r "email\|phone\|@\|+1" SKILL.md references/
```

| 原始值 | 替换为 |
|--------|--------|
| `chenjieyu.swufe@gmail.com` | `recipient@example.com` |
| 真实 cron job ID | `某日报 cron 任务` |
| 个人命名空间 (`com.hermes.`) | 通用命名空间 (`com.a-nomad.`) |

### 4. 补全合规文档

| 文件 | 内容 | 语言 |
|------|------|------|
| `README.md` | 架构图、快速开始、FAQ | English |
| `README.zh-CN.md` | 同上 | 中文 |
| `LICENSE` | MIT | English |
| `SECURITY.md` | 攻击面分析、端口安全、依赖审计 | English |
| `PRIVACY.md` | 数据流向、FDA 说明、删除指南 | English |
| `.gitignore` | macOS 缓存、日志、IDE 文件 | — |

### 5. 清理探索记录

删除以下类型的文档：

- 详细事故复盘（ZWJ emoji 三天调试战报）
- 扫描器源码分析（三套扫描器对比表）
- 内部 bug 修复记录（"execute_code 配置问题已解决"）
- 过时的降级/备选方案讨论
- 与其他 skill 的联动调试记录

**保留**：通用故障排查表（症状→原因→解决）、通用原理说明。

### 6. 发布

```bash
cd <skill-dir>
git init && git branch -m main
git add -A
git commit -m "v4.0.0: 开源重构"

gh repo create <user>/<repo> \
  --public \
  --source . \
  --remote origin \
  --push \
  --description "<一句话描述>"
```

## 通用模式：平台附录分离

核心原则：**主文档 = 通用方案，附录 = 平台适配**。

这个模式适用于任何需要跨平台/跨 Agent 框架分发的 skill：

```
skill/
├── SKILL.md              ← 纯通用，不提及任何特定 Agent 平台
├── README.md             ← 面向所有用户的快速开始
│
└── references/
    ├── core-topic.md     ← 通用原理/调研
    ├── deployment.md     ← 通用部署方案
    │
    └── <platform>/       ← 平台专属附录
        ├── integration.md
        └── <use-case>.md
```

## 设计决策记录

| 决策 | 理由 |
|------|------|
| Hermes 附录用子目录而非 `[Hermes Only]` 标记 | 子目录从结构上隔离，通用用户永远不会误入。标记不够强制 |
| 合规文档英文优先 | 面向国际开源社区，中文版 `README.zh-CN.md` 作为补充 |
| `references/README.md` 删除 | 与根 README 重复，冗余维护 |
| 旧 `security.md`/`privacy.md` 删除 | 已被根级英文版替代，更全面 |
