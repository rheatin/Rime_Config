# ==============================================================================
# New-AppOptions.ps1
# 扫描「正在运行」与「已安装」的 Windows 程序，生成可粘贴进
# weasel.custom.yaml 的 app_options 英文条目。
#
# 背景：小狼毫 (Weasel) 的 app_options 只认 exe 文件名，而且**未列出的 App 才会**
# 回落到方案的 switches/@0/reset。当前 reset: 1 = 英文，所以「除聊天软件和浏览器
# 外一律英文」本来就能满足；本脚本用于把常用工具显式钉死成英文，避免以后改
# reset 时翻车，也方便排查某个 App 为什么没切对。
#
# 用法：
#   pwsh -File tools\New-AppOptions.ps1                 # 打印未收录的候选条目
#   pwsh -File tools\New-AppOptions.ps1 -RunningOnly    # 只看当前正在运行的程序
#   pwsh -File tools\New-AppOptions.ps1 -WriteTemplate  # 生成完整片段到 tools\app_options.generated.yaml
# ==============================================================================

[CmdletBinding()]
param(
    # 只扫描当前正在运行的进程（默认同时扫描已安装程序）
    [switch]$RunningOnly,
    # 直接输出一份完整 YAML 片段文件
    [switch]$WriteTemplate
)

$ErrorActionPreference = 'Stop'

$RepoRoot = Split-Path -Parent $PSScriptRoot
$WeaselCustom = Join-Path $RepoRoot 'weasel.custom.yaml'

# ── 1. 这些 exe 属于「自动中文」的聊天软件/浏览器，不要建议成英文 ──────────────
$ChineseAllowList = @(
    'wechat.exe', 'weixin.exe', 'wechatappex.exe', 'wxwork.exe', 'qq.exe',
    'telegram.exe', 'slack.exe', 'discord.exe', 'feishu.exe', 'lark.exe',
    'dingtalk.exe', 'whatsapp.exe', 'line.exe', 'teams.exe', 'ms-teams.exe',
    'chrome.exe', 'msedge.exe', 'firefox.exe', 'brave.exe', 'opera.exe',
    'vivaldi.exe', 'arc.exe', 'iexplore.exe'
)

# ── 2. 这些是系统组件/输入法自身，没必要写进配置 ──────────────────────────────
$SystemDenyList = @(
    'weaselserver.exe', 'weaseldeployer.exe', 'weaselsetup.exe',
    'textinputhost.exe', 'ctfmon.exe', 'rime.exe', 'rime.dll',
    'dwm.exe', 'winlogon.exe', 'csrss.exe', 'smss.exe', 'services.exe',
    'lsass.exe', 'svchost.exe', 'fontdrvhost.exe', 'sihost.exe',
    'taskhostw.exe', 'runtimebroker.exe', 'dllhost.exe', 'conhost.exe',
    'wmiprvse.exe', 'backgroundtaskhost.exe', 'startmenuexperiencehost.exe',
    'shellexperiencehost.exe', 'nvidia overlay.exe', 'nvcontainer.exe',
    'msmpeng.exe', 'securityhealthsystray.exe', 'searchindexer.exe',
    'systemsettings.exe'   # 保留在系统类，不主动建议
)

function Get-RunningAppNames {
    $names = New-Object System.Collections.Generic.HashSet[string]
    foreach ($p in Get-Process -ErrorAction SilentlyContinue) {
        try {
            $n = $p.ProcessName
            if ($n) { [void]$names.Add(($n.ToLower() + '.exe')) }
        } catch { }
    }
    return $names
}

function Get-InstalledAppNames {
    $names = New-Object System.Collections.Generic.HashSet[string]
    $roots = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )
    foreach ($root in $roots) {
        foreach ($item in (Get-ItemProperty $root -ErrorAction SilentlyContinue)) {
            $loc = $item.InstallLocation
            if (-not $loc -or -not (Test-Path $loc)) { continue }
            foreach ($exe in (Get-ChildItem -Path $loc -Filter '*.exe' -File -ErrorAction SilentlyContinue)) {
                [void]$names.Add($exe.Name.ToLower())
            }
        }
    }
    return $names
}

# ── 3. 读取现有 weasel.custom.yaml 里已经收录的 exe 名 ────────────────────────
$existing = New-Object System.Collections.Generic.HashSet[string]
if (Test-Path $WeaselCustom) {
    $inAppOptions = $false
    foreach ($line in (Get-Content $WeaselCustom -Encoding UTF8)) {
        if (-not $inAppOptions) {
            if ($line -match '^\s*app_options:\s*$') { $inAppOptions = $true }
            continue
        }
        # patch: 下 app_options 的条目缩进为 4 空格
        if ($line -match '^ {4}([^ #][^:]*):\s*$') {
            $name = $Matches[1].Trim().Trim('"').ToLower()
            if ($name) { [void]$existing.Add($name) }
        }
    }
}

Write-Host "已收录条目: $($existing.Count) 个 (来自 weasel.custom.yaml)" -ForegroundColor Cyan

# ── 4. 收集候选 ──────────────────────────────────────────────────────────────
$candidates = New-Object System.Collections.Generic.HashSet[string]
foreach ($n in (Get-RunningAppNames)) { [void]$candidates.Add($n) }
if (-not $RunningOnly) {
    Write-Host "正在扫描已安装程序（可能需要十几秒）..." -ForegroundColor DarkGray
    foreach ($n in (Get-InstalledAppNames)) { [void]$candidates.Add($n) }
}

$missing = @()
foreach ($c in $candidates) {
    if ($existing.Contains($c)) { continue }
    if ($ChineseAllowList -contains $c) { continue }
    if ($SystemDenyList -contains $c) { continue }
    if ($c -match '^(unins|setup|install|vc_redist|vcredist|update|crashpad|.*\.tmp)') { continue }
    $missing += $c
}
$missing = $missing | Sort-Object -Unique

# ── 5. 输出 ──────────────────────────────────────────────────────────────────
$header = @'
    # ─── 显式英文 (由 tools/New-AppOptions.ps1 生成，请人工筛除不需要的项) ───
'@

$body = foreach ($m in $missing) {
    if ($m -match '[\s:]') {
        "    `"$m`":`n      ascii_mode: true"
    } else {
        "    ${m}:`n      ascii_mode: true"
    }
}

if ($WriteTemplate) {
    $outFile = Join-Path $PSScriptRoot 'app_options.generated.yaml'
    ($header, ($body -join "`n")) -join "`n" | Set-Content -Path $outFile -Encoding UTF8
    Write-Host "已写出: $outFile ($($missing.Count) 条)" -ForegroundColor Green
} else {
    Write-Host ""
    Write-Host "未收录的候选程序 ($($missing.Count) 个)，可直接粘贴到 weasel.custom.yaml 的 app_options 下:" -ForegroundColor Yellow
    Write-Host $header -ForegroundColor DarkGray
    $body | ForEach-Object { Write-Host $_ }
    Write-Host ""
    Write-Host "提示: 未列出的 App 本来就会回落到 switches/@0/reset (当前 = 英文)，" -ForegroundColor DarkGray
    Write-Host "      所以只需要把真正在用的程序补进来即可。" -ForegroundColor DarkGray
}
