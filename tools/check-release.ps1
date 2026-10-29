<#
.SYNOPSIS
    发版前自动校验。一条命令跑完，全绿才提 PR。

.DESCRIPTION
    查四件事，都是靠人眼最容易漏的：

      1. 版本号三处一致 —— 文档头部「版本」字段 / 文档自己的变更记录表 / 根目录 CHANGELOG.md
      2. 章节交叉引用有效 —— 正文里写的 §N.M 在目标文档中真的存在
      3. 配套文档已登记 —— standards/ 下每份文档都在主文档里被提到过
      4. KNOWN-ISSUES 自洽 —— 状态汇总表的条目数与正文条目数一致

    用法（在仓库任意位置）：
        powershell -File tools\check-release.ps1

    退出码：0 = 全部通过，1 = 有问题。可以直接挂在 CI 上。

.NOTES
    兼容 Windows PowerShell 5.1（Server 自带），不依赖 PowerShell 7。
    本文件必须存成 UTF-8 with BOM —— PS 5.1 读无 BOM 脚本时按系统 ANSI 解码，
    中文注释里的多字节序列会吃掉后面的括号，报一堆指不到原因的语法错误。
#>

[CmdletBinding()]
param(
    # 仓库根目录。默认取本脚本所在目录的上一级。
    [string]$RepoRoot
)

$ErrorActionPreference = 'Stop'

try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch { }

if (-not $RepoRoot) {
    $RepoRoot = Split-Path -Parent $PSScriptRoot
}
if (-not (Test-Path -LiteralPath $RepoRoot)) {
    Write-Host ("仓库根目录不存在：{0}" -f $RepoRoot) -ForegroundColor Red
    exit 1
}

$standardsDir = Join-Path $RepoRoot 'standards'
$changelogPath = Join-Path $RepoRoot 'CHANGELOG.md'
$knownIssuesPath = Join-Path $RepoRoot 'KNOWN-ISSUES.md'

$errors = New-Object System.Collections.ArrayList
$warns = New-Object System.Collections.ArrayList
$passes = New-Object System.Collections.ArrayList

function Add-Pass { param([string]$m) [void]$passes.Add($m); Write-Host ("  [OK ] {0}" -f $m) -ForegroundColor Green }
function Add-Warn { param([string]$m) [void]$warns.Add($m); Write-Host ("  [!! ] {0}" -f $m) -ForegroundColor Yellow }
function Add-Err { param([string]$m) [void]$errors.Add($m); Write-Host ("  [ERR] {0}" -f $m) -ForegroundColor Red }

function Read-Text {
    param([string]$Path)
    # 显式指定 UTF8：仓库里的文档没有 BOM，PS 5.1 不指定就会按 ANSI 读成乱码
    return (Get-Content -LiteralPath $Path -Raw -Encoding UTF8)
}

Write-Host ''
Write-Host '================================================================' -ForegroundColor Cyan
Write-Host '  发版前校验' -ForegroundColor Cyan
Write-Host ("  仓库：{0}" -f $RepoRoot) -ForegroundColor DarkGray
Write-Host '================================================================' -ForegroundColor Cyan

# ==============================================================================
# 解析每份标准文档：版本号 + 章节号集合
# ==============================================================================

$docs = @{}
$mainDocId = $null

if (-not (Test-Path -LiteralPath $standardsDir)) {
    Write-Host ("找不到 standards 目录：{0}" -f $standardsDir) -ForegroundColor Red
    exit 1
}

foreach ($f in (Get-ChildItem -LiteralPath $standardsDir -Filter '*.md' -File)) {
    $text = Read-Text -Path $f.FullName

    # 文档编号，形如 STD-AI-001
    $docId = $null
    if ($text -match '(?m)^\|\s*文档编号\s*\|\s*(STD-[A-Z]+-\d+)') { $docId = $Matches[1] }

    # 头部「版本」字段，形如 | 版本 | v1.3（评审稿） |
    $headerVer = $null
    if ($text -match '(?m)^\|\s*版本\s*\|\s*(v\d+(?:\.\d+)*)') { $headerVer = $Matches[1] }

    # 变更记录表：抓所有形如 | v1.2 | 日期 | ... 的行，取最后一条（表格按时间升序）
    $changeRows = @()
    foreach ($m in [regex]::Matches($text, '(?m)^\|\s*(v\d+(?:\.\d+)*)\s*\|')) {
        $changeRows += $m.Groups[1].Value
    }
    $latestChangeVer = if ($changeRows.Count -gt 0) { $changeRows[$changeRows.Count - 1] } else { $null }

    # 章节号集合：## 12. xxx → 12 ；### 12.1 xxx → 12.1 ；## 附录 D xxx → 附录D
    $sections = New-Object System.Collections.Generic.HashSet[string]
    foreach ($m in [regex]::Matches($text, '(?m)^#{2,4}\s+(\d+(?:\.\d+)*)\.?\s')) {
        [void]$sections.Add($m.Groups[1].Value)
    }
    foreach ($m in [regex]::Matches($text, '(?m)^#{2,4}\s+附录\s*([A-Z])')) {
        [void]$sections.Add('附录' + $m.Groups[1].Value)
    }

    $docs[$f.Name] = [pscustomobject]@{
        File             = $f.FullName
        Name             = $f.Name
        DocId            = $docId
        HeaderVersion    = $headerVer
        LatestChangeVer  = $latestChangeVer
        ChangeRowCount   = $changeRows.Count
        Sections         = $sections
        Text             = $text
    }

    if ($docId -eq 'STD-AI-001') { $mainDocId = $f.Name }
}

if (-not $mainDocId) {
    Add-Err '未找到文档编号为 STD-AI-001 的主文档'
}

# 文档编号 → 文件名 的映射，供交叉引用解析用
$idToFile = @{}
foreach ($k in $docs.Keys) {
    if ($docs[$k].DocId) { $idToFile[$docs[$k].DocId] = $k }
}

Write-Host ''
Write-Host '── 已识别的标准文档 ──' -ForegroundColor Cyan
foreach ($k in ($docs.Keys | Sort-Object)) {
    $d = $docs[$k]
    Write-Host ("  {0,-10} {1,-26} 头部 {2,-8} 变更记录最新 {3}" -f `
        ($(if ($d.DocId) { $d.DocId } else { '(无编号)' })), $k, `
        ($(if ($d.HeaderVersion) { $d.HeaderVersion } else { '(缺失)' })), `
        ($(if ($d.LatestChangeVer) { $d.LatestChangeVer } else { '(无记录)' })))
}

# ==============================================================================
# 检查 1：版本号三处一致
# ==============================================================================

Write-Host ''
Write-Host '── 检查 1：版本号一致性 ──' -ForegroundColor Cyan

$changelogText = $null
$changelogVersions = @()
if (Test-Path -LiteralPath $changelogPath) {
    $changelogText = Read-Text -Path $changelogPath
    foreach ($m in [regex]::Matches($changelogText, '(?m)^##\s+(v\d+(?:\.\d+)*)')) {
        $changelogVersions += $m.Groups[1].Value
    }
    Add-Pass ("CHANGELOG.md 存在，含 {0} 个版本条目" -f $changelogVersions.Count)
}
else {
    Add-Err ("找不到 CHANGELOG.md：{0}" -f $changelogPath)
}

foreach ($k in ($docs.Keys | Sort-Object)) {
    $d = $docs[$k]

    if (-not $d.DocId) {
        Add-Warn ("{0} 头部表格缺少「文档编号」" -f $k)
    }
    if (-not $d.HeaderVersion) {
        Add-Err ("{0} 头部表格缺少「版本」字段，或格式不是 vX.Y[.Z]" -f $k)
        continue
    }
    if (-not $d.LatestChangeVer) {
        Add-Err ("{0} 找不到变更记录表（应有形如 | v1.0 | 日期 | 变更 | 作者 | 的行）" -f $k)
        continue
    }

    # 头部 vs 文档自己的变更记录
    if ($d.HeaderVersion -ne $d.LatestChangeVer) {
        Add-Err ("{0} 版本号不一致：头部 {1}，变更记录最新一行 {2} —— 发版时漏改了一处" -f `
            $k, $d.HeaderVersion, $d.LatestChangeVer)
    }
    else {
        Add-Pass ("{0} 头部与变更记录一致（{1}）" -f $k, $d.HeaderVersion)
    }

    # 该版本是否在 CHANGELOG 里有记录
    if ($changelogVersions.Count -gt 0) {
        # CHANGELOG 里的版本可能带补丁号（v1.2.1）而文档头部是两位（v1.2），
        # 所以按「前缀匹配」判断：CHANGELOG 有 v1.3 或 v1.3.x 都算覆盖到 v1.3
        $covered = $false
        foreach ($cv in $changelogVersions) {
            if ($cv -eq $d.HeaderVersion -or $cv.StartsWith($d.HeaderVersion + '.')) { $covered = $true; break }
        }
        if ($covered) {
            Add-Pass ("{0} 的 {1} 已在 CHANGELOG.md 记录" -f $k, $d.HeaderVersion)
        }
        else {
            Add-Err ("{0} 的 {1} 在 CHANGELOG.md 里找不到对应条目 —— 三处同步漏了第三处" -f $k, $d.HeaderVersion)
        }
    }
}

# ==============================================================================
# 检查 2：章节交叉引用有效性
# ==============================================================================

Write-Host ''
Write-Host '── 检查 2：章节交叉引用 ──' -ForegroundColor Cyan

# 非标准文档（README / CHANGELOG / KNOWN-ISSUES / tools）里的裸 §N.M 默认指向主文档
$otherFiles = @()
foreach ($n in @('README.md', 'CHANGELOG.md', 'KNOWN-ISSUES.md')) {
    $p = Join-Path $RepoRoot $n
    if (Test-Path -LiteralPath $p) { $otherFiles += [pscustomobject]@{ Name = $n; Path = $p } }
}

$refTotal = 0
$refBad = 0

function Test-RefsInFile {
    param(
        [string]$DisplayName,
        [string]$Text,
        [string]$DefaultTargetFile
    )

    $bad = 0
    $total = 0

    # 匹配 §N、§N.M、§N.M.K，以及紧邻其前的 STD-AI-00X 编号。
    #
    # 编号与 § 之间只允许最多 8 个非 § 字符。这个窗口长度是刻意收紧的：
    # 写成 {0,20} 时，正则的「最左匹配」会从 § 前面的括号或汉字开始试，
    # 此时 STD 编号落在窗口内却被跳过（可选分组匹配为空），
    # 于是 "（STD-AI-001 §13）" 被当成裸引用 §13、回落到「引用本文档」，报假错。
    # 窗口收到 8 之后，从括号起跳就够不到 §，引擎只能从 STD 处开始匹配，编号才被正确捕获。
    $pattern = '(?:(STD-[A-Z]+-\d+)[^\r\n§]{0,8}?)?§\s*(\d+(?:\.\d+)*)'
    foreach ($m in [regex]::Matches($Text, $pattern)) {
        $total++
        $refId = $m.Groups[1].Value
        $sec = $m.Groups[2].Value

        $targetFile = $DefaultTargetFile
        if ($refId) {
            if ($idToFile.ContainsKey($refId)) { $targetFile = $idToFile[$refId] }
            else {
                Write-Host ("  [ERR] {0}: 引用了不存在的文档编号 {1}" -f $DisplayName, $refId) -ForegroundColor Red
                $script:errors.Add(("{0}: 引用了不存在的文档编号 {1}" -f $DisplayName, $refId)) | Out-Null
                $bad++
                continue
            }
        }

        if (-not $targetFile -or -not $docs.ContainsKey($targetFile)) { continue }

        # 顶级章节号存在即可（引用 §12.1 时，只要有 12.1 或 12 都算命中）
        $target = $docs[$targetFile]
        if ($target.Sections.Contains($sec)) { continue }

        $parent = ($sec -split '\.')[0]
        if ($target.Sections.Contains($parent)) { continue }

        $lineNo = ($Text.Substring(0, $m.Index) -split "`n").Count
        Write-Host ("  [ERR] {0} 第 {1} 行: §{2} 在 {3} 中不存在" -f $DisplayName, $lineNo, $sec, $targetFile) -ForegroundColor Red
        $script:errors.Add(("{0} 第 {1} 行: §{2} 在 {3} 中不存在" -f $DisplayName, $lineNo, $sec, $targetFile)) | Out-Null
        $bad++
    }

    return [pscustomobject]@{ Total = $total; Bad = $bad }
}

if ($mainDocId) {
    foreach ($k in ($docs.Keys | Sort-Object)) {
        $r = Test-RefsInFile -DisplayName $k -Text $docs[$k].Text -DefaultTargetFile $k
        $refTotal += $r.Total; $refBad += $r.Bad
    }
    foreach ($f in $otherFiles) {
        $r = Test-RefsInFile -DisplayName $f.Name -Text (Read-Text -Path $f.Path) -DefaultTargetFile $mainDocId
        $refTotal += $r.Total; $refBad += $r.Bad
    }
}

if ($refBad -eq 0) {
    Add-Pass ("交叉引用全部有效（共检查 {0} 处 §引用）" -f $refTotal)
}
else {
    Write-Host ("  共 {0} 处引用，{1} 处失效" -f $refTotal, $refBad) -ForegroundColor Yellow
}

# ==============================================================================
# 检查 3：配套文档已登记
# ==============================================================================

Write-Host ''
Write-Host '── 检查 3：配套文档登记 ──' -ForegroundColor Cyan

if ($mainDocId) {
    $mainText = $docs[$mainDocId].Text
    foreach ($k in ($docs.Keys | Sort-Object)) {
        if ($k -eq $mainDocId) { continue }
        $d = $docs[$k]
        $byId = $d.DocId -and ($mainText -match [regex]::Escape($d.DocId))
        $byName = $mainText -match [regex]::Escape($k)

        if ($byId -or $byName) {
            Add-Pass ("{0} 已在主文档中登记（{1}）" -f $k, $(if ($byId) { $d.DocId } else { '按文件名' }))
        }
        else {
            Add-Err ("{0} 未在主文档 STD-AI-001 中被提及 —— 新增配套文档必须在主文档头部「配套文档」和正文中登记" -f $k)
        }
    }
}

# ==============================================================================
# 检查 4：KNOWN-ISSUES 自洽
# ==============================================================================

Write-Host ''
Write-Host '── 检查 4：已知问题登记 ──' -ForegroundColor Cyan

if (Test-Path -LiteralPath $knownIssuesPath) {
    $kiText = Read-Text -Path $knownIssuesPath

    # 汇总表里的编号（| KI-001 | ...）与正文条目标题（## KI-001 ...）
    # 编号固定三位数字：这样文档末尾「登记新问题的模板」里的占位符（KI-NNN）
    # 不会被当成真条目 —— 第一版这里写成 KI-\d+ 就把占位符误判成了一条真实问题。
    $tableIds = @()
    foreach ($m in [regex]::Matches($kiText, '(?m)^\|\s*(KI-\d{3})\s*\|')) { $tableIds += $m.Groups[1].Value }

    $bodyIds = @()
    foreach ($m in [regex]::Matches($kiText, '(?m)^##\s+(KI-\d{3})\b')) { $bodyIds += $m.Groups[1].Value }

    $tableUniq = $tableIds | Sort-Object -Unique
    $bodyUniq = $bodyIds | Sort-Object -Unique

    $onlyTable = @($tableUniq | Where-Object { $bodyUniq -notcontains $_ })
    $onlyBody = @($bodyUniq | Where-Object { $tableUniq -notcontains $_ })

    if ($onlyTable.Count -eq 0 -and $onlyBody.Count -eq 0) {
        Add-Pass ("KNOWN-ISSUES.md 自洽：汇总表 {0} 条，正文 {1} 条，一一对应" -f $tableUniq.Count, $bodyUniq.Count)
    }
    else {
        if ($onlyTable.Count -gt 0) { Add-Err ("KNOWN-ISSUES 汇总表里有但正文没有：{0}" -f ($onlyTable -join ', ')) }
        if ($onlyBody.Count -gt 0) { Add-Err ("KNOWN-ISSUES 正文里有但汇总表没有：{0}" -f ($onlyBody -join ', ')) }
    }

    # 状态用词规范化：只允许这几种，避免"待处理/待修/未修/TODO"混用
    $allowedStatus = @('待修', '修复中', '部分解决', '已修复')
    $badStatus = @()
    foreach ($m in [regex]::Matches($kiText, '(?m)^\|\s*KI-\d{3}\s*\|[^|]*\|[^|]*\|\s*([^|]+?)\s*\|')) {
        $st = $m.Groups[1].Value.Trim()
        if ($allowedStatus -notcontains $st) { $badStatus += $st }
    }
    if ($badStatus.Count -eq 0) {
        Add-Pass 'KNOWN-ISSUES 状态用词规范（待修 / 修复中 / 部分解决 / 已修复）'
    }
    else {
        Add-Warn ("KNOWN-ISSUES 里出现了非标准状态词：{0}（建议统一为：{1}）" -f (($badStatus | Sort-Object -Unique) -join ', '), ($allowedStatus -join ' / '))
    }
}
else {
    Add-Warn '未找到 KNOWN-ISSUES.md（§12.1 要求已知缺陷登记在此，建议补上）'
}

# ==============================================================================
# 汇总
# ==============================================================================

Write-Host ''
Write-Host '================================================================' -ForegroundColor Cyan
Write-Host ("  通过 {0}    警告 {1}    错误 {2}" -f $passes.Count, $warns.Count, $errors.Count) -ForegroundColor White
Write-Host '================================================================' -ForegroundColor Cyan

if ($errors.Count -gt 0) {
    Write-Host ''
    Write-Host '  有错误，不要提 PR。按上面红色条目逐条修完再跑一次。' -ForegroundColor Red
    Write-Host ''
    exit 1
}
elseif ($warns.Count -gt 0) {
    Write-Host ''
    Write-Host '  无错误，有警告。确认每条是否可接受后再提 PR。' -ForegroundColor Yellow
    Write-Host ''
    exit 0
}
else {
    Write-Host ''
    Write-Host '  全部通过，可以提 PR。' -ForegroundColor Green
    Write-Host '  合并后记得打 tag：git tag std-ai-001-vX.Y.Z ；git push --tags' -ForegroundColor DarkGray
    Write-Host ''
    exit 0
}
