# ==============================================================================
# Rime Windows 用户词频与自造词一键/自动同步备份脚本
# Repository: https://github.com/rheatin/Rime_Config.git
# ==============================================================================

param(
    [switch]$Auto
)

$ErrorActionPreference = "Continue"

$LogFile = Join-Path $env:TEMP "rime_sync.log"
$DateStr = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

function Log-Message {
    param([string]$Msg)
    $Line = "[$DateStr] $Msg"
    Add-Content -Path $LogFile -Value $Line -ErrorAction SilentlyContinue
    Write-Host $Msg
}

Log-Message "===== 开始执行 Rime 词频同步 (Auto=$Auto) ====="

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
if (-not $ScriptDir) { $ScriptDir = Join-Path $env:USERPROFILE "Rime_Config" }
$RimeDir = Join-Path $env:APPDATA "Rime"

# 1. 如果是手动运行，先触发 WeaselDeployer
if (-not $Auto) {
    Log-Message "手动触发模式：正在调用小狼毫导出..."
    $Deployer = Get-ChildItem -Path "${env:ProgramFiles(x86)}\Rime", "${env:ProgramFiles}\Rime" -Filter "WeaselDeployer.exe" -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($Deployer) {
        Start-Process -FilePath $Deployer.FullName -ArgumentList "/sync" -Wait
    }
} else {
    # 自动监听模式：等待外部 WeaselDeployer 写入完成
    Log-Message "自动监听模式：等待 WeaselDeployer 写入完成..."
    $WaitCount = 0
    while ((Get-Process -Name "WeaselDeployer" -ErrorAction SilentlyContinue) -and ($WaitCount -lt 15)) {
        Start-Sleep -Seconds 1
        $WaitCount++
    }
    Start-Sleep -Seconds 2
}

# 2. 先拉取远端最新变更 (在修改工作区之前 pull，避免 unstaged 冲突)
if (Test-Path (Join-Path $ScriptDir ".git")) {
    Push-Location $ScriptDir
    try {
        git pull --rebase origin main 2>&1 | Out-String | ForEach-Object { Log-Message "Git Pull: $_" }
    } catch {}
    Pop-Location
}

# 3. 归档词频文件到仓库
$SourceSync = Join-Path $RimeDir "sync"
$TargetSync = Join-Path $ScriptDir "sync"

if (Test-Path $SourceSync) {
    Log-Message "正在归档词频文件从 $SourceSync 到 $TargetSync..."
    if (-not (Test-Path $TargetSync)) { New-Item -ItemType Directory -Path $TargetSync -Force | Out-Null }
    
    Copy-Item -Path (Join-Path $SourceSync "*") -Destination $TargetSync -Recurse -Force -ErrorAction SilentlyContinue
    Get-ChildItem -Path $TargetSync -Recurse -File | Where-Object { $_.Extension -ne ".txt" } | Remove-Item -Force -ErrorAction SilentlyContinue
} else {
    Log-Message "未找到同步源目录：$SourceSync"
}

# 4. 提交并推送到 GitHub
if (Test-Path (Join-Path $ScriptDir ".git")) {
    Push-Location $ScriptDir
    git add sync/
    $Status = git status --porcelain
    
    if ($Status) {
        git commit -m "sync(windows): 自动同步 Windows 端词频与自造词记忆 $DateStr" 2>&1 | Out-String | ForEach-Object { Log-Message "Git Commit: $_" }
        
        $PushOut = git push origin main 2>&1 | Out-String
        Log-Message "Git Push 结果: $PushOut"
        
        if ($LASTEXITCODE -eq 0) {
            Log-Message "🎉 同步并推送到 GitHub 成功！"
            try {
                [void] [System.Reflection.Assembly]::LoadWithPartialName("System.Windows.Forms")
                $Notify = New-Object System.Windows.Forms.NotifyIcon
                $Notify.Icon = [System.Drawing.SystemIcons]::Information
                $Notify.Visible = $true
                $Notify.ShowBalloonTip(3000, "Rime 词频同步", "Windows 自造词与词频已成功备份到 GitHub！", [System.Windows.Forms.ToolTipIcon]::Info)
            } catch {}
        } else {
            Log-Message "❌ Git Push 失败，请检查网络或 GitHub 权限。"
        }
    } else {
        Log-Message "✨ 词频已是最新，无新增改动。"
    }
    Pop-Location
}

Log-Message "===== 同步流程结束 =====`n"
