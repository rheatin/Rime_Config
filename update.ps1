# ==============================================================================
# Rime 词库底座与 AI 语言模型独立升级脚本 (update.ps1)
# 职责：
#   1. 读取用户本地画像 (.rime_profile)，仅追更用户选定的方案与组件
#   2. 自动更新底座词库 (rime-frost / rime-ice / 自定义方案)
#   3. 比对 GitHub Release SHA256，增量升级万象大模型与 MoeType
#   4. 触发小狼毫重新部署
# ==============================================================================

param(
    [switch]$Quiet
)

$ErrorActionPreference = "Continue"

Write-Host "====================================================" -ForegroundColor Cyan
Write-Host " 🔄 开始升级 Windows 小狼毫词库底座、语言模型与组件   " -ForegroundColor Green
Write-Host "====================================================" -ForegroundColor Cyan

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
if (-not $ScriptDir) { $ScriptDir = Join-Path $env:USERPROFILE "Rime_Config" }
$RimeDir = Join-Path $env:APPDATA "Rime"

$ProfileFile = Join-Path $ScriptDir ".rime_profile"
if (-not (Test-Path $ProfileFile)) { $ProfileFile = Join-Path $RimeDir ".rime_profile" }

$Framework = "rime-frost"
$CustomRepo = ""
$Schema = "rime_frost"
$Model = "wanxiang_lts"
$EnableMoe = $true

if (Test-Path $ProfileFile) {
    Get-Content $ProfileFile -Encoding UTF8 -ErrorAction SilentlyContinue | ForEach-Object {
        if ($_ -match '^RIME_FRAMEWORK=["'']?([^"'']+)["'']?') { $Framework = $Matches[1] }
        if ($_ -match '^RIME_CUSTOM_REPO=["'']?([^"'']+)["'']?') { $CustomRepo = $Matches[1] }
        if ($_ -match '^RIME_SCHEMA=["'']?([^"'']+)["'']?') { $Schema = $Matches[1] }
        if ($_ -match '^RIME_MODEL=["'']?([^"'']+)["'']?') { $Model = $Matches[1] }
        if ($_ -match '^RIME_ENABLE_MOE=["'']?(false|true)["'']?') { $EnableMoe = ($Matches[1] -eq "true") }
    }
}

Write-Host "📋 当前用户偏好画像:" -ForegroundColor Cyan
Write-Host "   • 底座框架: $Framework"
Write-Host "   • 当前方案: $Schema"
Write-Host "   • 语言模型: $Model"
Write-Host "   • 萌娘百科: $EnableMoe"

# 1. 追更底座词库
$TargetFwUrl = "https://github.com/gaboolic/rime-frost.git"
if ($Framework -eq "rime-ice") {
    $TargetFwUrl = "https://github.com/iDvel/rime-ice.git"
    Write-Host "❄️  正在更新 雾凇拼音 (rime-ice) 底座词库..." -ForegroundColor Cyan
} elseif ($Framework -eq "custom" -and $CustomRepo) {
    $TargetFwUrl = $CustomRepo
    Write-Host "📦 正在更新 自定义方案底座 ($CustomRepo)..." -ForegroundColor Cyan
} else {
    Write-Host "❄️  正在更新 白霜拼音 (rime-frost) 底座词库..." -ForegroundColor Cyan
}

$TempFw = Join-Path $env:TEMP "$([System.Guid]::NewGuid())"
if (Get-Command git -ErrorAction SilentlyContinue) {
    git clone --depth=1 $TargetFwUrl $TempFw 2>$null
    if (Test-Path $TempFw) {
        Copy-Item -Path (Join-Path $TempFw "*") -Destination $RimeDir -Recurse -Force
        Remove-Item -Recurse -Force $TempFw -ErrorAction SilentlyContinue
        Write-Host "✅ 底座词库更新完成！" -ForegroundColor Green
    }
}

# 2. 追更万象语言模型 (若启用)
if ($Model -eq "wanxiang_lts") {
    $ModelTarget = Join-Path $RimeDir "wanxiang-lts-zh-hans.gram"
    $WanxiangApiUrl = "https://api.github.com/repos/amzxyz/rime-wanxiang-data/releases/tags/LTS"
    $WanxiangModelUrl = "https://github.com/amzxyz/rime-wanxiang-data/releases/download/LTS/wanxiang-lts-zh-hans.gram"
    
    Write-Host "🌐 正在比对万象语言模型远程版本..." -ForegroundColor Cyan
    try {
        $resp = Invoke-RestMethod -Uri $WanxiangApiUrl -TimeoutSec 8 -Headers @{"User-Agent"="Mozilla/5.0"}
        $asset = $resp.assets | Where-Object { $_.name -eq "wanxiang-lts-zh-hans.gram" } | Select-Object -First 1
        $RemoteSha = if ($asset.digest -and $asset.digest.StartsWith("sha256:")) { $asset.digest.Substring(7).ToUpper() } else { "" }
        
        $NeedDownload = $true
        if ((Test-Path $ModelTarget) -and $RemoteSha) {
            $CurrentSha = (Get-FileHash -Path $ModelTarget -Algorithm SHA256).Hash.ToUpper()
            if ($CurrentSha -eq $RemoteSha) {
                Write-Host "✅ 本地万象语言模型已是最新，跳过下载！" -ForegroundColor Green
                $NeedDownload = $false
            }
        }
        
        if ($NeedDownload) {
            Write-Host "🧠 正在下载最新万象 (Wanxiang) LTS 语言模型 (~400MB)..." -ForegroundColor Cyan
            $ModelTemp = Join-Path $env:TEMP "wanxiang-lts.gram.tmp"
            Invoke-WebRequest -Uri $WanxiangModelUrl -OutFile $ModelTemp
            Move-Item -Path $ModelTemp -Destination $ModelTarget -Force
            Write-Host "✅ 万象语言模型更新完成！" -ForegroundColor Green
        }
    } catch {
        Write-Host "⚠️ 语言模型拉取受阻，保留本地现存版本继续。" -ForegroundColor Yellow
    }
}

# 3. 追更 MoeType 词库 (若启用)
if ($EnableMoe) {
    $TargetMoe = Join-Path $RimeDir "moe.dict.yaml"
    $MoeDigestFile = Join-Path $RimeDir ".moe_digest"
    $MoeTypeApiUrl = "https://api.github.com/repos/suiginko/moetype/releases/latest"
    $MoeTypeReleaseUrl = "https://github.com/suiginko/moetype/releases/latest/download/toneless_moe.dict.yaml"

    try {
        $resp = Invoke-RestMethod -Uri $MoeTypeApiUrl -TimeoutSec 8 -Headers @{"User-Agent"="Mozilla/5.0"}
        $asset = $resp.assets | Where-Object { $_.name -eq "toneless_moe.dict.yaml" } | Select-Object -First 1
        $RemoteMoeSha = if ($asset.digest -and $asset.digest.StartsWith("sha256:")) { $asset.digest.Substring(7) } else { "" }

        $NeedMoe = $true
        if ((Test-Path $TargetMoe) -and (Test-Path $MoeDigestFile) -and $RemoteMoeSha) {
            $Saved = (Get-Content $MoeDigestFile -Raw).Trim()
            if ($Saved -eq $RemoteMoeSha) {
                Write-Host "✅ 本地 MoeType 萌娘百科词库已是最新，跳过下载！" -ForegroundColor Green
                $NeedMoe = $false
            }
        }

        if ($NeedMoe) {
            Write-Host "🌸 正在拉取 MoeType 最新词库并更新..." -ForegroundColor Cyan
            Invoke-WebRequest -Uri $MoeTypeReleaseUrl -OutFile $TargetMoe
            if ($RemoteMoeSha) { Set-Content -Path $MoeDigestFile -Value $RemoteMoeSha -Encoding ASCII }
            Write-Host "✅ MoeType 词库更新完成！" -ForegroundColor Green
        }
    } catch {
        Write-Host "⚠️ MoeType 下载受阻，保留本地旧版继续。" -ForegroundColor Yellow
    }
}

# 4. 执行智能清理
$CleanScript = Join-Path $ScriptDir "clean.ps1"
if (Test-Path $CleanScript) { & $CleanScript -Quiet }

# 5. 重新部署小狼毫
Write-Host "🔄 正在重新部署小狼毫..." -ForegroundColor Cyan
$Deployer = Get-ChildItem -Path "${env:ProgramFiles(x86)}\Rime", "${env:ProgramFiles}\Rime" -Filter "WeaselDeployer.exe" -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
if ($Deployer) {
    & $Deployer.FullName /deploy
    Stop-Process -Name "WeaselDeployer" -Force -ErrorAction SilentlyContinue
    Write-Host "🎉 升级与部署完成！" -ForegroundColor Green
}
