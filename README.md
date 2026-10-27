# 内网 AI 开发技术栈标准

面向 AI BP 团队的内网自研系统技术栈与交付规范。目标是：**任何人用 AI 生成的系统，都能在同一台内网服务器上部署、被另一个人接手维护。**

## 文档

| 文件 | 说明 |
|---|---|
| [standards/内网AI开发技术栈标准.md](standards/内网AI开发技术栈标准.md) | 主文档（STD-AI-001），当前 v1.2（评审稿） |
| [standards/小型系统裁剪指南.md](standards/小型系统裁剪指南.md) | 配套文档（STD-AI-002）：规模定档判据、S/M/L 分档裁剪矩阵、永不裁剪红线、升档触发条件 |
| [CHANGELOG.md](CHANGELOG.md) | 版本变更记录 |
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

## 状态

- v1.0：初版（2026-10-23）
- v1.1：评审稿（2026-10-27）
- v1.2：评审稿（2026-10-27），新增规模分级与裁剪指南（STD-AI-002），待架构负责人签字后生效
