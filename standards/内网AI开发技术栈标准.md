# 内网 AI 开发技术栈标准

| 项目 | 内容 |
|---|---|
| 文档编号 | STD-AI-001 |
| 版本 | v1.3（评审稿） |
| 生效日期 | 评审通过后次月 1 日 |
| 适用范围 | AI BP 团队，以及所有内网自研系统（含 AI 能力） |
| 配套文档 | STD-AI-002《内网自研系统规模分级与裁剪指南》（同目录） |
| 归口部门 | 数字化 / IT |
| 标准负责人 | 架构负责人（待指定） |
| 评审周期 | 每季度一次；紧急修订走临时评审 |
| 变更记录 | 见附录 D |

> 一句话：**语言只能 C#，平台只能 .NET，数据库只能 SQL Server，模型只能走网关，任何项目断网也能构建和部署。**
> 本文档由 AI 辅助起草，须经架构负责人评审签字后生效；签字前为评审稿。

---

## 目录

- [0. 摘要](#0-摘要)
- [1. 目的、范围与前提](#1-目的范围与前提)
- [2. 五条铁律与角色职责](#2-五条铁律与角色职责)
- [3. 技术选型](#3-技术选型)
- [4. 架构与部署](#4-架构与部署)
- [5. 容器策略：v1.x 不上 Docker](#5-容器策略v1x-不上-docker)
- [6. 离线依赖](#6-离线依赖)
- [7. 项目模板](#7-项目模板)
- [8. AI 生成代码的约束](#8-ai-生成代码的约束)
- [9. 编码规范](#9-编码规范)
- [10. 数据分级与安全](#10-数据分级与安全)
- [11. 备份与恢复](#11-备份与恢复)
- [12. 版本、例外与 ADR](#12-版本例外与-adr)
- [13. 交付标准（DoD）](#13-交付标准dod)
- [14. 落地计划](#14-落地计划)
- [15. 规模分级与标准裁剪](#15-规模分级与标准裁剪)
- [附录 A 配置样例](#附录-a-配置样例)
- [附录 B 速查卡](#附录-b-速查卡)
- [附录 C 术语表](#附录-c-术语表)
- [附录 D 变更记录](#附录-d-变更记录)

---

## 0. 摘要

本标准解决三个具体问题：

1. **装不下**——多人用 AI 生成多套栈，一台服务器装不下、端口冲突、依赖打架。
2. **装不上**——内网无外网，`npm install`、`pip install`、`dotnet restore` 全部失败。
3. **接不住**——人一走项目没人能改；统一栈的本质是降低单点依赖。

**技术基线**：Windows Server + .NET 10 LTS + SQL Server 2025 + Vue 3 + Python 3.12（仅 AI）+ Nginx + Garnet + Gitea，不上容器。

### 为什么不用常见替代方案

| 常见选择 | 结论 | 原因 |
|---|---|---|
| Node.js / Next.js 写后端 | 禁止 | 多一套运行时与构建链，内网离线成本翻倍 |
| Python 写业务后端 | 禁止 | Python 只做 AI 能力，业务逻辑归 .NET |
| MySQL / PostgreSQL / MongoDB | 禁止 | 备份、权限、运维、监控全部翻倍 |
| Redis for Windows | 禁止 | 微软移植版停更在 3.x，有已知缺陷；用 Garnet |
| Docker / K8s | 暂不 | 单机 Windows 场景收益低、离线镜像成本高，见第 5 节 |
| Blazor 与 Vue 并存 | 禁止 | 前端只留一套；本标准选 Vue |
| 微服务 / 消息队列 / GraphQL | 禁止（默认） | 单机单库足够，复杂度是负债；确需走 ADR |

---

## 1. 目的、范围与前提

**目的**：让任何一个 AI BP 用 AI 生成的系统，都能在同一台内网服务器上部署、被同一个人接手维护。

**范围（In Scope）**
- AI BP 团队新建的所有内部系统（Web、服务、脚本工具）
- 具备 AI 能力（RAG、Agent、文档生成、数据分析）的应用
- 单台内网服务器部署

**不在范围（Out of Scope）**
- 采购的商业软件（MES / ERP / WMS 产品本身）
- 现有系统的原厂定制开发
- 公有云上的系统

**前提假设**（不成立时需重新评审）
- 服务器为 Windows Server 2019 及以上
- 内网完全断网或仅有限外网
- 有 GPU（≥16GB 显存）用于本地模型；无 GPU 则模型能力降级

---

## 2. 五条铁律与角色职责

### 2.1 五条铁律

1. **一个后端语言**：C# / .NET。Node、Python、Go 不写业务后端。
2. **一个数据库**：SQL Server。关系数据、向量、任务、日志归档都在里面。
3. **一个入口**：Nginx。所有服务只监听 `127.0.0.1`，对外只有 80/443。
4. **一个 AI 出口**：所有模型调用走 `AiGateway`，应用不直连 Ollama / vLLM / 外部 API。
5. **离线可还原**：任何项目在断网机器上都能 `restore → build → publish → deploy`。

> **铁律 5 的边界（易被误读，此处明确）**：它约束的是**构建期与部署期**，不是运行期的网络访问。系统运行时调用外部 HTTP 服务（钉钉开放平台、短信网关、上级系统接口等）**不违反本条**，但必须按 STD-AI-002 §6 做**出站登记**：防火墙出站规则精确到域名 + 443、仅出站不开入站、依赖定位为"非核心链路"并配熔断降级。把"内网系统"等同于"不能有任何出站调用"是错误的，会导致该接的外部能力被误砍；反过来，以"只是运行期访问"为由开随机出站或公网回调入口，同样不合规。

### 2.2 角色与职责

| 角色 | 职责 | 关键产出 |
|---|---|---|
| 架构负责人 | 标准解释权、例外审批、版本升级、季度评审 | ADR 签字、版本表 |
| 项目负责人（AI BP） | 按标准交付、提 ADR、对业务结果负责 | 方案、上线、复盘 |
| 开发 | 模板内开发、PR 自检、离线构建验证 | 代码、测试、部署包 |
| 业务方 | 提需求、验收、确认“有人在用” | 验收单 |
| IT 运维 | 服务器、账号、备份、证书、监控 | 备份记录、演练报告 |

**原则**：标准由架构负责人一票裁决；有争议先按标准执行，再走 ADR 修改标准，不允许“先做了再说”。

---

## 3. 技术选型

### 3.1 后端：.NET 10 + C#

- 新项目一律 `net10.0`（.NET 10 LTS，2025-11 发布，支持至 2028-11）。
- 已上线的 .NET 8 项目 2027 年前升级，不再新开 .NET 8。
- 第三方库无 .NET 10 版本时：**换库，不降框架**；无替代则走 ADR。
- 对接仅支持 .NET Framework 的旧 SDK（部分 MES / 上位机组件）：单独做 **Adapter 服务**（.NET Framework 4.8 或 COM 互操作），HTTP 暴露，**旧框架不得进入新项目**。
- 禁止：新系统用 WinForms / WPF 做管理端（保留给设备上位机）；Blazor 与 Vue 混用。

### 3.2 数据库：SQL Server 2025

- 关系数据 + 向量同库：`VECTOR(1024)` 存 embedding，`VECTOR_DISTANCE` 做相似度。
- `CREATE VECTOR INDEX` 目前为预览特性，**暂不启用**；数据量 < 10 万 chunk 时精确检索够用，超限或延迟不达标再评估 Qdrant。
- 现有 2022 实例不强制升级，新库建在 2025；升级统一排窗口。
- 规范：`READ_COMMITTED_SNAPSHOT ON`；每应用独立登录名；禁用 `sa`；夜间全备 + 每小时日志备份到 NAS。
- 排序规则统一 `Chinese_PRC_CI_AS`；字符串一律 `nvarchar`；时间一律 `datetime2` 存 UTC。

### 3.3 缓存：Garnet

- Windows 无官方 Redis（移植版停在 3.x）。用 **Garnet**：微软开源、Redis 协议兼容、Windows 原生、单文件部署。
- 客户端统一 `StackExchange.Redis`，代码只依赖 `IDistributedCache` 抽象。
- 用途限定：缓存、会话、分布式锁、限流计数；**不作主存储**。
- 单机优先 `IMemoryCache`；确需跨进程共享再用 Garnet。**S 档（≤50 用户、单实例）默认不部署 Garnet**，属档内裁剪，登记即可免 ADR；实例数从 1 变 2 即触发升档，见第 15.4 节与 STD-AI-002 §8。

### 3.4 前端：Vue 3 + TypeScript + Element Plus

- 唯一组合：Vue 3 + TS + Vite + Element Plus + Pinia + Vue Router。
- Node 24 LTS 锁死（`.nvmrc` 或 Volta），提交 `package-lock.json`，用 `npm ci`。
- **生产服务器不装 Node**：构建产物为静态文件，由 ASP.NET Core 或 Nginx 托管。
- 禁止：React / Angular / Next.js / Nuxt；禁止 Node 写 BFF 或接口。

### 3.5 Python：只做 AI 能力

- 版本 3.12.x（AI 库兼容性最好），依赖锁 `requirements.txt`（含 hash），用 `uv` 安装。
- 只允许三类职责：模型训练/微调、推理服务、文档解析与 OCR。
- 对外只暴露 HTTP（FastAPI + uvicorn），由 .NET 调用。
- **不直连业务库写数据**；取数走 .NET 的只读接口或数据库只读视图。
- 以 Windows 服务常驻（NSSM），监听 `127.0.0.1:5200`。

### 3.6 AI 网关：唯一出口

自研 `AiGateway`（ASP.NET Core），提供 OpenAI 兼容接口：

- `/v1/chat/completions`（支持流式）
- `/v1/embeddings`
- `/v1/models`（可用模型清单）

职责：路由（本地 Ollama / 远程 API）、密钥管理、限流、超时重试、Token 计费、审计日志（脱敏）、模型白名单。

应用侧只配一个地址 `http://127.0.0.1:5100`。**禁止任何应用直连 11434 或外部模型 API。**

### 3.7 模型与向量

- 对话模型：Qwen2.5 / Qwen3 系列、DeepSeek 蒸馏版，GGUF 格式，Ollama 加载；GPU 富余时上 vLLM（Linux）。
- **Embedding 全公司统一 `bge-m3`，1024 维**——维度不一致会导致向量库作废，这是最常见的事故。
- Rerank 统一 `bge-reranker-v2-m3`。
- 模型文件按 `名称-版本-量化级别` 命名并存档 NAS，附 SHA256；**禁止 latest 标签**。
- 训练在 GPU 工作站完成，产物（LoRA adapter / GGUF）审批后拷贝到服务器，**不在生产服务器训练**。

### 3.8 入口：Nginx

- Nginx 1.28+ 稳定版，只做三件事：TLS 终止、静态资源、反向代理。
- Windows 版为官方 beta 质量，内网中小流量可用；迁 Linux 后配置可复用。
- AI 流式响应必须：`proxy_buffering off; proxy_read_timeout 300s;`，否则前端看不到逐字输出。

### 3.9 Git 与协作

- 自建 Gitea（单机足够），内网访问；仓库结构见第 7 节。
- `main` 保护：禁止直接 push，必须 PR + 1 人评审；AI 生成代码同样走 PR。
- 分支：`main` + `feature/xxx`，短分支，合并即删。
- 提交信息：`type(scope): subject`（feat / fix / docs / refactor / chore / test）。
- 大文件（模型、安装包、数据）不进 Git，放 NAS；单文件 > 50MB 拒绝入库。
- 仓库必须含：`README.md`、`deploy.ps1`、`nuget.config`、`global.json`、`.editorconfig`。

### 3.10 AI 编码助手的使用边界

| 场景 | 允许的工具 | 约束 |
|---|---|---|
| 内网开发机（默认） | Continue + Ollama 本地模型（qwen2.5-coder 等） | 代码不出机器 |
| 有外网的开发机 | 公司批准的账号（Cursor / Copilot 企业版等） | 禁止上传 L3/L4 数据；禁止整库、整目录上传 |
| 任何情况 | — | 生成代码必须人工评审；加密、权限、支付类代码不得直接采纳 |

重要模块在提交信息中标注 `AI-assisted`，评审人重点看边界条件与异常处理。

### 3.11 与现有 MES / WMS / ERP 的集成边界

- **只读优先**：通过只读视图或只读账号取数，禁止 AI 应用直接写生产库。
- 需要写回时，走对方提供的 API 或中间表 + 审批流，不直连表。
- 集成层单独建 `Adapter` 项目，隔离对方协议（WebService / 中间表 / SDK）。
- 每个集成点必须写清：数据源、频率、字段映射、失败重试、对账方式。

---

## 4. 架构与部署

### 4.1 单机拓扑

```
                    ┌─────────────────────────────┐
   内网用户 ──443──▶ │  Nginx（唯一入口，TLS 终止）  │
                    └──────┬───────────┬──────────┘
                           │           │
                  ┌────────▼───┐  ┌────▼─────────┐
                  │ 业务应用 A  │  │ 业务应用 B   │  127.0.0.1:5001-5099
                  │ (.NET 10)  │  │ (.NET 10)    │  Windows 服务
                  └────┬───────┘  └────┬─────────┘
                       │               │
          ┌────────────▼───────────────▼─────────────┐
          │            AiGateway  :5100              │
          └───┬──────────────┬──────────────┬────────┘
              │              │              │
      ┌───────▼─────┐ ┌──────▼──────┐ ┌─────▼──────┐
      │ Ollama      │ │ Python AI   │ │ SQL Server │
      │ :11434      │ │ :5200       │ │ :1433      │
      └─────────────┘ └─────────────┘ └────────────┘
              │
      ┌───────▼─────┐   ┌─────────────┐   ┌──────────┐
      │ Garnet:6379 │   │ Gitea :3000 │   │ NAS 备份 │
      └─────────────┘   └─────────────┘   └──────────┘
```

### 4.2 端口分配

| 端口 | 用途 | 绑定 |
|---|---|---|
| 80 / 443 | Nginx | 0.0.0.0 |
| 1433 | SQL Server | 127.0.0.1 |
| 5001–5099 | 业务应用（每应用一个，向架构负责人登记） | 127.0.0.1 |
| 5100 | AiGateway | 127.0.0.1 |
| 5200 | Python AI 服务 | 127.0.0.1 |
| 11434 | Ollama | 127.0.0.1 |
| 6379 | Garnet | 127.0.0.1 |
| 3000 | Gitea | 127.0.0.1 |

### 4.3 目录规范

```
D:\Apps\{app}\{version}\      应用版本目录
D:\Apps\{app}\current         目录联接，指向当前版本
D:\Data\{app}\uploads         上传文件（DB 只存相对路径）
D:\Logs\{app}\                日志，保留 30 天
D:\Packages\nuget             离线 NuGet 源
D:\Packages\npm               npm 缓存 / Verdaccio 存储
D:\Packages\pip               wheelhouse
D:\Packages\models            模型文件（同步自 NAS）
D:\Secrets\{app}.json         密钥，ACL 只给服务账号
D:\Backup                     数据库备份（再同步 NAS）
```

### 4.4 资源与容量

| 资源 | 建议 | 说明 |
|---|---|---|
| CPU | 16 核以上 | SQL Server、.NET、Python 抢核，留余量 |
| 内存 | 64GB 起 | **SQL Server 必须设 `max server memory`（24–32GB）**，否则会吃掉内存、把模型挤崩 |
| GPU | 24GB 显存（4090 / L20） | 跑 14B–32B 量化模型；无 GPU 只能 7B–8B，效果明显下降 |
| 磁盘 | 系统盘 200GB SSD + 数据盘 1TB NVMe | 模型与备份放 NAS |

> 单机第一杀手不是 CPU 而是内存：装完 SQL Server 先设上限，再规划显存预算。

### 4.5 部署流程

1. CI 产出 `publish.zip` + 版本号（Git tag）。
2. 运维执行 `deploy.ps1 -App X -Version 1.2.3 -Zip ...`。
3. 脚本：停服务 → 备份当前版本 → 解压到新版本目录 → 切换 `current` 联接 → 启动 → 健康检查。
4. 健康检查失败自动回滚到上一版本目录。
5. 记录部署单（谁、何时、版本、回滚点）。

**切换窗口**：目录联接替换不是原子的，需在停服窗口内完成（通常 < 30 秒）；要求零停机的应用，用 Nginx upstream 蓝绿切换。

---

## 5. 容器策略：v1.x 不上 Docker

**结论：不用。**

- 单机 + Windows + 内网离线，容器收益（环境一致、快速扩缩容）用不上；成本（离线镜像搬运、Windows 容器体验、Docker Desktop 授权）全要付。
- Docker Desktop 对大型企业收费（员工 > 250 人或年收入 > 1000 万美元需订阅），内网也不该引入授权风险。
- `dotnet publish` + 版本目录 + `deploy.ps1` 已能做到“可重复、可回滚”。

**重新评估条件（三条同时满足）**：
1. 出现 ≥3 个需独立伸缩或强隔离的服务；
2. 有 Linux 主机或 K8s 计划；
3. 有内网镜像仓库（Harbor）。

届时用 Linux + containerd/Podman + Harbor，不用 Docker Desktop；Windows 容器只用于 CI 构建。

---

## 6. 离线依赖

### 6.1 依赖来源

| 生态 | 做法 | 存放 |
|---|---|---|
| NuGet | 外网机 restore 拉全量包 → `.nupkg` 拷入本地源；`nuget.config` 用 `<clear/>` 只留本地 | `D:\Packages\nuget` |
| npm | 外网机 `npm ci` 后打包 `node_modules`；或内网 Verdaccio | `D:\Packages\npm` |
| pip | `pip download -r requirements.txt -d wheelhouse --only-binary=:all:`，内网 `--no-index --find-links` | `D:\Packages\pip` |
| 模型 | 外网下载 GGUF / safetensors，校验 SHA256，审批后拷贝 | NAS → `D:\Packages\models` |
| 安装介质 | SQL Server ISO、.NET Hosting Bundle、Node MSI、Python、Nginx、Garnet、Git | NAS `\\nas\software` |

### 6.2 硬性要求

每个项目仓库必须有：

- `global.json`（锁 SDK）
- `nuget.config`（指向内网源）
- `package-lock.json` + `.nvmrc`（或 `engines`）
- `requirements.txt`（含版本）

**四样缺一，不算交付。**

> 按技术栈适用性裁剪：不引入 Python 侧车（无 AI 职责）时 `requirements.txt` 与 wheelhouse 不适用，不引入前端时 `package-lock.json` / `.nvmrc` 不适用——但**必须在项目 README 的「裁剪声明」表登记豁免理由**（见第 15.3 节与 STD-AI-002 §5）。`global.json`、`nuget.config`、`Directory.Packages.props`、`.editorconfig` 无任何豁免。

### 6.3 维护流程

- 架构负责人每月第 1 周同步一次离线源（补包、清废弃包）。
- 同步后在测试机做一次“断网全量构建”验证，记录在 `docs/offline-build.md`。
- 任何人发现缺包，提 Issue，由架构负责人统一补，不允许各自从外网拷 dll 进仓库。

---

## 7. 项目模板

### 7.1 统一结构

```
Xxx/
├─ global.json
├─ nuget.config
├─ Directory.Packages.props
├─ .editorconfig
├─ README.md
├─ deploy.ps1
├─ docs/
│  ├─ adr/
│  └─ offline-build.md
├─ src/
│  ├─ Xxx.Api/            控制器、中间件、DI
│  ├─ Xxx.Application/    用例、DTO、校验
│  ├─ Xxx.Domain/         实体、领域服务
│  └─ Xxx.Infrastructure/ EF Core、Dapper、外部集成
├─ tests/
│  └─ Xxx.Tests/
└─ web/                   Vue 3 前端（可选）
```

### 7.2 模板内置

- 统一返回 `{ code, message, data, traceId }` + 全局异常中间件 + 错误码表
- Serilog 结构化日志（TraceId / UserId / AppId）
- JWT / Cookie 鉴权 + RBAC 权限过滤器
- EF Core + 迁移 + Dapper 注册
- `/health/live`、`/health/ready`
- OpenAPI 文档
- `deploy.ps1`（部署 + 健康检查 + 回滚）
- `README.md` 模板

**模板之外的新结构视为不合规。**

### 7.3 依赖版本集中管理

根目录 `Directory.Packages.props` 统一版本，项目里只写包名、不写版本。AI 最常做的事就是随手加包、随手升级——这一条直接堵死。新增包必须评审并登记。

---

## 8. AI 生成代码的约束

### 8.1 十条约束

1. **从模板起步**：只用 `dotnet new aibp-*`，不手工搭架子。
2. **只用白名单包**：新增 NuGet / npm / pip 包必须评审，版本进 `Directory.Packages.props` 或 `package.json` 统一管理。
3. **禁止幻觉包**：AI 推荐的包名可能是编造的（slopsquatting），必须核对官方仓库、作者、下载量；内网无法核对时由架构负责人统一审。
4. **禁止第二套技术**：不引入第二个 ORM、日志库、前端框架、数据库。
5. **禁止微服务**：单库单服务优先；不上 K8s、不上 MQ、不上 GraphQL，确需走 ADR。
6. **禁止直连模型**：所有调用走 AiGateway。
7. **禁止硬编码**：连接串、密钥、模型地址一律配置化，密钥不进 Git。
8. **禁止自研基础设施**：认证、加密、ORM、序列化一律用成熟库。
9. **必须离线可构建**：PR 前在断网环境跑 `restore + build + publish`。
10. **必须过 CI**：编译、单测、`dotnet format`、密钥扫描（gitleaks）、依赖漏洞检查，全绿才可合并。

### 8.2 禁止清单

| 禁止 | 原因 |
|---|---|
| Node / Python / Go 写业务后端 | 部署与运维碎片化 |
| React / Angular / Next.js 与 Vue 并存 | 两套构建链 |
| MySQL / PostgreSQL / MongoDB / ES 作主存储 | 备份、权限、运维翻倍 |
| Redis for Windows（3.x 移植版） | 停更、有已知缺陷，用 Garnet |
| Docker Desktop | 商用授权 + 离线镜像成本 |
| AI 脚本/工具直连生产库 | 误操作与数据泄露 |
| 未锁版本的依赖（`latest`、`*`） | 构建不可重复 |
| 大段复制来源不明代码 | 开源授权风险 |
| 把生产数据贴进外部 AI 对话 | 数据外泄 |
| 未经评审的第三方包 | 供应链风险 |

> 授权提示：AutoMapper、MediatR、FluentAssertions 8+ 已转商业授权；EPPlus 为非商业授权；QuestPDF 按营收分级。AI 常推荐这些库，引入前必须核对授权。替代：手写映射、Shouldly、ClosedXML、OpenXML SDK。

### 8.3 PR 检查清单

- [ ] 从模板创建，目录结构一致
- [ ] 无新增未评审依赖
- [ ] 无硬编码密钥、连接串
- [ ] 迁移脚本可重复执行
- [ ] 核心逻辑有单测
- [ ] 断网环境构建通过
- [ ] `README.md` / `deploy.ps1` 已更新
- [ ] 日志不含敏感信息
- [ ] 有健康检查端点
- [ ] 有回滚方案

---

## 9. 编码规范

- **API**：REST，路径 `/api/v1/{resource}`；JSON camelCase；分页 `page/pageSize`；时间 ISO 8601 UTC；错误用统一错误码，禁止 HTTP 200 包错误。
- **数据库**：表名 PascalCase 单数；主键 `Id`（bigint identity 或 GUID）；必须有 `CreatedAt/UpdatedAt`；软删除 `IsDeleted`；禁止 `SELECT *` 进生产代码；禁止拼接 SQL。
- **事务**：跨表写操作显式事务；长事务禁止包 HTTP 调用。
- **日志**：结构化字段；不打印完整 Prompt、身份证、手机号、密码；默认 Information。
- **配置**：`appsettings.json` + `appsettings.{Env}.json` + 环境变量覆盖；生产密钥放 `D:\Secrets`，ACL 限制。
- **时间**：DB 存 UTC，前端按本地时区展示；禁止写死 `DateTime.Now`。
- **文件**：存 `D:\Data\{app}\uploads\{yyyyMM}`，DB 存相对路径；文件名用 GUID。
- **后台任务**：Hangfire，任务幂等、可重试、有超时。
- **AI 调用**：超时 60s（流式 300s）、重试 ≤2 次、模型不可用时明确降级提示，不阻塞主流程。

---

## 10. 数据分级与安全

### 10.1 数据分级

| 级别 | 示例 | 能否进入模型 |
|---|---|---|
| L1 公开 | 产品手册、公开资料 | 可以 |
| L2 内部 | 制度、流程、会议纪要 | 本地模型可以；外部 API 不允许 |
| L3 敏感 | 客户名单、报价、工艺参数 | 仅本地模型，需脱敏并审计 |
| L4 核心 | 图纸、配方、源代码、财务数据 | 禁止进入任何模型；确需使用走离线专用实例 + 审批 |

### 10.2 安全要求

- **账号**：一人一账号，禁用共享账号；SQL Server 每应用独立登录名，只给所需库的 `db_datareader/db_datawriter`；禁用 `sa`。
- **密钥**：不进 Git、不进日志、不进前端；统一 `D:\Secrets`，部署时注入环境变量。
- **权限**：RBAC，菜单 + 接口双重校验；数据权限按部门/产线隔离。
- **审计**：登录、导出、删除、AI 调用（谁、何时、模型、Token 数、脱敏后的 Prompt 摘要）留痕 180 天；审计数据单独存储、限权访问。应用运行日志不打印完整 Prompt。
- **提示词注入**：知识库文档视为不可信输入；系统提示与用户输入分离；工具调用白名单；禁止模型直接执行 SQL / Shell。
- **沙盒**：AI 生成代码若需执行，必须在隔离进程或临时目录运行，禁止直接操作生产库。
- **外部 AI**：内网开发机默认不接外部模型；确需使用走公司账号，禁止上传代码与业务数据。

---

## 11. 备份与恢复

| 对象 | 频率 | 保留 | 位置 |
|---|---|---|---|
| 数据库全备 | 每日 01:00 | 30 天 | 本地 + NAS |
| 数据库日志备份 | 每小时 | 7 天 | 本地 + NAS |
| 上传文件 | 每日增量 | 30 天 | NAS |
| 应用版本包 | 每次发布 | 10 个版本 | NAS |
| 模型文件 | 变更时 | 全部 | NAS |

- **RPO ≤ 1 小时，RTO ≤ 4 小时。**
- 每季度做一次恢复演练（随机抽一个库恢复到测试实例），记录在 `docs/dr-drill.md`。
- 备份加密，密钥与备份分开存放。

> 上列为 M / L 档基线。**S 档（≤50 用户、无外部写回）允许放宽为 RPO ≤ 24 小时 / RTO ≤ 8 小时、日志备份每日 1 次、全备保留 14 天、恢复演练上线前 1 次 + 每年 1 次**，需业务方在验收单签字确认，并在 README「裁剪声明」登记（STD-AI-002 §3）。**"上线前至少真实恢复验证过一次"这一条任何档位都不放宽**——没被验证过的备份等于没有备份。

---

## 12. 版本、例外与 ADR

- 只选 **LTS / 稳定版**：.NET、Node、Python、SQL Server，不用预览版。
- 每季度评审版本表，统一升级窗口（每半年一次），禁止个人随时升级。
- 升级前：全项目构建通过 + 回归测试 + 数据库备份。
- 任何偏离本标准的决定，写 **ADR**（背景、选项、决定、影响、回滚），架构负责人签字，存 `docs/adr/NNNN-标题.md`。

**ADR 与裁剪声明的分工**（避免评审带宽被稀释，详见第 15.3 节）：

| 情形 | 处理方式 |
|---|---|
| 在 STD-AI-002 §3 分档矩阵的所属档位列内（如 S 档不装 Garnet、放宽备份频率） | **免 ADR**，在项目 README「裁剪声明」表登记一行，项目负责人自签 |
| 偏离基线（做标准明确禁止的事，或提前引入高档组件） | **必须写 ADR**，架构负责人签字 |
| 不确定归哪类 | 先问架构负责人，**不允许"先做了再说"**（§2.2） |
- ADR 模板见 `docs/adr/0000-adr-template.md`。

### 12.1 标准文档自身的版本规则

上面几条管的是**依赖**的版本，这一条管**标准文档自己**的版本。

#### 版本号怎么升：看改动的方向，不看改动的大小

| 版本 | 什么时候用 | 例子 | 谁批 |
|---|---|---|---|
| **补丁** `v1.2.1` | 纠错不改义：错字、死链、版本号写错、把话说清楚但**合规判定结果不变** | 附录 A3 里的包版本过期了 | **不用架构负责人签字**。改的人自己验证，任一成员复核后合并 |
| **次版本** `v1.3` | 只加不减：新增可选内容、放松要求、新增章节或配套文档 | 新增 npm 离线镜像规范 | 架构负责人过 PR |
| **主版本** `v2.0` | 收紧或推翻：改铁律、改强制结构、删组件、改变"什么算合规" | 调整"禁 Docker"的适用范围 | 季度评审 + 全员知会 |

**判断口诀：改完之后，原本合规的项目还合规吗？**

- 还合规，而且只是把写错的地方改对 → **补丁**
- 还合规，但多了新要求或新选项 → **次版本**
- 变得不合规了 → **主版本**（或按下面的过渡规则处理）

拿不准就按高的算：把补丁当次版本发，代价只是多走一次评审；反过来则可能让没评审过的规则直接生效。

#### 新增强制要求不会让存量项目立刻违规

次版本新增的强制项，**只约束生效日之后开工的项目**。
存量项目在**下一季度评审前**补齐即可，这段时间不算违规。

这条不是放水。如果标准一升级全员立刻违规，大家的反应会是绕开标准而不是遵守它 ——
那比标准写得松更糟。

#### 生效时间

| 类型 | 生效时间 |
|---|---|
| 补丁 | **合并即生效**。纠错没有理由等下个窗口 |
| 次版本 / 主版本 | 文档头部表格里写的「生效日期」，默认评审通过后次月 1 日 |

#### 多份文档各自升版本

STD-AI-001、STD-AI-002…… 每份文档**独立**升版本，互不绑定。
小文档改一行，不用惊动主文档，也不用等它一起发版。

代价是引用时必须写清版本，**不能只写文档编号**：

| 写法 | 说明 |
|---|---|
| ✅ `见 STD-AI-002 §3（v1.0）` | 读者知道该去翻哪一版 |
| ❌ `见 STD-AI-002 §3` | 对方升版后，这个引用可能已经指向不存在的内容 |

被引用文档升版本时，**由发起升级的人**负责搜一遍仓库、更新所有引用处。
`tools/check-release.ps1` 会把「引用了不存在的章节号」直接报出来，不用靠人记。

#### 发版五步（照做即可，不用背）

```
1. 建分支    git checkout main
             git pull
             git checkout -b patch/简短描述        # 次版本用 feature/xxx，主版本用 release/vX.0

2. 改文档    只改该改的，不夹带无关调整

3. 三处同步  ① 文档头部表格的「版本」字段
             ② 附录 D 变更记录加一行
             ③ CHANGELOG.md 加一段

4. 跑校验    powershell -File tools\check-release.ps1
             全绿才提 PR。红了按提示改，别忽略

5. 合并打标签  PR 合并后：
             git tag std-ai-001-v1.2.1
             git push --tags
```

第 3 步的「三处同步」是最容易漏的一步（改了正文忘了更新版本表），
所以第 4 步的脚本专门查这个 —— 三处版本号不一致会直接报红。

#### 已知问题登记

发现的缺陷不立刻修也没关系，但**必须登记到 `KNOWN-ISSUES.md`**。
只写在群里或某个人脑子里的缺陷等于不存在。

登记一条只要三行：什么问题、影响谁、打算怎么修。修复后在发版时把状态改成「已修复」并注明版本号。

---

## 13. 交付标准（DoD）

1. 从公司模板创建，目录结构合规
2. `README.md` 写清构建、部署、端口、依赖、数据表
3. `deploy.ps1` 可一键部署、可回滚
4. 断网环境能 `restore + build + publish`
5. 有 `/health` 端点，Nginx 能探活
6. 日志结构化，能按 TraceId 追一次请求
7. 数据库迁移脚本入库，可重复执行
8. 有备份与恢复演练记录
9. 通过 CI（编译、单测、格式、密钥扫描）
10. 有使用说明与培训记录，业务方签字确认“有人在用”

---

## 14. 落地计划

| 阶段 | 时间 | 任务 | 产出 |
|---|---|---|---|
| P1 | 第 1 周 | 服务器基线：必装 .NET Hosting Bundle、SQL Server 2025、Nginx、Git、Gitea；按需装 Garnet / Ollama / Python（按第 15 节定档决定，不在无需求时预装） | 能跑 hello world |
| P2 | 第 2 周 | 离线源 + 项目模板 + `deploy.ps1` | 断网可构建 |
| P3 | 第 3 周 | 试点：车间日报 / 报价助手 | 一个上线项目 |
| P4 | 第 4 周 | 评审 + 培训 + 冻结 v1.x | 团队签字 |
| P5 | 90 天 | 覆盖 3 条业务线各 1 个场景 | 复盘报告 |

---

## 15. 规模分级与标准裁剪

> 完整判据、分档矩阵与登记模板见配套文档 **STD-AI-002《内网自研系统规模分级与裁剪指南》**。本节只给出主文档使用者必须先知道的四条。

本标准的基线假设是"一台服务器承载多个内网系统"，但真实项目规模跨度极大：从 20 人用的部门台账，到几百人带 AI 的分析平台。若一律按最重配置执行，会出现两类相反的错误：**小系统过度建设**（照抄全组件，单机七八个进程互相抢内存，没人说得清哪个是必需的）与**小系统借机摆烂**（以"内部小工具"为由不写 `deploy.ps1`、迁移不入库、不做越权校验，半年后无人能接手）。

本节把这些张力收敛为一条规则：**基线不变，可裁剪的是"装多少组件、做多严演练、留多少证据"，且裁剪必须登记。**

### 15.1 开工前必须先定档

任何新项目在写第一行代码前，先按三轴判定规模档位（**任一轴命中高档则整体定高档**）：

| 判据 | S（小型） | M（中型） | L（大型） |
|---|---|---|---|
| 注册用户 / 峰值并发 | ≤ 50 / ≤ 10 | 50–500 / ≤ 50 | > 500 或跨部门强隔离 |
| 是否调用大模型 | 否 | 只读问答、内容生成 | Agent 多步、带工具调用 |
| 是否写回外部生产库 | 否 | 否（只读集成） | 是 |

定档结论、判据数字、定档人必须写进项目 `README.md`。评审人不看内容先看这一项，缺失直接打回。

### 15.2 哪些能裁、哪些绝不能裁

- **可裁**（按档位执行，登记即可，**不必逐个提 ADR**）：Garnet 是否部署、Python 侧车与 AiGateway 是否引入、应用实例数、备份频率与保留期、RPO/RTO、恢复演练频次、压测范围、单测范围、Dashboard 是否开放、离线锁文件中不适用项的豁免。
- **绝不可裁**（与规模无关，12 条）：五条铁律、四层目录结构、中央包管理、参数化 SQL、密钥不入 Git、RBAC + 数据范围 + 服务端二次鉴权、TraceId 贯穿、`/health` + `deploy.ps1` + 30 秒可回滚、迁移脚本入库、**备份至少被真实恢复验证过一次**、核心逻辑（状态机/金额与进度计算/权限/导出）有单测、数据分级判定与审计 180 天。

> 口诀：**栈不许变、安全不许降、可回滚不许省、证据不许缺。**

### 15.3 裁剪登记与 ADR 的分工

| 情形 | 处理 | 批准人 |
|---|---|---|
| 在 STD-AI-002 §3 矩阵的所属档位列内 | **免 ADR**，在项目 README「裁剪声明」表登记一行 | 项目负责人自签 |
| 偏离基线（标准禁止项要做，或 S 档却提前引入高档组件） | **必须走 ADR**（第 12 节） | 架构负责人签字 |
| 不确定属于哪类 | **先问，不要先做了再说**（§2.2） | — |

这条分工的目的不是放松管控，而是**把 ADR 的注意力留给真正的偏离**。当"不装 Garnet"也要排队评审时，评审人会开始批量签字，真正需要讨论的决策反而被淹没。

### 15.4 升档触发条件

以下任一变化出现，立即重新定档并按新档补做，不要沿用 S 档假设打补丁：

- 用户数突破 50 或峰值并发突破 10；
- **应用实例数从 1 变 2**（此时会话与外部服务凭证必须跨进程共享——典型故障是两边各自刷新同一个 access_token 互相顶掉，表现为偶发凭证失效、重启后好一阵又复发。这是升档最常见的第一个技术后果，须引入 Garnet）；
- 引入任何大模型调用（→ 补 Python 侧车、AiGateway、数据分级评估、Prompt 审计）；
- 需要写回外部生产库（→ 定 L 档，补对账与中间表）；
- 单库突破 5 GB，或核心表进入千万行级；
- 业务要求 RPO 短于 4 小时。

> **升档是"补装"，不是"重构"——前提是从第一天就按本标准走抽象层。** 代码只依赖 `IDistributedCache`，那么 S→M 装 Garnet 是加一个 Provider 加一行配置；若一开始就随手 `Dictionary` 存缓存、把配置硬编码进代码，升档必然重写。统一模板真正的回报不在于让代码长得一样，而在于**让"系统变大"这件事的成本可控**。

---

## 附录 A 配置样例

### A1. global.json

```json
{
  "sdk": {
    "version": "10.0.100",
    "rollForward": "latestPatch"
  }
}
```

### A2. nuget.config

```xml
<?xml version="1.0" encoding="utf-8"?>
<configuration>
  <packageSources>
    <clear />
    <add key="internal" value="D:\Packages\nuget" />
  </packageSources>
</configuration>
```

### A3. Directory.Packages.props

```xml
<Project>
  <PropertyGroup>
    <ManagePackageVersionsCentrally>true</ManagePackageVersionsCentrally>
  </PropertyGroup>
  <ItemGroup>
    <!-- 版本由架构负责人每季度统一更新，项目内不得写版本号 -->
    <PackageVersion Include="Microsoft.EntityFrameworkCore.SqlServer" Version="10.0.0" />
    <PackageVersion Include="Microsoft.EntityFrameworkCore.Design" Version="10.0.0" />
    <PackageVersion Include="Dapper" Version="2.1.66" />
    <PackageVersion Include="Serilog.AspNetCore" Version="9.0.0" />
    <PackageVersion Include="Hangfire.AspNetCore" Version="1.8.22" />
    <PackageVersion Include="Hangfire.SqlServer" Version="1.8.22" />
    <PackageVersion Include="FluentValidation.AspNetCore" Version="11.3.1" />
    <PackageVersion Include="StackExchange.Redis" Version="2.8.31" />
    <PackageVersion Include="Microsoft.Extensions.Hosting.WindowsServices" Version="10.0.0" />
    <PackageVersion Include="xunit" Version="2.9.3" />
    <PackageVersion Include="Shouldly" Version="4.3.0" />
  </ItemGroup>
</Project>
```

### A4. appsettings.json（生产密钥用环境变量覆盖）

```json
{
  "ConnectionStrings": {
    "Default": "Server=127.0.0.1;Database=AppDb;User Id=app_user;Encrypt=True;TrustServerCertificate=True"
  },
  "AiGateway": {
    "BaseUrl": "http://127.0.0.1:5100",
    "ChatModel": "qwen2.5:14b-instruct",
    "EmbeddingModel": "bge-m3",
    "TimeoutSeconds": 60
  },
  "Serilog": {
    "MinimumLevel": "Information",
    "WriteTo": [
      { "Name": "File", "Args": { "path": "D:\\Logs\\App\\log-.json", "rollingInterval": "Day", "retainedFileCountLimit": 30 } }
    ]
  },
  "AllowedHosts": "*"
}
```

> 密码不写文件：用环境变量 `ConnectionStrings__Default` 覆盖。

### A5. nginx.conf（核心片段）

```nginx
server {
    listen 443 ssl;
    server_name ai.internal;

    ssl_certificate     D:/Certs/ai.crt;
    ssl_certificate_key D:/Certs/ai.key;

    client_max_body_size 100m;

    # 前端静态资源
    location / {
        root D:/Apps/portal/current/wwwroot;
        try_files $uri $uri/ /index.html;
    }

    # 普通 API
    location /api/report/ {
        proxy_pass http://127.0.0.1:5001;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }

    # AI 流式接口：必须关闭缓冲
    location /v1/ {
        proxy_pass http://127.0.0.1:5100;
        proxy_http_version 1.1;
        proxy_set_header Connection "";
        proxy_buffering off;
        proxy_read_timeout 300s;
        proxy_set_header Host $host;
    }
}
```

### A6. deploy.ps1 骨架

```powershell
param(
    [Parameter(Mandatory)][string]$App,
    [Parameter(Mandatory)][string]$Version,
    [Parameter(Mandatory)][string]$Zip,
    [Parameter(Mandatory)][int]$Port
)
$ErrorActionPreference = "Stop"
$root   = "D:\Apps\$App"
$target = Join-Path $root $Version
$svc    = "app-$App"

Stop-Service $svc -ErrorAction SilentlyContinue
if (Test-Path $target) { Remove-Item $target -Recurse -Force }
Expand-Archive -Path $Zip -DestinationPath $target

# 切换 current（目录联接）：先删链接再重建，只删链接不删内容
cmd /c rmdir "$root\current" 2>$null
cmd /c mklink /J "$root\current" $target | Out-Null

Start-Service $svc
$ok = $false
for ($i = 0; $i -lt 20; $i++) {
    try {
        Invoke-RestMethod "http://127.0.0.1:$Port/health/ready" -TimeoutSec 2 | Out-Null
        $ok = $true; break
    } catch { Start-Sleep -Seconds 2 }
}
if (-not $ok) {
    Write-Error "健康检查失败：请切换 current 到上一版本并重启服务"
    exit 1
}
Write-Host "部署成功：$App $Version"
```

### A7. .gitignore

```gitignore
bin/
obj/
publish/
.vs/
.idea/
node_modules/
dist/
*.user
*.suo
*.log
appsettings.*.local.json
D:/Secrets/
```

---

## 附录 B 速查卡

**开工四件套**：`global.json`、`nuget.config`、`Directory.Packages.props`、`.editorconfig`

**提交前五问**：
1. 包是不是白名单里的？
2. 有没有硬编码密码？
3. 断网能构建吗？
4. 日志会不会打出敏感数据？
5. 出问题能在 30 秒内回滚吗？

**禁止**：Node 写后端、第二个数据库、直连模型、Docker Desktop、未锁版本、直连生产库。

**求助路径**：缺包 → 架构负责人；端口 → 架构负责人；例外 → 写 ADR。

---

## 附录 C 术语表

| 术语 | 含义 |
|---|---|
| BP | Business Partner，业务合作伙伴：嵌入业务部门、共担指标的协作方式 |
| RAG | 检索增强生成：先查知识库，再让模型基于检索结果回答 |
| Agent | 能自主调用工具、分多步完成任务的 AI 程序 |
| MCP | 模型调用外部工具/数据的统一协议，可理解为“AI 的 USB 接口” |
| 沙盒 | 隔离的运行环境，AI 生成的代码先在里面跑，确认后再落生产 |
| Embedding | 把文本转成向量，用于相似度检索；维度必须全公司统一 |
| LoRA | 低成本微调方法，只训练少量参数 |
| AiGateway | 公司自建的模型统一出口，负责路由、鉴权、限流、审计 |
| ADR | 架构决策记录，记录“为什么这么选” |
| DoD | Definition of Done，交付完成标准 |
| LTS | 长期支持版本，享受多年安全更新 |

---

## 附录 D 变更记录

> 版本号怎么升、补丁要不要签字、新增强制项如何过渡 —— 见 **§12.1**。
> 已发现但尚未修复的问题登记在仓库根目录的 `KNOWN-ISSUES.md`。

| 版本 | 日期 | 变更 | 作者 |
|---|---|---|---|
| v1.0 | 2026-10-23 | 初版：选型、架构、离线依赖、AI 约束、DoD | AI BP |
| v1.1 | 2026-10-27 | 增加角色职责、数据分级、备份恢复、AI 编码助手边界、集成边界、配置样例、术语表、ADR 机制；补充授权风险与 PR 清单；细化资源规划与部署流程 | AI BP |
| v1.2 | 2026-10-27 | 新增第 15 节「规模分级与标准裁剪」并配套 STD-AI-002 指南；明确铁律 5 只约束构建/部署期、不禁止运行期受控出站；§3.3 缓存、§6.2 交付四件套、§12 ADR 三处补充档内裁剪与登记口径 | AI BP |
| v1.3 | 2026-10-29 | 新增 **§12.1 标准文档自身的版本规则**：三段式版本语义（补丁 / 次版本 / 主版本，按"改动方向"而非"改动大小"判定）、补丁免架构负责人签字、新增强制项对存量项目的过渡窗口、多文档独立升版与引用须带版本号、发版五步清单；新增 `KNOWN-ISSUES.md` 已知问题登记与 `tools/check-release.ps1` 发版前自动校验（三处版本号一致性、章节交叉引用有效性、配套文档登记完整性） | AI BP |
