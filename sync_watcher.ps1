# ==============================================================================
# Rime Windows 词频变动监听守护脚本 (后台静默运行)
# 监听 %APPDATA%\Rime\sync 目录变动，点击「用户资料同步」即自动 Push 到 GitHub
# ==============================================================================

param(
    [switch]$Install,
    [switch]$Uninstall,
    [switch]$Status
)

$ErrorActionPreference = "Continue"

$RimeSyncDir = Join-Path $env:APPDATA "Rime\sync"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
if (-not $ScriptDir) { $ScriptDir = Join-Path $env:USERPROFILE "Rime_Config" }
$SyncScript = Join-Path $ScriptDir "sync.ps1"
$LogFile = Join-Path $env:TEMP "rime_sync.log"
$StartupFolder = [Environment]::GetFolderPath("Startup")
$VbsPath = Join-Path $StartupFolder "RimeSyncWatcher.vbs"

function Show-Balloon {
    param([string]$Title = "Rime 词频守护", [string]$Message = "")
    try {
        [void] [System.Reflection.Assembly]::LoadWithPartialName("System.Windows.Forms")
        $Notify = New-Object System.Windows.Forms.NotifyIcon
        $Notify.Icon = [System.Drawing.SystemIcons]::Information
        $Notify.Visible = $true
        $Notify.ShowBalloonTip(3000, $Title, $Message, [System.Windows.Forms.ToolTipIcon]::Info)
    } catch {}
}

# 1. 查询守护进程运行状态
if ($Status) {
    $Procs = Get-WmiObject Win32_Process | Where-Object { $_.CommandLine -like "*sync_watcher.ps1*" }
    if ($Procs) {
        Write-Host "✅ Rime 词频守护服务正在后台运行中 (PID: $($Procs.ProcessId -join ', '))" -ForegroundColor Green
    } else {
        Write-Host "⚠️ Rime 词频守护服务当前未在后台运行。" -ForegroundColor Yellow
    }
    return
}

# 2. 卸载开机自启
if ($Uninstall) {
    if (Test-Path $VbsPath) {
        Remove-Item -Path $VbsPath -Force -ErrorAction SilentlyContinue
        Write-Host "✅ 已从开机启动项中移除守护服务脚本。" -ForegroundColor Green
    }
    $Procs = Get-WmiObject Win32_Process | Where-Object { $_.CommandLine -like "*sync_watcher.ps1*" }
    if ($Procs) {
        $Procs | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
        Write-Host "✅ 已终止正在运行的守护进程。" -ForegroundColor Green
    }
    return
}

# 3. 安装开机自启并启动
if ($Install) {
    $VbsContent = "CreateObject(`"Wscript.Shell`").Run `"powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"`"$SyncScript`" -Auto`", 0, False"
    $WatcherVbsContent = "CreateObject(`"Wscript.Shell`").Run `"powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"`"$PSCommandPath`"`"`", 0, False"
    Set-Content -Path $VbsPath -Value $WatcherVbsContent -Encoding ASCII
    Start-Process "wscript.exe" -ArgumentList "`"$VbsPath`"" -WindowStyle Hidden
    Write-Host "✅ 自动同步监听守护进程已成功安装并启动！" -ForegroundColor Green
    return
}

# 4. 常驻监听主逻辑
if (-not (Test-Path $RimeSyncDir)) {
    New-Item -ItemType Directory -Path $RimeSyncDir -Force | Out-Null
}

$NowStr = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
Add-Content -Path $LogFile -Value "[$NowStr] 🚀 Rime Watcher 守护服务已启动，正在监听目录: $RimeSyncDir" -ErrorAction SilentlyContinue

# 导出同步脚本路径到环境变量，供事件块全局安全读取
$env:RIME_SYNC_SCRIPT_PATH = $SyncScript

$Watcher = New-Object System.IO.FileSystemWatcher
$Watcher.Path = $RimeSyncDir
$Watcher.IncludeSubdirectories = $true
$Watcher.EnableRaisingEvents = $true
$Watcher.NotifyFilter = [System.IO.NotifyFilters]::FileName -bor [System.IO.NotifyFilters]::DirectoryName -bor [System.IO.NotifyFilters]::LastWrite

# 使用安全锁文件防抖 (解决多事件并发与作用域失效问题)
$Global:SyncLockFile = Join-Path $env:TEMP "rime_watcher_sync.lock"
if (Test-Path $Global:SyncLockFile) {
    Remove-Item -Path $Global:SyncLockFile -Force -ErrorAction SilentlyContinue
}

$Action = {
    $Lock = Join-Path $env:TEMP "rime_watcher_sync.lock"
    $Now = [DateTime]::Now
    
    # 8 秒防抖检查
    if (Test-Path $Lock) {
        $LastTime = (Get-Item $Lock).LastWriteTime
        if (($Now - $LastTime).TotalSeconds -lt 8) {
            return
        }
    }
    Set-Content -Path $Lock -Value $Now.ToString() -ErrorAction SilentlyContinue

    $Log = Join-Path $env:TEMP "rime_sync.log"
    $Time = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Add-Content -Path $Log -Value "[$Time] 🔔 检测到 Rime sync 目录变动，等待写入沉降..." -ErrorAction SilentlyContinue

    # 缓冲 3 秒等待小狼毫完成词库文件写入
    Start-Sleep -Seconds 3

    # 安全读取同步脚本路径并唤起 sync.ps1
    $ScriptToRun = $env:RIME_SYNC_SCRIPT_PATH
    if (-not $ScriptToRun -or -not (Test-Path $ScriptToRun)) {
        $ScriptToRun = Join-Path $env:USERPROFILE "Rime_Config\sync.ps1"
    }

    if (Test-Path $ScriptToRun) {
        Add-Content -Path $Log -Value "[$Time] 🚀 正在后台唤起: $ScriptToRun -Auto" -ErrorAction SilentlyContinue
        Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$ScriptToRun`" -Auto" -WindowStyle Hidden
    } else {
        Add-Content -Path $Log -Value "[$Time] ❌ 未找到同步脚本: $ScriptToRun" -ErrorAction SilentlyContinue
    }
}

Register-ObjectEvent -InputObject $Watcher -EventName "Changed" -Action $Action -MessageData $SyncScript | Out-Null
Register-ObjectEvent -InputObject $Watcher -EventName "Created" -Action $Action -MessageData $SyncScript | Out-Null

Show-Balloon -Title "Rime 词频守护" -Message "Windows 词频变动监听已启动，点击「用户资料同步」即可自动备份到 GitHub！"

while ($true) {
    Start-Sleep -Seconds 30
}
