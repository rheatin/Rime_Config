# ==============================================================================
# Rime Windows 用户词频与自造词一键/自动同步备份脚本
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

# 1. 如果是手动运行，等待并触发 WeaselDeployer
if (-not $Auto) {
    Log-Message "手动触发模式：正在调用 Weasel 同步..."
    $Deployer = Get-ChildItem -Path "${env:ProgramFiles(x86)}\Rime", "${env:ProgramFiles}\Rime" -Filter "WeaselDeployer.exe" -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($Deployer) {
        Start-Process -FilePath $Deployer.FullName -ArgumentList "/sync" -Wait
    }
} else {
    # 自动监听模式：等待外部 WeaselDeployer 进程完全退出，确保文件解除占用且维护模式结束
    Log-Message "自动监听模式：等待 WeaselDeployer 写入完成..."
    $WaitCount = 0
    while ((Get-Process -Name "WeaselDeployer" -ErrorAction SilentlyContinue) -and ($WaitCount -lt 15)) {
        Start-Sleep -Seconds 1
        $WaitCount++
    }
    Start-Sleep -Seconds 2
}

# 2. 归档词频文件到仓库
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

# 3. 提交并推送到 GitHub
if (Test-Path (Join-Path $ScriptDir ".git")) {
    Push-Location $ScriptDir
    
    # 拉取远端最新提交以防冲突
    git pull --rebase origin main 2>&1 | Out-String | ForEach-Object { Log-Message "Git Pull: $_" }
    
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
            Log-Message "❌ Git Push 失败，请检查网络或 GitHub 认证权限。"
            try {
                [void] [System.Reflection.Assembly]::LoadWithPartialName("System.Windows.Forms")
                $Notify = New-Object System.Windows.Forms.NotifyIcon
                $Notify.Icon = [System.Drawing.SystemIcons]::Warning
                $Notify.Visible = $true
                $Notify.ShowBalloonTip(5000, "Rime 词频同步失败", "Git 推送失败，请查看 $LogFile 了解详情。", [System.Windows.Forms.ToolTipIcon]::Warning)
            } catch {}
        }
    } else {
        Log-Message "✨ 词频已是最新，无新增改动。"
    }
    Pop-Location
} else {
    Log-Message "❌ $ScriptDir 不是一个有效的 Git 仓库！"
}

Log-Message "===== 同步流程结束 =====`n"
