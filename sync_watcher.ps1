# ==============================================================================
# Rime Windows 词频变动监听守护脚本 (后台静默运行)
# 监听 %APPDATA%\Rime\sync 目录，点击「用户词典同步」即自动 Push 到 GitHub
# ==============================================================================

$RimeSyncDir = Join-Path $env:APPDATA "Rime\sync"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
if (-not $ScriptDir) { $ScriptDir = Join-Path $env:USERPROFILE "Rime_Config" }
$SyncScript = Join-Path $ScriptDir "sync.ps1"

if (-not (Test-Path $RimeSyncDir)) {
    New-Item -ItemType Directory -Path $RimeSyncDir -Force | Out-Null
}

$Watcher = New-Object System.IO.FileSystemWatcher
$Watcher.Path = $RimeSyncDir
$Watcher.IncludeSubdirectories = $true
$Watcher.EnableRaisingEvents = $true
$Watcher.Filter = "*.txt"
$Watcher.NotifyFilter = [System.IO.NotifyFilters]::FileName -bor [System.IO.NotifyFilters]::LastWrite

$LastSyncTime = [DateTime]::MinValue

$Action = {
    $Now = [DateTime]::Now
    # 防抖机制：5秒内只触发一次
    if (($Now - $script:LastSyncTime).TotalSeconds -ge 5) {
        $script:LastSyncTime = $Now
        Start-Sleep -Seconds 2
        Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$using:SyncScript`" -Auto" -WindowStyle Hidden
    }
}

Register-ObjectEvent -InputObject $Watcher -EventName "Changed" -Action $Action | Out-Null
Register-ObjectEvent -InputObject $Watcher -EventName "Created" -Action $Action | Out-Null

while ($true) {
    Start-Sleep -Seconds 60
}
