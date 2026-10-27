# 内网 AI 开发技术栈标准

面向 AI BP 团队的内网自研系统技术栈与交付规范。目标是：**任何人用 AI 生成的系统，都能在同一台内网服务器上部署、被另一个人接手维护。**

## 文档

| 文件 | 说明 |
|---|---|
| [standards/内网AI开发技术栈标准.md](standards/内网AI开发技术栈标准.md) | 主文档，当前 v1.1（评审稿） |
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

## 怎么用

1. 新项目开工前，先读主文档第 2、3、7 节。
2. 按模板创建项目，仓库必须包含 `global.json`、`nuget.config`、`Directory.Packages.props`、`.editorconfig`。
3. 需要偏离标准时，写 ADR 并提交评审，不要“先做了再说”。
4. 每个季度评审一次版本表。

## 贡献流程

- 分支：`feature/xxx`，合并前提 PR，至少 1 人评审。
- 提交信息：`type(scope): subject`，例如 `docs(standard): 增加数据分级`。
- 变更必须同步更新 `CHANGELOG.md` 与文档内的版本表。

## 状态

- v1.0：初版（2026-10-23）
- v1.1：评审稿（2026-10-27），待架构负责人签字后生效
