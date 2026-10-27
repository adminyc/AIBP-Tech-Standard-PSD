# 内网 AI 开发技术栈标准 v1.0

> 适用对象：AI BP 团队，以及后续用 AI 开发的任何内部系统
> 适用环境：单台内网服务器（Windows Server）、无外网或受限外网
> 基线日期：2026-10　|　评审周期：每季度一次　|　负责人：架构负责人（一票裁决权）
> 一句话：**语言只能 C#，平台只能 .NET，数据库只能 SQL Server，模型只能走网关，任何项目断网也能构建和部署。**

---

## 0. 一页纸结论

| 层 | 选型 | 版本基线 | 说明 |
|---|---|---|---|
| 操作系统 | Windows Server | 2022 / 2025 | 与 SQL Server、.NET 同生态，运维成本最低 |
| 后端语言 | C# | C# 13 / 14 | 唯一允许的业务后端语言 |
| 后端平台 | .NET | **.NET 10 LTS** | 2025-11 发布，支持至 2028-11；新项目一律 10 |
| Web 框架 | ASP.NET Core | 10.x | WebAPI 为主，Razor Pages 做简单页面 |
| ORM | EF Core + Dapper | EF Core 10 / Dapper 2.x | CRUD 用 EF，复杂报表用 Dapper |
| 数据库 | SQL Server | **2025（17.x）** | 关系数据 + 原生 VECTOR，一个库搞定 |
| 缓存 | Garnet | 1.x | Redis 协议兼容、Windows 原生；不装 Redis for Windows |
| 前端 | Vue 3 + TypeScript + Element Plus | Vue 3.5 / TS 5.x | 只允许这一套 |
| 前端构建 | Node.js | 24 LTS（锁死） | **仅构建期使用，生产服务器不装 Node** |
| AI 能力 | Python | 3.12.x | 只做训练/推理/文档解析，通过 HTTP 被 .NET 调用 |
| 模型运行时 | Ollama（Windows）/ vLLM（Linux GPU） | 最新稳定版 | 只监听 127.0.0.1 |
| AI 网关 | 自研 `AiGateway`（.NET） | — | 所有模型调用的唯一出口 |
| 反向代理 | Nginx | 1.28 stable | 唯一对外入口，TLS 终止 |
| 版本管理 | Git + Gitea | Git 2.5x / Gitea 1.2x | 保护 main 分支，PR 评审 |
| 后台任务 | Hangfire | 1.8.x | 存储用 SQL Server，不引入 MQ |
| 日志 | Serilog | 4.x | JSON 文件 + 可选 Seq |
| 容器 | **不用 Docker** | — | 见第 5 节，满足条件再评估 |
| 依赖来源 | 内网离线源 | — | NuGet / npm / pip / 模型全部本地化 |

---

## 1. 为什么必须统一（三个真实会发生的失败）

1. **装不下**：三个人用 AI 生成三套栈（Next.js + PostgreSQL、Python FastAPI + MySQL、.NET + SQLite），一台服务器要装三个运行时、三个数据库，端口和依赖互相打架。
2. **装不上**：内网没有外网，`npm install`、`pip install`、`dotnet restore` 全部失败。技术栈不统一时，离线包要准备三份，没人维护得过来。
3. **接不住**：人一走，留下的项目没人能改。统一栈的本质是**降低单点依赖**，让任何一个人都能接手任何项目。

---

## 2. 五条铁律

1. **一个后端语言**：C# / .NET。Node、Python、Go 不写业务后端。
2. **一个数据库**：SQL Server。关系数据、向量、任务队列、日志归档都在里面。
3. **一个入口**：Nginx。所有服务只监听 127.0.0.1，对外只有 80/443。
4. **一个 AI 出口**：所有模型调用走 `AiGateway`，应用不直连 Ollama / vLLM / 外部 API。
5. **离线可还原**：任何项目在断网机器上都能 `restore → build → publish → deploy`。

---

## 3. 选型细则

### 3.1 后端：.NET 10 + C#

- 新项目一律 `net10.0`；已上线的 .NET 8 项目在 2027 年前升级，不再新开 .NET 8。
- 第三方库没有 .NET 10 版本时，**降级库，不降级框架**；实在没有替代，走 ADR 例外。
- 对接只支持 .NET Framework 的旧 SDK（部分 MES / 上位机组件）时，单独做一个 **Adapter 服务**（可用 .NET Framework 4.8 或 COM 互操作），通过 HTTP 暴露，**不得把 .NET Framework 引入新项目**。
- 禁止：WinForms/WPF 做新系统的管理端（保留给设备上位机场景）；Blazor 与 Vue 混用（二选一，本标准选 Vue）。

### 3.2 数据库：SQL Server 2025

- 关系数据 + 向量统一在一个实例：`VECTOR(1024)` 存 embedding，`VECTOR_DISTANCE` 做相似度。
- 向量索引（`CREATE VECTOR INDEX`）目前是预览特性，**先不开**；数据量 < 10 万 chunk 时精确检索够用，超过或延迟不达标再评估 Qdrant。
- 现有 2022 实例不强制升级，但新库建在 2025 上；升级窗口统一安排。
- 规范：`READ_COMMITTED_SNAPSHOT ON`、每库独立登录名、禁用 `sa`、夜间全备 + 每小时日志备份到 NAS。
- 排序规则统一 `Chinese_PRC_CI_AS`；字符串一律 `nvarchar`；时间一律 `datetime2` 存 UTC。

### 3.3 缓存：Garnet，不用 Redis for Windows

- Windows 没有官方 Redis（微软移植版停在 3.x，有已知问题）。用 **Garnet**（微软开源、Redis 协议兼容、Windows 原生、单文件）。
- 客户端统一 `StackExchange.Redis`，代码里只依赖 `IDistributedCache` 抽象。
- 用途限定：缓存、会话、分布式锁、限流计数。**不作为主存储，不存业务唯一数据。**
- 单机场景优先 `IMemoryCache`；确需跨进程共享再上 Garnet。

### 3.4 前端：Vue 3 + TypeScript + Element Plus，Node 只做构建

- 一套：Vue 3 + TS + Vite + Element Plus + Pinia + Vue Router。
- Node 24 LTS 锁死（`.nvmrc` / Volta），提交 `package-lock.json`，用 `npm ci`。
- **生产服务器不装 Node**：构建产物是静态文件，由 ASP.NET Core 静态托管或 Nginx 托管。
- 禁止：React / Angular / Next.js / Nuxt；禁止用 Node 写 BFF 或后端接口。

### 3.5 Python：只做 AI 能力，不做业务

- 版本 3.12.x（AI 库兼容性最好），依赖锁 `requirements.txt`（含 hash），用 `uv` 安装。
- 只允许三类职责：模型训练/微调、推理服务、文档解析与 OCR。
- 对外只暴露 HTTP（FastAPI + uvicorn），由 .NET 调用；**Python 不直连业务库写数据**，需要数据走 .NET 的只读接口或只读视图。
- 服务以 Windows 服务方式常驻（NSSM），监听 127.0.0.1:5200。

### 3.6 AI 网关：所有模型调用的唯一出口

- 自研 `AiGateway`（ASP.NET Core），对外提供 OpenAI 兼容的 `/v1/chat/completions`、`/v1/embeddings`。
- 职责：路由（本地 Ollama / 远程 API）、密钥管理、限流、超时重试、Token 计费、审计日志（Prompt/响应脱敏）、模型白名单。
- 应用侧只配一个地址：`http://127.0.0.1:5100`。**禁止任何应用直连 11434 或外部模型 API。**
- 好处：换模型不改业务代码；出问题一处排查；成本可计量。

### 3.7 模型与向量：全公司只用一个 embedding

- 对话模型：Qwen 系列 / DeepSeek 蒸馏版，GGUF 格式，Ollama 加载；GPU 富余时上 vLLM（Linux）。
- **Embedding 统一 `bge-m3`，1024 维**。维度不一致 = 向量库作废，这是最容易踩的坑。
- Rerank 统一 `bge-reranker-v2-m3`。
- 模型文件按 `名称-版本-量化级别.sha256` 存档到 NAS，**禁止使用 latest 标签**。
- 训练在 GPU 工作站完成，产物（LoRA adapter / GGUF）经审批后拷贝到服务器，**不在生产服务器上训练**。

### 3.8 入口与部署：Nginx + Windows 服务

- Nginx 1.28，只做三件事：TLS 终止、静态资源、反向代理。
- AI 流式响应必须关闭缓冲：`proxy_buffering off; proxy_read_timeout 300s;`，否则前端看不到逐字输出。
- 应用以 Windows 服务运行（`Microsoft.Extensions.Hosting.WindowsServices`），只绑 `127.0.0.1`。
- 版本目录 + `current` 目录联接切换，回滚 = 切回上一个目录，30 秒完成。

### 3.9 Git 与协作

- 自建 Gitea（比 GitLab 轻，单机够用），内网访问。
- `main` 保护：禁止直接 push，必须 PR + 1 人评审；AI 生成的代码同样走 PR。
- 分支：`main` + `feature/xxx`，短分支，合并后删除。
- 提交信息：`type(scope): subject`（feat/fix/docs/refactor/chore）。
- 大文件（模型、安装包、数据）不进 Git，放 NAS；文档可用 Git LFS，但单文件 < 50MB。
- 仓库必须含：`README.md`、`deploy.ps1`、`nuget.config`、`global.json`、`.editorconfig`。

---

## 4. 单机部署架构

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

**端口分配表**

| 端口 | 用途 | 绑定 |
|---|---|---|
| 80 / 443 | Nginx | 0.0.0.0 |
| 1433 | SQL Server | 127.0.0.1 |
| 5001–5099 | 业务应用（每个应用一个） | 127.0.0.1 |
| 5100 | AiGateway | 127.0.0.1 |
| 5200 | Python AI 服务 | 127.0.0.1 |
| 11434 | Ollama | 127.0.0.1 |
| 6379 | Garnet | 127.0.0.1 |
| 3000 | Gitea | 127.0.0.1 |

**磁盘目录规范**

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
D:\Backup                     数据库备份（再同步到 NAS）
```

### 4.1 资源与容量（单机最容易翻车的地方）

| 资源 | 建议 | 说明 |
|---|---|---|
| CPU | 16 核以上 | SQL Server、.NET、Python 抢核，留余量 |
| 内存 | 64GB 起 | **SQL Server 必须设 `max server memory`（24–32GB）**，否则它会吃掉几乎所有内存，把模型挤崩 |
| GPU | 24GB 显存（4090 / L20） | 跑 14B–32B 量化模型；无 GPU 只能跑 7B–8B，效果明显下降 |
| 磁盘 | 系统盘 200GB SSD + 数据盘 1TB NVMe | 模型权重与备份放 NAS，不占本地盘 |

> 单机部署的第一杀手不是 CPU 而是内存。装完 SQL Server 第一件事就是设上限，第二件事是给 Ollama 留出显存预算。

---

## 5. Docker 用不用：v1.0 不用

**结论：不用。** 单机 + Windows + 内网离线，容器的收益（环境一致、快速扩缩容）用不上，成本（镜像搬运、离线仓库、Windows 容器体验、Docker Desktop 商用授权）全都要付。

- Docker Desktop 对大型企业收费（员工 > 250 人或年收入 > 1000 万美元需订阅），内网也不该引入授权风险。
- Windows 容器需要 Windows Server 容器运行时，镜像体积大、构建慢，调试体验差。
- `dotnet publish` + 版本目录 + `deploy.ps1` 已经能做到“可重复、可回滚”，这就够了。

**什么时候再评估（三条同时满足）**：
1. 出现 ≥ 3 个需要独立伸缩或强隔离的服务；
2. 有 Linux 主机（或计划上 K8s）；
3. 有内网镜像仓库（Harbor）。

届时用 **Linux + containerd/Podman + Harbor**，不用 Docker Desktop；Windows 容器只用于 CI 构建，不上生产。

---

## 6. 离线依赖：这是内网落地真正的难点

| 生态 | 做法 | 存放位置 |
|---|---|---|
| NuGet | 外网机 `dotnet restore` 拉全量包 → 拷贝 `.nupkg` 到本地源；`nuget.config` 里 `<clear/>` 只留本地源 | `D:\Packages\nuget` |
| npm | 外网机 `npm ci` 后打包 `node_modules` + 提交 lockfile；或内网 Verdaccio 私服 | `D:\Packages\npm` |
| pip | `pip download -r requirements.txt -d wheelhouse --only-binary=:all:`，内网 `pip install --no-index --find-links` | `D:\Packages\pip` |
| 模型 | 外网下载 GGUF / safetensors，校验 SHA256，经审批拷贝 | NAS → `D:\Packages\models` |
| 安装介质 | SQL Server ISO、.NET Hosting Bundle、Node MSI、Python 安装包、Nginx zip、Garnet zip、Git | NAS `\\nas\software` |

**硬性要求**：每个项目仓库里必须有 `nuget.config`（指向内网源）、`global.json`（锁 SDK 版本）、`.nvmrc` / `package.json` 的 `engines`、`requirements.txt`（含版本）。**没有这四样，不算交付。**

---

## 7. 项目模板：让 AI 没机会自由发挥

统一用 `dotnet new` 公司模板创建项目，模板里已经内置：

- 分层目录：`src/Api`、`src/Application`、`src/Domain`、`src/Infrastructure`、`tests/`
- 统一返回结构 `{ code, message, data, traceId }` + 全局异常中间件 + 错误码表
- Serilog 结构化日志（含 TraceId、UserId、AppId）
- JWT / Cookie 鉴权 + RBAC 权限过滤器
- EF Core + 迁移脚本 + Dapper 注册
- 健康检查 `/health/live`、`/health/ready`
- OpenAPI 文档（内置 `Microsoft.AspNetCore.OpenApi`）
- `deploy.ps1`：停服务 → 备份 → 拷贝 → 切 current → 启动 → 健康检查 → 失败自动回滚
- `README.md`：怎么构建、怎么部署、端口、依赖、数据表、联系人

**模板之外的新结构，一律视为不合规。**

依赖版本集中管理：根目录 `Directory.Packages.props` 统一版本，项目里只写 `<PackageReference Include="..." />`，不写版本号。AI 最常干的事就是随手加包、随手升级，这一条直接堵死。

---

## 8. AI 生成代码的十条约束

1. **从模板起步**：只用 `dotnet new aibp-*`，不手工搭架子。
2. **只用白名单包**：新增 NuGet / npm / pip 包必须评审，写进 `Directory.Packages.props` 或 `package.json` 统一管理。
3. **禁止幻觉包**：AI 推荐的包名可能是编的（slopsquatting），必须核对官方仓库、作者、下载量；内网核对不了就由架构负责人统一审。
4. **禁止第二套技术**：不引入第二个 ORM、日志库、前端框架、数据库。
5. **禁止微服务**：单库单服务优先，不上 K8s、不上消息队列、不上 GraphQL；确有需要走 ADR。
6. **禁止直连模型**：所有调用走 AiGateway。
7. **禁止硬编码**：连接串、密钥、模型地址一律配置化，密钥不进 Git。
8. **禁止自研基础设施**：认证、加密、ORM、序列化一律用成熟库。
9. **必须能离线构建**：PR 前在断网环境跑一次 `restore + build + publish`。
10. **必须过 CI**：编译、单测、`dotnet format`、密钥扫描（gitleaks）、依赖漏洞检查，全绿才能合并。

### 明确禁止清单

| 禁止 | 原因 |
|---|---|
| Node / Python / Go 写业务后端 | 部署与运维碎片化 |
| React / Angular / Next.js 与 Vue 并存 | 前端两套构建链 |
| MySQL / PostgreSQL / MongoDB / ES 作为主存储 | 备份、权限、运维翻倍 |
| Redis for Windows（3.x 移植版） | 停更、有已知缺陷，用 Garnet |
| Docker Desktop | 商用授权 + 离线镜像成本 |
| AI 脚本/工具直连生产库 | 误操作与数据泄露 |
| 未锁版本的依赖（`latest`、`*`） | 构建不可重复 |
| 大段复制来源不明代码 | 开源授权风险 |
| 把生产数据贴进外部 AI 对话 | 数据外泄 |
| AutoMapper / MediatR / FluentAssertions 8+ / EPPlus / QuestPDF | 已转商业授权或有版本授权陷阱，用替代品（手写映射、Shouldly、ClosedXML、OpenXml） |

---

## 9. 编码规范（只列会被 AI 写错的）

- **API**：REST，路径 `/api/v1/{resource}`；JSON 字段 camelCase；分页 `page/pageSize`；时间 ISO 8601 UTC；错误用统一错误码，不用 HTTP 200 包错误。
- **数据库**：表名 PascalCase 单数；主键 `Id`（bigint identity 或 GUID）；必须有 `CreatedAt/UpdatedAt`；软删除用 `IsDeleted`；禁止 `SELECT *` 进生产代码；禁止拼接 SQL。
- **事务**：跨表写操作必须显式事务；长事务禁止包 HTTP 调用。
- **日志**：只记结构化字段，不打印完整 Prompt、身份证、手机号、密码；日志级别默认 Information。
- **配置**：`appsettings.json`（默认）+ `appsettings.{Env}.json`（环境）+ 环境变量覆盖；生产密钥放 `D:\Secrets`，ACL 限制。
- **时间**：数据库存 UTC，前端按本地时区展示；禁止在代码里写死 `DateTime.Now`。
- **文件**：上传文件存 `D:\Data\{app}\uploads\{yyyyMM}`，DB 只存相对路径；文件名用 GUID，不用原名。
- **后台任务**：Hangfire，任务必须幂等、可重试、有超时。
- **AI 调用**：必须设置超时（默认 60s，流式 300s）、重试（最多 2 次）、降级（模型不可用时返回明确提示，不阻塞主流程）。

---

## 10. 安全（内网不等于安全）

- **账号**：一人一账号，禁用共享账号；SQL Server 每应用独立登录名，只给所需库的 `db_datareader/db_datawriter`，禁用 `sa`。
- **密钥**：不进 Git、不进日志、不进前端；统一放 `D:\Secrets`，部署时注入环境变量。
- **权限**：RBAC，菜单 + 接口双重校验；数据权限按部门/产线隔离。
- **审计**：登录、导出、删除、AI 调用（谁、什么时候、问了什么、用了哪个模型）留痕 180 天。
- **提示词注入**：知识库文档视为不可信输入；系统提示与用户输入分离；工具调用加白名单，禁止模型直接执行 SQL/Shell。
- **沙盒**：AI 生成的代码若要执行，必须在隔离进程/临时目录里跑，禁止直接操作生产库。
- **外部 AI**：内网开发机默认不接入外部模型；确需使用，走公司账号，禁止上传代码与业务数据。

---

## 11. 版本与升级

- 只选 **LTS**：.NET、Node、Python、SQL Server 都用 LTS/稳定版，不用预览版。
- 每季度评审一次版本表，统一升级窗口（每半年一次），禁止个人随时升级。
- 升级前必须：跑通全部项目构建 + 回归测试 + 备份数据库。
- 任何偏离本标准的决定，写 **ADR**（背景、选项、决定、影响），架构负责人签字，存档在 `docs/adr/`。

---

## 12. 交付标准（Definition of Done）

一个项目算“交付”，必须同时满足：

1. 从公司模板创建，目录结构合规；
2. `README.md` 写清构建、部署、端口、依赖、数据表；
3. `deploy.ps1` 可一键部署、可回滚；
4. 断网环境能 `restore + build + publish`；
5. 有 `/health` 端点，Nginx 能探活；
6. 日志结构化，能按 TraceId 追一次请求；
7. 数据库迁移脚本入库，可重复执行；
8. 有备份与恢复演练记录；
9. 通过 CI（编译、单测、格式、密钥扫描）；
10. 有使用说明与培训记录，业务方签字确认“有人在用”。

---

## 13. 四周落地计划

| 周 | 做什么 | 产出 |
|---|---|---|
| 第 1 周 | 服务器基线：装 .NET Hosting Bundle、SQL Server 2025、Nginx、Garnet、Git、Gitea、Ollama | 一台能跑 hello world 的机器 |
| 第 2 周 | 离线源 + 项目模板 + `deploy.ps1` | `dotnet new aibp-webapi` 可用，断网能构建 |
| 第 3 周 | 选 1 个真实小场景（车间日报 / 报价助手）试点 | 一个上线项目，跑通全流程 |
| 第 4 周 | 规范评审 + 全员培训 + 冻结 v1.0 | 团队签字，纳入考核 |

---

## 附：新项目开工清单（打印贴墙）

- [ ] `dotnet new aibp-webapi -n Xxx`
- [ ] `global.json` 锁 10.0.x，`nuget.config` 指向内网源
- [ ] 建库：独立登录名、`READ_COMMITTED_SNAPSHOT ON`、备份作业
- [ ] 端口登记（5001–5099 找架构负责人要）
- [ ] 模型调用只配 `AiGateway` 地址
- [ ] 前端 `npm ci`，产物交给 ASP.NET 静态托管
- [ ] `deploy.ps1` + `README.md` + `/health`
- [ ] PR 评审 → CI 全绿 → 测试环境 → 业务验收 → 上线
