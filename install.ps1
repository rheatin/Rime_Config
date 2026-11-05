# ==============================================================================
# Rime 自动配置与安装脚本 (Windows / 白霜拼音 + 万象语言模型 + MoeType)
# Repository: https://github.com/rheatin/Rime_Config.git
# ==============================================================================

$ErrorActionPreference = "Continue"

Write-Host "====================================================" -ForegroundColor Cyan
Write-Host " 🚀 开始配置 Rime 白霜拼音 + 万象语言模型 (Windows) " -ForegroundColor Green
Write-Host "====================================================" -ForegroundColor Cyan

# 彻底终止可能卡在维护中的旧后台进程
Write-Host "🧹 正在清理可能卡住的旧输入法进程..." -ForegroundColor Cyan
Stop-Process -Name "WeaselDeployer" -Force -ErrorAction SilentlyContinue
Stop-Process -Name "WeaselServer" -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 1

$RimeDir = Join-Path $env:APPDATA "Rime"
$PermanentConfigDir = Join-Path $env:USERPROFILE "Rime_Config"

$PSScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$RepoUrl = if ($env:RIME_REPO_URL) { $env:RIME_REPO_URL } else { "" }
if (-not $RepoUrl -and $PSScriptDir -and (Test-Path (Join-Path $PSScriptDir ".git"))) {
    $Detected = (& git -C $PSScriptDir remote get-url origin 2>$null)
    if ($Detected) { $RepoUrl = $Detected.Trim() }
}
if (-not $RepoUrl) { $RepoUrl = "https://github.com/rheatin/Rime_Config.git" }
$RepoZipUrl = $RepoUrl -replace "\.git$", "/archive/refs/heads/main.zip"
$RimeFrostUrl = "https://github.com/gaboolic/rime-frost.git"
$RimeFrostZipUrl = "https://github.com/gaboolic/rime-frost/archive/refs/heads/main.zip"

$WanxiangApiUrl = "https://api.github.com/repos/amzxyz/rime-wanxiang-data/releases/tags/LTS"
$WanxiangModelUrl = "https://github.com/amzxyz/rime-wanxiang-data/releases/download/LTS/wanxiang-lts-zh-hans.gram"
$FallbackWanxiangSha256 = "1635588006D79CC6955FBCF3D8DE12822A36856EB5408735A8B4A2952B16CADF"

$MoeTypeApiUrl = "https://api.github.com/repos/suiginko/moetype/releases/latest"
$MoeTypeReleaseUrl = "https://github.com/suiginko/moetype/releases/latest/download/toneless_moe.dict.yaml"
$FallbackMoeSha256 = "BBF8FB188A88D84310457F65F3C2EBCEC692C5371087A1F6589EAB8B923C08AF"

function Download-And-Extract-Zip {
    param([string]$Url, [string]$DestDir)
    $ZipFile = Join-Path $env:TEMP "$([System.Guid]::NewGuid()).zip"
    $ExtractTemp = Join-Path $env:TEMP "$([System.Guid]::NewGuid())"
    Write-Host "🌐 正在下载: $Url" -ForegroundColor Cyan
    Invoke-WebRequest -Uri $Url -OutFile $ZipFile
    Expand-Archive -Path $ZipFile -DestinationPath $ExtractTemp -Force
    $InnerFolder = Get-ChildItem -Path $ExtractTemp -Directory | Select-Object -First 1
    if (-not (Test-Path $DestDir)) {
        New-Item -ItemType Directory -Path $DestDir -Force | Out-Null
    }
    Copy-Item -Path (Join-Path $InnerFolder.FullName "*") -Destination $DestDir -Recurse -Force
    Remove-Item -Path $ZipFile -Force -ErrorAction SilentlyContinue
    Remove-Item -Path $ExtractTemp -Recurse -Force -ErrorAction SilentlyContinue
}

# 1. 准备/更新永久个人配置仓库
Write-Host "📥 正在同步 Rime_Config 仓库资源..." -ForegroundColor Cyan
if (-not (Test-Path $PermanentConfigDir)) {
    if (Get-Command git -ErrorAction SilentlyContinue) {
        git clone $RepoUrl $PermanentConfigDir 2>$null
    } else {
        Download-And-Extract-Zip -Url $RepoZipUrl -DestDir $PermanentConfigDir
    }
} else {
    if (Test-Path (Join-Path $PermanentConfigDir ".git")) {
        Push-Location $PermanentConfigDir
        try { git pull --rebase origin main 2>$null } catch {}
        Pop-Location
    }
}

# 统一资源源目录
$SourceDir = $PermanentConfigDir

# 2. 检测与安装 Weasel (小狼毫)
$WeaselDir = "${env:ProgramFiles(x86)}\Rime\weasel-*"
$WeaselInstalled = (Test-Path $WeaselDir) -or (Test-Path "${env:ProgramFiles}\Rime\weasel-*")

if (-not $WeaselInstalled) {
    Write-Host "🔍 未检测到小狼毫 (Weasel)，正在尝试自动安装..." -ForegroundColor Yellow
    if (Get-Command winget -ErrorAction SilentlyContinue) {
        Write-Host "📦 使用 winget 安装 Weasel..." -ForegroundColor Cyan
        winget install --id Rime.Weasel -e --accept-package-agreements --accept-source-agreements
    } else {
        Write-Host "🌐 正在下载 Weasel 安装包..." -ForegroundColor Cyan
        $InstallerUrl = "https://github.com/rime/weasel/releases/latest/download/weasel-setup.exe"
        $InstallerPath = Join-Path $env:TEMP "weasel-setup.exe"
        Invoke-WebRequest -Uri $InstallerUrl -OutFile $InstallerPath
        Write-Host "📦 启动安装程序 (请在弹窗中完成安装)..." -ForegroundColor Cyan
        Start-Process -FilePath $InstallerPath -Wait
    }
} else {
    Write-Host "✅ 检测到已安装小狼毫 (Weasel)" -ForegroundColor Green
}

# 2.1 交互式个性化向导 (底座方案 / 输入模式 / 大模型 / 词库)
$Framework = "rime-frost"
$CustomRepo = ""
$Schema = "rime_frost"
$Model = "wanxiang_lts"
$EnableMoe = $true
$EnableCells = $true

if ($Host.UI.RawUI -and [Environment]::UserInteractive) {
    Write-Host "`n====================================================" -ForegroundColor Cyan
    Write-Host "🛠️  Rime Windows 个性化配置向导 (直接回车默认采用推荐项)" -ForegroundColor Yellow
    Write-Host "====================================================" -ForegroundColor Cyan

    Write-Host "`n【第 1 步】请选择输入法方案底座 (Base Framework):" -ForegroundColor Cyan
    Write-Host "  1. 白霜拼音 (rime-frost) [推荐] - 词库全面、内置拆字反查、多模式支持" -ForegroundColor Green
    Write-Host "  2. 雾凇拼音 (rime-ice) - 自然语言语料切分、极简清爽经典方案"
    Write-Host "  3. 自定义外部方案 (输入 GitHub 用户名/仓库名，自动校验并拉取)"
    $fwChoice = Read-Host "👉 请选择 [1-3, 默认 1]"
    if ($fwChoice -eq "2") {
        $Framework = "rime-ice"
        $Schema = "rime_ice"
    } elseif ($fwChoice -eq "3") {
        while ($true) {
            $userRepo = Read-Host "👉 请输入 GitHub 方案仓库 (格式 owner/repo，例如 iDvel/rime-ice)"
            if ($userRepo) {
                try {
                    $test = Invoke-RestMethod -Uri "https://api.github.com/repos/$userRepo" -TimeoutSec 5 -Headers @{"User-Agent"="Mozilla/5.0"}
                    Write-Host "   ✅ 验证通过！成功连接到该 GitHub 方案库。" -ForegroundColor Green
                    $Framework = "custom"
                    $CustomRepo = "https://github.com/$userRepo.git"
                    break
                } catch {
                    Write-Host "   ❌ 未能找到该仓库或无访问权限，请核对后重新输入！" -ForegroundColor Red
                }
            }
        }
    }

    if ($Framework -eq "rime-frost") {
        Write-Host "`n【第 2 步】请选择主输入模式 (Input Mode):" -ForegroundColor Cyan
        Write-Host "  1. 经典全拼 (Standard Pinyin) [推荐]" -ForegroundColor Green
        Write-Host "  2. 小鹤双拼 (Double Pinyin - Flypy)"
        Write-Host "  3. 自然码双拼 (Double Pinyin - Zrm)"
        Write-Host "  4. 微软双拼 (Double Pinyin - MSPY)"
        Write-Host "  5. 五笔 86 (Wubi 86)"
        $scChoice = Read-Host "👉 请选择 [1-5, 默认 1]"
        switch ($scChoice) {
            "2" { $Schema = "rime_frost_double_pinyin_flypy" }
            "3" { $Schema = "rime_frost_double_pinyin" }
            "4" { $Schema = "rime_frost_double_pinyin_mspy" }
            "5" { $Schema = "rime_frost_wubi86" }
            Default { $Schema = "rime_frost" }
        }
    }

    Write-Host "`n【第 3 步】请选择 AI 语法语言模型 (Grammar Model):" -ForegroundColor Cyan
    Write-Host "  1. 万象 LTS 400MB 语法模型 [推荐] - 大幅跃升长句整句命中率" -ForegroundColor Green
    Write-Host "  2. 跳过安装 (轻量纯净模式) - 零额外下载，极度节省 400MB 内存"
    $modChoice = Read-Host "👉 请选择 [1-2, 默认 1]"
    if ($modChoice -eq "2") { $Model = "none" } else { $Model = "wanxiang_lts" }

    Write-Host "`n【第 4 步】请选择要挂载的扩展词库 (支持多选，输入编号如 1 2):" -ForegroundColor Cyan
    Write-Host "  1. MoeType 萌娘百科 (17.5 万二次元、ACG 与流行热词)"
    Write-Host "  2. 专业细胞词库 (涵盖计算机、医学、理化、地理历史等 20+ 领域)"
    Write-Host "  3. 全部跳过 (仅保留基础核心字词库)"
    $dictChoice = Read-Host "👉 请输入编号 [例如 1 2，直接回车默认 1 2]"
    if (-not $dictChoice) { $dictChoice = "1 2" }
    if ($dictChoice -match "3") {
        $EnableMoe = $false
        $EnableCells = $false
    } else {
        $EnableMoe = ($dictChoice -match "1")
        $EnableCells = ($dictChoice -match "2")
    }

    Write-Host "`n✅ 向导完成！正在为您自动组装方案与词库..." -ForegroundColor Green
    Write-Host "====================================================`n" -ForegroundColor Cyan
}

$ProfileLines = @(
    "RIME_FRAMEWORK=`"$Framework`"",
    "RIME_CUSTOM_REPO=`"$CustomRepo`"",
    "RIME_SCHEMA=`"$Schema`"",
    "RIME_MODEL=`"$Model`"",
    "RIME_CUSTOM_MODEL_URL=`"`"",
    "RIME_ENABLE_MOE=$($EnableMoe.ToString().ToLower())",
    "RIME_ENABLE_CELLS=$($EnableCells.ToString().ToLower())",
    "RIME_ENABLE_TENCENT=false",
    "RIME_CUSTOM_DICT_URL=`"`""
)
Set-Content -Path (Join-Path $PermanentConfigDir ".rime_profile") -Value $ProfileLines -Encoding UTF8
Set-Content -Path (Join-Path $RimeDir ".rime_profile") -Value $ProfileLines -Encoding UTF8

if (Get-Command python -ErrorAction SilentlyContinue) {
    & python (Join-Path $PermanentConfigDir "tools\rime_generator.py") 2>$null
}

# 3. 拉取/同步 方案底座
$TargetFwUrl = $RimeFrostUrl
$TargetZipUrl = $RimeFrostZipUrl
if ($Framework -eq "rime-ice") {
    $TargetFwUrl = "https://github.com/iDvel/rime-ice.git"
    $TargetZipUrl = "https://github.com/iDvel/rime-ice/archive/refs/heads/main.zip"
    Write-Host "❄️  正在同步 雾凇拼音 (rime-ice) 词库底座..." -ForegroundColor Cyan
} elseif ($Framework -eq "custom" -and $CustomRepo) {
    $TargetFwUrl = $CustomRepo
    $TargetZipUrl = $CustomRepo -replace "\.git$", "/archive/refs/heads/main.zip"
    Write-Host "📦 正在同步 自定义方案底座 ($CustomRepo)..." -ForegroundColor Cyan
} else {
    Write-Host "❄️  正在同步 白霜拼音 (rime-frost) 官方词库..." -ForegroundColor Cyan
}

if (-not (Test-Path $RimeDir)) {
    New-Item -ItemType Directory -Path $RimeDir -Force | Out-Null
}

$TempFrost = Join-Path $env:TEMP "rime_fw_temp"
if (Test-Path $TempFrost) { Remove-Item -Recurse -Force $TempFrost }

if (Get-Command git -ErrorAction SilentlyContinue) {
    git clone --depth=1 $TargetFwUrl $TempFrost 2>$null
    Copy-Item -Path (Join-Path $TempFrost "*") -Destination $RimeDir -Recurse -Force
    if (Test-Path (Join-Path $TempFrost ".git")) {
        Copy-Item -Path (Join-Path $TempFrost ".git") -Destination $RimeDir -Recurse -Force
    }
} else {
    Download-And-Extract-Zip -Url $TargetZipUrl -DestDir $RimeDir
}
if (Test-Path $TempFrost) { Remove-Item -Recurse -Force $TempFrost -ErrorAction SilentlyContinue }
Write-Host "✅ 方案底座词库同步完成！" -ForegroundColor Green

# 4. 动态获取 GitHub 远程 Digest SHA256 并校验下载万象语言模型 (若用户启用)
$ModelTarget = Join-Path $RimeDir "wanxiang-lts-zh-hans.gram"
if ($Model -eq "wanxiang_lts") {
Write-Host "🌐 正在查询万象模型 GitHub 远程 Digest SHA256..." -ForegroundColor Cyan

$RemoteWanxiangSha256 = $null
try {
    $ReleaseJson = Invoke-RestMethod -Uri $WanxiangApiUrl -Headers @{"User-Agent"="Mozilla/5.0"} -TimeoutSec 8
    $Asset = $ReleaseJson.assets | Where-Object { $_.name -eq "wanxiang-lts-zh-hans.gram" }
    if ($Asset -and $Asset.digest -and $Asset.digest.StartsWith("sha256:")) {
        $RemoteWanxiangSha256 = $Asset.digest.Substring(7).ToUpper()
    }
} catch {}

if (-not $RemoteWanxiangSha256) {
    $RemoteWanxiangSha256 = $FallbackWanxiangSha256
    Write-Host "ℹ️ 使用内置基准 SHA256: $($RemoteWanxiangSha256.Substring(0, 16))..." -ForegroundColor Yellow
} else {
    Write-Host "✅ 获取到远程万象模型 SHA256: $($RemoteWanxiangSha256.Substring(0, 16))..." -ForegroundColor Green
}

$ModelOk = $false
if (Test-Path $ModelTarget) {
    $CurrentHash = (Get-FileHash -Path $ModelTarget -Algorithm SHA256).Hash
    if ($CurrentHash -eq $RemoteWanxiangSha256) {
        Write-Host "✅ 本地万象模型与 GitHub 远程 Digest 一致，跳过下载！" -ForegroundColor Green
        $ModelOk = $true
    } else {
        Write-Host "⚠️ 本地万象模型不一致或有更新，准备拉取最新版本..." -ForegroundColor Yellow
    }
}

if (-not $ModelOk) {
    Write-Host "🧠 正在下载万象 (Wanxiang) LTS 语言模型 (~400MB)..." -ForegroundColor Cyan
    try {
        $ModelTemp = Join-Path $env:TEMP "wanxiang-lts-zh-hans.gram.tmp"
        Invoke-WebRequest -Uri $WanxiangModelUrl -OutFile $ModelTemp
        $DownloadHash = (Get-FileHash -Path $ModelTemp -Algorithm SHA256).Hash
        if ($DownloadHash -ne $RemoteWanxiangSha256) {
            Write-Host "❌ 下载的文件与 GitHub 官方 SHA256 不匹配！" -ForegroundColor Red
            Remove-Item -Path $ModelTemp -Force -ErrorAction SilentlyContinue
        } else {
            Move-Item -Path $ModelTemp -Destination $ModelTarget -Force
            Write-Host "✅ 万象语言模型下载且 SHA256 校验通过！" -ForegroundColor Green
        }
    } catch {
        Write-Host "⚠️ 万象语言模型下载失败: $_" -ForegroundColor Yellow
    }
}
} else {
    Write-Host "ℹ️ 用户跳过万象 AI 语法模型 (保持纯本地词典匹配，零额外内存占用)" -ForegroundColor Green
    if (Test-Path $ModelTarget) { Remove-Item -Path $ModelTarget -Force -ErrorAction SilentlyContinue }
}

# 5. 动态获取 MoeType 远程 Digest 并智能比对跳过/下载去重 (若用户启用)
$TargetMoe = Join-Path $RimeDir "moe.dict.yaml"
$MoeDigestFile = Join-Path $RimeDir ".moe_digest"
if ($EnableMoe) {
Write-Host "🌸 正在查询 MoeType 词库 GitHub 远程 Digest SHA256..." -ForegroundColor Cyan

$RemoteMoeSha256 = $null
try {
    $MoeJson = Invoke-RestMethod -Uri $MoeTypeApiUrl -Headers @{"User-Agent"="Mozilla/5.0"} -TimeoutSec 8
    $MoeAsset = $MoeJson.assets | Where-Object { $_.name -eq "toneless_moe.dict.yaml" }
    if ($MoeAsset -and $MoeAsset.digest -and $MoeAsset.digest.StartsWith("sha256:")) {
        $RemoteMoeSha256 = $MoeAsset.digest.Substring(7).ToUpper()
    }
} catch {}

if (-not $RemoteMoeSha256) {
    $RemoteMoeSha256 = $FallbackMoeSha256
}

$MoeNeedUpdate = $true
if ((Test-Path $TargetMoe) -and (Test-Path $MoeDigestFile)) {
    $SavedDigest = (Get-Content $MoeDigestFile -ErrorAction SilentlyContinue).Trim()
    if ($SavedDigest -eq $RemoteMoeSha256) {
        Write-Host "✅ 本地 MoeType 词库与 GitHub 远程最新 Digest 一致，跳过下载与去重！" -ForegroundColor Green
        $MoeNeedUpdate = $false
    }
}

if ($MoeNeedUpdate) {
    Write-Host "🌸 正在获取 MoeType 最新词库并进行动态去重..." -ForegroundColor Cyan
    $RawMoeTemp = Join-Path $env:TEMP "toneless_moe_raw.dict.yaml"
    try {
        Invoke-WebRequest -Uri $MoeTypeReleaseUrl -OutFile $RawMoeTemp
        if (Test-Path $RawMoeTemp) {
            Move-Item -Path $RawMoeTemp -Destination $TargetMoe -Force
            if ($RemoteMoeSha256) { Set-Content -Path $MoeDigestFile -Value $RemoteMoeSha256 -Encoding ASCII }
            Write-Host "✅ MoeType 词库更新完成！" -ForegroundColor Green
        }
    } catch {
        Write-Host "⚠️ MoeType 下载受阻，跳过扩展词库。" -ForegroundColor Yellow
    }
}
} else {
    Write-Host "ℹ️ 用户跳过 MoeType 萌娘百科词库挂载" -ForegroundColor Green
    if (Test-Path $TargetMoe) { Remove-Item -Path $TargetMoe -Force -ErrorAction SilentlyContinue }
    if (Test-Path $MoeDigestFile) { Remove-Item -Path $MoeDigestFile -Force -ErrorAction SilentlyContinue }
}
    $RawMoeTemp = Join-Path $env:TEMP "toneless_moe_raw.dict.yaml"
    try {
        Invoke-WebRequest -Uri $MoeTypeReleaseUrl -OutFile $RawMoeTemp
        
        $RimeWords = [System.Collections.Generic.HashSet[string]]::new()
        $CnDictsDir = Join-Path $RimeDir "cn_dicts"
        if (Test-Path $CnDictsDir) {
            Get-ChildItem -Path $CnDictsDir -Recurse -Include "*.dict.yaml", "*.txt" | ForEach-Object {
                $inBody = $false
                foreach ($line in [System.IO.File]::ReadLines($_.FullName)) {
                    $trimmed = $line.Trim()
                    if ($trimmed -eq '...') { $inBody = $true; continue }
                    if (-not $inBody -or [string]::IsNullOrWhiteSpace($trimmed) -or $trimmed.StartsWith('#')) { continue }
                    $p = $trimmed.Split("`t")
                    if ($p.Length -ge 1 -and $p[0].Trim()) {
                        [void]$RimeWords.Add($p[0].Trim())
                    }
                }
            }
        }
        
        $Writer = [System.IO.StreamWriter]::new($TargetMoe, $false, [System.Text.Encoding]::UTF8)
        $inBody = $false
        $kept = 0
        $removed = 0
        
        foreach ($line in [System.IO.File]::ReadLines($RawMoeTemp)) {
            $trimmed = $line.Trim()
            if ($trimmed -eq '...') { $inBody = $true; $Writer.WriteLine($line); continue }
            if (-not $inBody) { $Writer.WriteLine($line); continue }
            if ([string]::IsNullOrWhiteSpace($trimmed) -or $trimmed.StartsWith('#')) { $Writer.WriteLine($line); continue }
            
            $p = $trimmed.Split("`t")
            $w = $p[0].Trim()
            if ($RimeWords.Contains($w)) {
                $removed++
            } else {
                $kept++
                $Writer.WriteLine($line)
            }
        }
        $Writer.Close()
        Remove-Item -Path $RawMoeTemp -Force -ErrorAction SilentlyContinue
        Set-Content -Path $MoeDigestFile -Value $RemoteMoeSha256 -Encoding ASCII
        Write-Host "   去重完成：保留独有词条 $kept，剔除重复词条 $removed" -ForegroundColor Green
    } catch {
        Write-Host "⚠️ MoeType 处理跳过: $_" -ForegroundColor Yellow
    }
}

# 6. 复制个人自定义配置与聚合词库定义
Write-Host "⚙️  正在应用个人配置与 Rheatin Solarized 皮肤..." -ForegroundColor Cyan

# 复制所有 custom.yaml（包括 weasel.custom.yaml、rime_frost.custom.yaml 等）
Get-ChildItem -Path $SourceDir -Filter "*.custom.yaml" -File -ErrorAction SilentlyContinue | Copy-Item -Destination $RimeDir -Force

# 复制所有 dict.yaml 词库
Get-ChildItem -Path $SourceDir -Filter "*.dict.yaml" -File -ErrorAction SilentlyContinue | Copy-Item -Destination $RimeDir -Force

# 复制特定 yaml 与 txt 文件
@("symbols_v.yaml", "snippets.yaml", "snippets.custom.example.yaml", "weasel.custom.yaml") | ForEach-Object {
    $targetFile = Join-Path $SourceDir $_
    if (Test-Path $targetFile) {
        Copy-Item -Path $targetFile -Destination $RimeDir -Force
    }
}

$CustomSnippets = Join-Path $SourceDir "snippets.custom.yaml"
if (Test-Path $CustomSnippets) {
    Copy-Item -Path $CustomSnippets -Destination (Join-Path $RimeDir "snippets.custom.yaml") -Force
} elseif (Test-Path (Join-Path $SourceDir "snippets.custom.example.yaml")) {
    Copy-Item -Path (Join-Path $SourceDir "snippets.custom.example.yaml") -Destination (Join-Path $RimeDir "snippets.custom.yaml") -Force
}

# 复制自定义短语 (优先使用个人短语，其次使用公开示例短语)
$PhraseFile = Join-Path $SourceDir "custom_phrase.txt"
if (-not (Test-Path $PhraseFile)) { $PhraseFile = Join-Path $SourceDir "custom_phrase.example.txt" }
if (Test-Path $PhraseFile) {
    Copy-Item -Path $PhraseFile -Destination (Join-Path $RimeDir "custom_phrase.txt") -Force
}

# 复制 Lua 插件目录
$RepoLua = Join-Path $SourceDir "lua"
if (Test-Path $RepoLua) {
    $DstLua = Join-Path $RimeDir "lua"
    if (-not (Test-Path $DstLua)) { New-Item -ItemType Directory -Path $DstLua -Force | Out-Null }
    Copy-Item -Path (Join-Path $RepoLua "*") -Destination $DstLua -Recurse -Force
}
Write-Host "✅ 个人配置应用成功！" -ForegroundColor Green

# 7. 导入跨平台历史词频快照
if (Test-Path (Join-Path $SourceDir "sync")) {
    Write-Host "🧠 正在导入跨平台自造词与历史词频..." -ForegroundColor Cyan
    $TargetSync = Join-Path $RimeDir "sync"
    if (-not (Test-Path $TargetSync)) { New-Item -ItemType Directory -Path $TargetSync -Force | Out-Null }
    Copy-Item -Path (Join-Path $SourceDir "sync\*") -Destination $TargetSync -Recurse -Force
    Write-Host "✅ 跨平台词频快照就绪！" -ForegroundColor Green
}

# 8. 安装思源宋体与 Symbols Nerd Font 字体 (若已安装则跳过)
$FontsSource = Join-Path $SourceDir "fonts"
if (Test-Path $FontsSource) {
    $UserFontsDir = Join-Path $env:LOCALAPPDATA "Microsoft\Windows\Fonts"
    $SystemFontsDir = Join-Path $env:WINDIR "Fonts"
    
    $AllInstalled = $true
    Get-ChildItem -Path $FontsSource -File | ForEach-Object {
        $InstalledInUser = Test-Path (Join-Path $UserFontsDir $_.Name)
        $InstalledInSys = Test-Path (Join-Path $SystemFontsDir $_.Name)
        if (-not ($InstalledInUser -or $InstalledInSys)) {
            $AllInstalled = $false
        }
    }

    if ($AllInstalled) {
        Write-Host "✅ 检测到思源宋体与 Symbols Nerd Font 已安装，自动跳过安装流程！" -ForegroundColor Green
    } else {
        Write-Host "🔤 正在安装并注册思源宋体与 Symbols Nerd Font..." -ForegroundColor Cyan
        if (-not (Test-Path $UserFontsDir)) { New-Item -ItemType Directory -Path $UserFontsDir -Force | Out-Null }
        
        $RegKeyPath = "HKCU:\Software\Microsoft\Windows NT\CurrentVersion\Fonts"
        
        $TypeDefinition = @"
        using System;
        using System.Runtime.InteropServices;
        public class FontHelper {
            [DllImport("gdi32.dll", EntryPoint = "AddFontResourceW", SetLastError = true)]
            public static extern int AddFontResource([In, MarshalAs(UnmanagedType.LPWStr)] string lpFileName);
            [DllImport("user32.dll")]
            public static extern int SendMessage(IntPtr hWnd, uint Msg, IntPtr wParam, IntPtr lParam);
        }
"@
        if (-not ([System.Management.Automation.PSTypeName]'FontHelper').Type) {
            Add-Type -TypeDefinition $TypeDefinition -ErrorAction SilentlyContinue
        }

        try {
            $ShellApp = New-Object -ComObject Shell.Application
            $FontsFolder = $ShellApp.Namespace(0x14)
            Get-ChildItem -Path $FontsSource -File | ForEach-Object {
                $TargetSystemFont = Join-Path $SystemFontsDir $_.Name
                if (-not (Test-Path $TargetSystemFont)) {
                    $FontsFolder.CopyHere($_.FullName, 16)
                }
            }
        } catch {}

        Get-ChildItem -Path $FontsSource -File | ForEach-Object {
            $FontName = $_.Name
            $DestPath = Join-Path $UserFontsDir $FontName
            
            if (-not (Test-Path $DestPath)) {
                try {
                    Copy-Item -Path $_.FullName -Destination $DestPath -Force -ErrorAction Stop
                } catch {}
            }
            
            $Aliases = @(
                "$($_.BaseName) (TrueType)",
                "$($_.BaseName) (OpenType)",
                "Source Han Serif SC Heavy (OpenType)",
                "Source Han Serif TC Heavy (OpenType)",
                "思源宋体 Heavy (OpenType)",
                "Symbols Nerd Font Mono (TrueType)",
                "Symbols Nerd Font (TrueType)"
            )
            foreach ($alias in $Aliases) {
                Set-ItemProperty -Path $RegKeyPath -Name $alias -Value $DestPath -Force -ErrorAction SilentlyContinue
            }
            
            try { [FontHelper]::AddFontResource($DestPath) | Out-Null } catch {}
        }
        try { [FontHelper]::SendMessage([IntPtr]0xffff, 0x001D, [IntPtr]::Zero, [IntPtr]::Zero) | Out-Null } catch {}
        Write-Host "✅ 字体安装与即时注册完成！" -ForegroundColor Green
    }
}

# 9. 配置 Windows 用户资料同步自动 Push 守护服务 (纯静默无黑框弹窗)
Write-Host "⚡ 配置 Windows 用户资料同步自动 Push 守护服务 (纯静默无黑框弹窗)..." -ForegroundColor Cyan
$StartupFolder = [Environment]::GetFolderPath("Startup")
$OldStartupVbs = Join-Path $StartupFolder "RimeSyncWatcher.vbs"
$WatcherScriptPath = Join-Path $PermanentConfigDir "sync_watcher.ps1"

# 仅在源目录与永久配置目录不同时才执行复制，避免覆盖自身的报错
if ($SourceDir -ne $PermanentConfigDir) {
    if (Test-Path (Join-Path $SourceDir "sync.ps1")) {
        Copy-Item -Path (Join-Path $SourceDir "sync.ps1") -Destination $PermanentConfigDir -Force
    }
    if (Test-Path (Join-Path $SourceDir "sync_watcher.ps1")) {
        Copy-Item -Path (Join-Path $SourceDir "sync_watcher.ps1") -Destination $PermanentConfigDir -Force
    }
}

# 彻底清理旧的直接放在 Startup 目录的 vbs，防止资源管理器关联 cscript.exe 产生黑框
if (Test-Path $OldStartupVbs) { Remove-Item -Path $OldStartupVbs -Force -ErrorAction SilentlyContinue }

$SilentVbsPath = Join-Path $RimeDir "RimeSyncWatcher.vbs"
$PsExe = if (Get-Command pwsh -ErrorAction SilentlyContinue) { "pwsh.exe" } else { "powershell.exe" }
$VbsContent = "CreateObject(`"Wscript.Shell`").Run `"$PsExe -NoProfile -NonInteractive -NoLogo -ExecutionPolicy Bypass -WindowStyle Hidden -File `"`"$WatcherScriptPath`"`"`", 0, False"
Set-Content -Path $SilentVbsPath -Value $VbsContent -Encoding ASCII

# 注册计划任务 (开机登录时运行 wscript.exe //b //nologo，彻底杜绝控制台黑框)
$SchTaskCmd = "wscript.exe //b //nologo `"$SilentVbsPath`""
schtasks /create /tn "RimeSyncWatcher" /tr "$SchTaskCmd" /sc onlogon /f 2>$null | Out-Null

if ($LASTEXITCODE -ne 0) {
    $WshShell = New-Object -ComObject WScript.Shell
    $Shortcut = $WshShell.CreateShortcut((Join-Path $StartupFolder "RimeSyncWatcher.lnk"))
    $Shortcut.TargetPath = "wscript.exe"
    $Shortcut.Arguments = "//b //nologo `"$SilentVbsPath`""
    $Shortcut.WindowStyle = 7
    $Shortcut.Save()
}

Start-Process "wscript.exe" -ArgumentList "//b //nologo `"$SilentVbsPath`""
Write-Host "✅ 自动同步监听守护进程已激活（纯后台静默运行，无黑框弹窗）！" -ForegroundColor Green

# 9.1 调用平台专一化瘦身清理，移除所有冗余与非本系统方案
$CleanScript = Join-Path $SourceDir "clean.ps1"
if (Test-Path $CleanScript) {
    & $CleanScript
}

# 10. 重新部署小狼毫
Write-Host "🔄 正在部署小狼毫 (首次编译语言模型需约 15~20 秒)..." -ForegroundColor Cyan
$Deployer = Get-ChildItem -Path "${env:ProgramFiles(x86)}\Rime", "${env:ProgramFiles}\Rime" -Filter "WeaselDeployer.exe" -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
$WeaselServer = Get-ChildItem -Path "${env:ProgramFiles(x86)}\Rime", "${env:ProgramFiles}\Rime" -Filter "WeaselServer.exe" -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1

if ($Deployer) {
    try {
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = $Deployer.FullName
        $psi.Arguments = "/deploy"
        $psi.CreateNoWindow = $true
        $psi.UseShellExecute = $false
        $proc = [System.Diagnostics.Process]::Start($psi)
        $proc.WaitForExit()
    } catch {
        & $Deployer.FullName /deploy
    }
    Stop-Process -Name "WeaselDeployer" -Force -ErrorAction SilentlyContinue
    Write-Host "🎉 部署完成！" -ForegroundColor Green
}

if ($WeaselServer) {
    Start-Process -FilePath $WeaselServer.FullName
}

Write-Host "====================================================" -ForegroundColor Cyan
Write-Host "🎉 全部安装、配置、白霜拼音 + 万象语言模型部署完成！" -ForegroundColor Green
Write-Host "💡 提示：在 Windows 托盘点击「用户资料同步」将自动同步并推送到 GitHub！" -ForegroundColor Yellow
Write-Host "====================================================" -ForegroundColor Cyan
