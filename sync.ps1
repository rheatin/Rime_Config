# ==============================================================================
# Rime Windows 用户词频与自造词一键/自动同步备份脚本
# Repository: https://github.com/rheatin/Rime_Config.git
# ==============================================================================

param(
    [switch]$Auto
)

$ErrorActionPreference = "SilentlyContinue"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
if (-not $ScriptDir) { $ScriptDir = Join-Path $env:USERPROFILE "Rime_Config" }
$RimeDir = Join-Path $env:APPDATA "Rime"

# 1. 如果是手动运行，先触发 Weasel 同步导出
if (-not $Auto) {
    Write-Host "🔄 1. 正在触发小狼毫导出最新词频..." -ForegroundColor Cyan
    $Deployer = Get-ChildItem -Path "${env:ProgramFiles(x86)}\Rime", "${env:ProgramFiles}\Rime" -Filter "WeaselDeployer.exe" -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($Deployer) {
        Start-Process -FilePath $Deployer.FullName -ArgumentList "/sync" -Wait
    }
}

# 2. 归档词频文件到仓库
$SourceSync = Join-Path $RimeDir "sync"
$TargetSync = Join-Path $ScriptDir "sync"

if (Test-Path $SourceSync) {
    if (-not (Test-Path $TargetSync)) { New-Item -ItemType Directory -Path $TargetSync -Force | Out-Null }
    
    # 拷贝并只保留 *.userdb.txt
    Copy-Item -Path (Join-Path $SourceSync "*") -Destination $TargetSync -Recurse -Force
    Get-ChildItem -Path $TargetSync -Recurse -File | Where-Object { $_.Extension -ne ".txt" } | Remove-Item -Force
}

# 3. 提交并推送到 GitHub
Push-Location $ScriptDir
git add sync/
$Status = git status --porcelain

if ($Status) {
    $DateStr = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    git commit -m "sync(windows): 自动同步 Windows 端词频与自造词记忆 $DateStr"
    
    $PushSuccess = $false
    for ($i = 1; $i -le 3; $i++) {
        git push origin main
        if ($LASTEXITCODE -eq 0) {
            $PushSuccess = $true
            break
        }
        Start-Sleep -Seconds 2
    }
    
    if ($PushSuccess) {
        # Windows 原生气泡/Toast 通知
        try {
            [void] [System.Reflection.Assembly]::LoadWithPartialName("System.Windows.Forms")
            $Notify = New-Object System.Windows.Forms.NotifyIcon
            $Notify.Icon = [System.Drawing.SystemIcons]::Information
            $Notify.Visible = $true
            $Notify.ShowBalloonTip(3000, "Rime 词频同步", "Windows 自造词与词频已成功备份到 GitHub！", [System.Windows.Forms.ToolTipIcon]::Info)
        } catch {}
        Write-Host "🎉 词频已成功同步到 GitHub！" -ForegroundColor Green
    }
} else {
    Write-Host "✨ 词频已是最新，无新增改动。" -ForegroundColor Green
}
Pop-Location
