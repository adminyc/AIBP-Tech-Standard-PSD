# 已知问题登记

本文件登记**已发现但尚未修复**的标准缺陷。

规则见 STD-AI-001 §12.1：发现的缺陷不立刻修没关系，但必须登记在这里。
只写在群里、或只存在于某个人脑子里的缺陷，等于不存在。

登记一条只要四行：**什么问题 / 影响谁 / 建议怎么修 / 状态**。
修复后把状态改成「已修复」并注明版本号，不要删行 —— 保留历史才能看出标准是怎么演进的。

---

## 状态汇总

| 编号 | 问题 | 严重度 | 状态 |
|---|---|---|---|
| KI-001 | 附录 A3 的包版本号已过期 | 中 | 待修 |
| KI-002 | 附录 A3 推荐的 FluentValidation.AspNetCore 已停止维护 | 高 | 待修 |
| KI-003 | §8.1 只评审直接引用，传递依赖的高危漏洞无人管 | **高** | 待修 |
| KI-004 | 附录 A2 的 nuget.config 在开发机上会硬失败 | 中 | 待修 |
| KI-005 | §14 P2 要求的 `aibp-*` 项目模板此前并不存在 | 高 | 部分解决 |
| KI-006 | 标准是纯 .NET 视角，前端 npm 离线交付完全空白 | 中 | 待修 |
| KI-007 | `dotnet new` 默认生成的 `.slnx` 与内网工具链兼容性差 | 低 | 待修 |

> 严重度按「会不会导致安全事故或交付失败」判，不按修复难度判。

---

## KI-001 附录 A3 的包版本号已过期

**问题**：附录 A3 是 AI 辅助起草的，里面的版本号没有经过实际核对，现在已经全部落后。

| 包 | A3 写的 | 实际最新稳定版（2026-10-29 核对） |
|---|---|---|
| Microsoft.EntityFrameworkCore.SqlServer | 10.0.0 | **10.0.14** |
| Microsoft.EntityFrameworkCore.Design | 10.0.0 | **10.0.14** |
| Dapper | 2.1.66 | **2.1.89** |
| Serilog.AspNetCore | 9.0.0 | **10.0.0** |
| Hangfire.AspNetCore / .SqlServer | 1.8.22 | **1.8.25** |
| StackExchange.Redis | 2.8.31 | **3.4.20**（跨大版本，需评估） |

**影响**：照抄 A3 建项目，会拿到几个月前的旧版本。旧版本可能带已公开的安全漏洞，
而且「标准里写的版本」和「离线源里同步的版本」不一致时，还原会直接失败。

**建议修法**：
1. 更新 A3 的版本号到上表右列；
2. **在 A3 标题下加一行核对日期**，并注明「版本号必须实测核对，禁止照抄上一版」；
3. StackExchange.Redis 2.x → 3.x 是跨大版本，有 breaking change，单独评估后再改，不要顺手升。

**状态**：待修（属**补丁**级别 —— 修正写错的数字，不改变任何合规判定）

---

## KI-002 附录 A3 推荐的 FluentValidation.AspNetCore 已停止维护

**问题**：A3 里写的是 `FluentValidation.AspNetCore` 11.3.1。这个包**在 11.3 之后就不再跟随主库更新**，
主库 `FluentValidation` 已经到 12.2.0。也就是说 A3 推荐的是一个被上游放弃的包。

**影响**：新项目照抄会引入一个不再维护的依赖。它不会报错、不会警告，
只会在某个 .NET 版本升级后突然不兼容 —— 那时候排查成本远高于现在换掉。

**建议修法**：A3 改成两个包，删掉 `FluentValidation.AspNetCore`：

```xml
<PackageVersion Include="FluentValidation" Version="12.2.0" />
<PackageVersion Include="FluentValidation.DependencyInjectionExtensions" Version="12.2.0" />
```

并在 §8.2 授权风险清单旁边加一条「已停止维护的包」提示，避免同类问题再犯。

**状态**：待修（属**补丁**级别）

---

## KI-003 §8.1 只评审直接引用，传递依赖的高危漏洞无人管

**这条是本次登记里最严重的一条。**

**问题**：§8.1 要求「新增包必须评审并登记」，管的是 csproj 里写得出来的**直接引用**。
但真实项目里的高危漏洞，绝大多数藏在**传递依赖**里 —— 那些包在任何 csproj 中都搜不到。

**实证**（DeptPlan 项目实测，2026-10-27）：直接引用的包一个漏洞都没有，
`dotnet list package --include-transitive --vulnerable` 却报出两个高危：

| 漏洞包 | 谁带进来的 | 根因 |
|---|---|---|
| Newtonsoft.Json **11.0.1**（高危 GHSA-5crp-9r3c-p9vr） | Hangfire.Core 1.8.25 | Hangfire 只声明 `>= 11.0.1`，NuGet 取**最低满足版本**，于是落到 2018 年那个版本 |
| System.Security.Cryptography.Pkcs **9.0.11**（高危 GHSA-846f-f764-76mx + 中危 GHSA-2fmv-rv2c-59x7） | Microsoft.Data.SqlClient 6.1.7 ← EF Core SqlServer | 同理 |

**「新增包必须评审登记」这条纪律再严也拦不住这两个** —— 没人会去评审一个自己没写进 csproj 的包。

**建议修法**（三处都要改，缺一不可）：

1. **§8.1 新增一条强制要求**：所有项目的 `Directory.Packages.props` 必须开启传递依赖钉版：

   ```xml
   <PropertyGroup>
     <ManagePackageVersionsCentrally>true</ManagePackageVersionsCentrally>
     <CentralPackageTransitivePinningEnabled>true</CentralPackageTransitivePinningEnabled>
   </PropertyGroup>
   ```

   开启后，只有显式列了 `PackageVersion` 的包会被钉住，未列出的传递依赖不受影响，所以是安全的定向操作。

2. **附录 A3 增加两条钉版**（并注明为什么）：

   ```xml
   <!-- 传递依赖钉版：不在任何 csproj 里，但随上游被拉进来且默认版本带高危漏洞 -->
   <PackageVersion Include="Newtonsoft.Json" Version="13.0.4" />
   <PackageVersion Include="System.Security.Cryptography.Pkcs" Version="10.0.14" />
   ```

   **不要**为了修这个把 Microsoft.Data.SqlClient 跳到 7.x —— 那是跨大版本，与 EF Core 10 的兼容性未验证。

3. **§13 DoD 与 CI 各加一条**：
   - DoD 新增「`dotnet list package --include-transitive --vulnerable` 零命中」；
   - CI 流水线加这一步，有命中就红。

   注意校验方式是**逐项目跑 `dotnet list`**，不是看构建告警有没有消失 ——
   告警会被 `NoWarn`、日志级别、增量构建等各种原因吞掉。

**连带影响**：钉版的包必须同步进内网离线源 `D:\Packages\nuget`，否则还原时 `NU1301` 硬失败。
离线源同步清单的生成方式见 KI-004。

**状态**：待修（属**次版本**级别 —— 新增了强制要求，需架构负责人过 PR）

---

## KI-004 附录 A2 的 nuget.config 在开发机上会硬失败

**问题**：A2 给的配置是 `<clear />` + 只指向 `D:\Packages\nuget`。
这个路径是**服务器侧约定**，开发机上通常不存在。而 `<clear />` 屏蔽了所有公共源，
所以开发机上跑 `dotnet restore` 会直接 `NU1301` 报错终止 —— **不是警告，是硬失败**。

**影响**：新人拿到标准照抄 A2，在自己机器上第一步还原就失败，而且报错信息
（找不到源）离真正原因（这台机器不该用这份配置）有距离，容易卡半天。

**建议修法**：A2 改成**双文件方案**，并说明各自用途：

| 文件 | 用途 | 内容要点 |
|---|---|---|
| `nuget.config` | 开发机（随代码入库） | 指向 nuget.org 或公司内网 NuGet 代理，**不加 `<clear />`** |
| `nuget.intranet.config` | 内网服务器 / CI | `<clear />` + 只指向 `D:\Packages\nuget` |

部署时把 `nuget.intranet.config` 覆盖为 `nuget.config` 即可。

服务器侧**保留 `<clear />` 是对的，不要改** —— 它确保「断网可还原」是真的可还原，
而不是悄悄回落到公共源后蒙对了一次。静默回落会让「内网可构建」变成一次没人发现的假通过。

同时补一句离线源怎么生成：从能出网的机器上，用 `dotnet restore` 后各项目的
`obj/project.assets.json` 里 `libraries` 节点中 `type == "package"` 的键（形如 `包名/版本`）
提取完整闭包，逐个从 nuget.org flatcontainer 下载 `.nupkg` 铺进目录。
**这份清单必须包含传递依赖**，只按 csproj 里的直接引用去同步是不够的。

**状态**：待修（属**补丁**级别 —— 补上缺失的使用场景说明，不改变服务器侧要求）

---

## KI-005 §14 P2 要求的 `aibp-*` 项目模板此前并不存在

**问题**：§8.1 第 1 条要求「只用 `dotnet new aibp-*` 起步，不手工搭架子」，
§7.2 更写明「模板之外的新结构视为不合规」。但截至 2026-10-27，
**这个模板从来没有被造出来** —— 本机 36 个 `dotnet new` 模板全是内置的，离线源里也搜不到。

这不是"没找到"，是确实不存在：§14 P2 本身就把「产出项目模板」列为第 2 周任务。

**影响**：标准同时要求「必须从模板起步」和「模板外结构不合规」，而模板不存在 ——
这是一条**无法遵守的规则**。实际后果是要么手工搭架子（违反 §8.1），要么停工等模板。

**已做**：DeptPlan 项目中已按 §7.1 四层结构造出 `Aibp.Templates 1.0.0`（模板短名 `aibp-webapi`），
包含统一返回包、全局异常中间件、错误码表、Serilog + TraceId、Cookie 鉴权 + RBAC 权限过滤器、
EF Core 写 / Dapper 读分离、`/health/live` 与 `/health/ready`、OpenAPI、`deploy.ps1`、
DoD 与 PR 清单、ADR 模板、27 个框架契约测试。
已实测：打包 0 警告 → 安装 → 实例化（改名与端口注入正确）→ 构建 0 错误 0 警告 → 测试 27/27 通过。

**待办**：
1. 把模板回收到本仓库（建议放 `templates/`，作为 §7 的配套交付物）；
2. §7 补一节说明模板的安装、参数（`-n` / `--port` / `--skipRestore`）与修改后的验证流程；
3. §14 P2 的状态更新为已完成。

**状态**：部分解决（模板已造出并实测，**尚未回收入仓库**）

---

## KI-006 标准是纯 .NET 视角，前端 npm 离线交付完全空白

**问题**：标准把 Vue 3 + Element Plus 列为强制前端栈，但**离线依赖（§6）通篇只讲 NuGet**，
对 npm 一个字都没提。而前端依赖数量和体积都不小（DeptPlan 实测 125 个包、`node_modules` 206 MB）。

**影响**：内网服务器上要么装不了前端依赖，要么只能整个拷 `node_modules`（脏且易损坏）。
「任何项目断网也能构建和部署」这条铁律，在前端侧实际上是**没有落地路径**的。

**建议修法**：§6 增加一节「前端离线交付」，明确两条路并给出推荐：

| 方案 | 做法 | 适用 |
|---|---|---|
| **推荐：只交付构建产物** | 在开发机构建，产物输出到后端 `wwwroot`，内网服务器只需 ASP.NET/Nginx 提供静态资源 | 生产环境。**内网不需要 Node**，也天然符合「禁 Node 后端」 |
| 备选：npm 离线缓存 | 用干净缓存执行 `npm ci --cache <新目录>` 生成最小缓存（DeptPlan 实测 37 MB，远小于原始 180 MB 缓存），压缩后随包分发；内网配 `offline=true` 后 `npm ci --offline` | 需要在内网改前端时 |

要点（都是实测踩出来的）：
- 内网必须设 `offline=true`，否则 npm 每次先探测 registry，等超时才回落缓存，一次安装能白等几分钟；
- `registry` 建议指向不可路由地址（如 `http://127.0.0.1:9/`），这样万一 `offline` 被误关会立刻失败而不是挂住；
- npm 11 起默认拦截 install 脚本。esbuild 等平台二进制随包分发、不依赖 postinstall，
  但**装完必须实测一次**（如 `node -e "require('esbuild').transformSync('const a=1',{loader:'ts'})"`），
  不能只看安装成功；
- 构建产物**禁止引用任何 CDN**，全部本地打包，否则断网白屏。

**状态**：待修（属**次版本**级别 —— 新增章节）

---

## KI-007 `dotnet new` 默认生成的 `.slnx` 与内网工具链兼容性差

**问题**：.NET 10 的 `dotnet new sln` 默认生成 `.slnx`（新 XML 格式）。
内网的 Gitea 与较老版本的 Visual Studio 对它的支持不完整。

**影响**：低。表现为 CI 或 IDE 打不开解决方案，改回经典 `.sln` 即可。

**建议修法**：§7 或附录里注明「统一使用经典 `.sln`，不用 `.slnx`」，
并在模板中固定（`Aibp.Templates` 已按此处理）。

**状态**：待修（属**补丁**级别）

---

## 登记新问题的模板

复制下面这段到「状态汇总」表和正文各加一条即可：

```markdown
## KI-NNN 一句话标题
```

编号固定三位数字（KI-008、KI-009……），上面的 `KI-NNN` 只是占位符，
校验脚本按三位数字识别真实条目，所以占位符不会被误当成一条问题。

正文四段照抄这个结构：

**问题**：具体是什么，怎么发现的（最好带实测证据，别写"据说"）

**影响**：谁会踩到、踩到之后什么表现

**建议修法**：能直接照做的程度，最好给出改哪一节、改成什么

**状态**：待修 / 修复中 / 已修复（vX.Y.Z）
```

版本号级别（补丁 / 次版本 / 主版本）按 STD-AI-001 §12.1 的判定表确定，并写在状态里 ——
这样发版时不用再回头判断一次。
