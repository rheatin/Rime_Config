# ==============================================================================
# Rime Windows 词频变动监听守护脚本 (后台静默运行)
# 监听 %APPDATA%\Rime\sync 目录变动，点击「用户资料同步」即自动 Push 到 GitHub
# ==============================================================================

$RimeSyncDir = Join-Path $env:APPDATA "Rime\sync"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
if (-not $ScriptDir) { $ScriptDir = Join-Path $env:USERPROFILE "Rime_Config" }
$SyncScript = Join-Path $ScriptDir "sync.ps1"
$LogFile = Join-Path $env:TEMP "rime_sync.log"

if (-not (Test-Path $RimeSyncDir)) {
    New-Item -ItemType Directory -Path $RimeSyncDir -Force | Out-Null
}

$NowStr = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
Add-Content -Path $LogFile -Value "[$NowStr] 🚀 Rime Watcher 守护服务已启动，正在监听目录: $RimeSyncDir" -ErrorAction SilentlyContinue

$Watcher = New-Object System.IO.FileSystemWatcher
$Watcher.Path = $RimeSyncDir
$Watcher.IncludeSubdirectories = $true
$Watcher.EnableRaisingEvents = $true
$Watcher.NotifyFilter = [System.IO.NotifyFilters]::FileName -bor [System.IO.NotifyFilters]::DirectoryName -bor [System.IO.NotifyFilters]::LastWrite

$Global:LastSyncTime = [DateTime]::MinValue

$Action = {
    $Now = [DateTime]::Now
    if (($Now - $Global:LastSyncTime).TotalSeconds -ge 8) {
        $Global:LastSyncTime = $Now
        $Log = Join-Path $env:TEMP "rime_sync.log"
        $Time = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        Add-Content -Path $Log -Value "[$Time] 🔔 检测到 Rime sync 目录变动，正在唤起 sync.ps1..." -ErrorAction SilentlyContinue
        
        Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$using:SyncScript`" -Auto" -WindowStyle Hidden
    }
}

Register-ObjectEvent -InputObject $Watcher -EventName "Changed" -Action $Action | Out-Null
Register-ObjectEvent -InputObject $Watcher -EventName "Created" -Action $Action | Out-Null

while ($true) {
    Start-Sleep -Seconds 30
}
