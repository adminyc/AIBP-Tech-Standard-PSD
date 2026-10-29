# 内网 AI 开发技术栈标准

面向 AI BP 团队的内网自研系统技术栈与交付规范。目标是：**任何人用 AI 生成的系统，都能在同一台内网服务器上部署、被另一个人接手维护。**

## 文档

| 文件 | 说明 |
|---|---|
| [standards/内网AI开发技术栈标准.md](standards/内网AI开发技术栈标准.md) | 主文档（STD-AI-001），当前 v1.3（评审稿） |
| [standards/小型系统裁剪指南.md](standards/小型系统裁剪指南.md) | 配套文档（STD-AI-002）：规模定档判据、S/M/L 分档裁剪矩阵、永不裁剪红线、升档触发条件 |
| [KNOWN-ISSUES.md](KNOWN-ISSUES.md) | **已知问题登记**。发现的缺陷先记这里，不用等修好 —— 只写在群里的缺陷等于不存在 |
| [CHANGELOG.md](CHANGELOG.md) | 版本变更记录 |
| [tools/check-release.ps1](tools/check-release.ps1) | 发版前自动校验（版本号三处一致、章节引用有效、配套文档已登记），提 PR 前必跑 |
| [docs/adr/0000-adr-template.md](docs/adr/0000-adr-template.md) | 架构决策记录（ADR）模板 |

## 技术基线

- 语言 / 平台：C# / .NET 10 LTS
- 数据库：SQL Server 2025（关系 + 原生 VECTOR）
- 前端：Vue 3 + TypeScript + Element Plus（Node 仅构建期）
- AI：Python 3.12 侧车 + 统一 AiGateway
- 缓存：Garnet（Redis 协议，Windows 原生）
- 入口：Nginx
- 版本管理：Git + Gitea
- 容器：暂不使用

> 上列**语言、数据库、入口、版本管理、容器策略为强制基线**；**AI（Python 侧车 / AiGateway / 模型）与 Garnet 为按需部署项**，无对应需求或属小型系统时不装，判定口径见 [STD-AI-002](standards/小型系统裁剪指南.md) 第 3 节分档矩阵。少装组件不是违规，**未登记的少装才是违规**。

## 怎么用

1. 新项目开工前，**先按 STD-AI-002 定档（S / M / L）**，再读主文档第 2、3、7 节。
2. 按模板创建项目，仓库必须包含 `global.json`、`nuget.config`、`Directory.Packages.props`、`.editorconfig`。
3. **档内裁剪不必逐个提 ADR**，在项目 README 的「裁剪声明」表登记一行即可（如 S 档不装 Garnet、放宽备份频率）；偏离基线才写 ADR 提交评审。不要"先做了再说"。
4. 主文档第 2 节五条铁律、STD-AI-002 第 2 节永不裁剪清单，任何规模都不打折。
5. 每个季度评审一次版本表。

## 贡献流程

- 分支：`feature/xxx`，合并前提 PR，至少 1 人评审。
- 提交信息：`type(scope): subject`，例如 `docs(standard): 增加数据分级`。
- 变更必须同步更新 `CHANGELOG.md` 与文档内的版本表。

### 改标准前先判断版本级别

判定表和完整规则见 **STD-AI-001 §12.1**，一句话版本：

| 你改的是 | 版本 | 要不要架构负责人签字 |
|---|---|---|
| 错字、死链、写错的版本号，**合规判定结果不变** | 补丁 `v1.2.1` | **不用**。自己验证 + 任一成员复核即可，合并即生效 |
| 新增可选内容、放松要求、新增章节或配套文档 | 次版本 `v1.3` | 要 |
| 改铁律、改强制结构、删组件、改变"什么算合规" | 主版本 `v2.0` | 要，且走季度评审 + 全员知会 |

拿不准就按高的算。

### 发版五步

```
1. 建分支      git checkout main; git pull; git checkout -b patch/简短描述
2. 改文档      只改该改的，不夹带无关调整
3. 三处同步    文档头部「版本」字段 + 附录 D 变更记录 + CHANGELOG.md
4. 跑校验      powershell -File tools\check-release.ps1     ← 全绿才提 PR
5. 合并打标签  git tag std-ai-001-v1.2.1; git push --tags
```

第 3 步最容易漏，所以第 4 步的脚本专门查它。

### 发现了问题但暂时不修？

登记到 [KNOWN-ISSUES.md](KNOWN-ISSUES.md)，一条四行：什么问题 / 影响谁 / 建议怎么修 / 状态。
下次发补丁时一并处理。

## 状态

- v1.0：初版（2026-10-23）
- v1.1：评审稿（2026-10-27）
- v1.2：评审稿（2026-10-27），新增规模分级与裁剪指南（STD-AI-002），待架构负责人签字后生效
- v1.3：评审稿（2026-10-29），新增标准文档自身的版本规则（§12.1）、已知问题登记（KNOWN-ISSUES.md）与发版校验脚本（tools/check-release.ps1），待架构负责人签字后生效
