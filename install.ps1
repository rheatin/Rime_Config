# ==============================================================================
# Rime 自动配置与安装脚本 (Windows / Weasel 小狼毫)
# Repository: https://github.com/rheatin/Rime_Config.git
# ==============================================================================

$ErrorActionPreference = "Stop"

Write-Host "====================================================" -ForegroundColor Cyan
Write-Host "       🚀 开始配置 Rime 雾凇拼音与个人环境 (Windows)   " -ForegroundColor Green
Write-Host "====================================================" -ForegroundColor Cyan

$RimeDir = Join-Path $env:APPDATA "Rime"
$PermanentConfigDir = Join-Path $env:USERPROFILE "Rime_Config"
$RepoUrl = "https://github.com/rheatin/Rime_Config.git"
$RepoZipUrl = "https://github.com/rheatin/Rime_Config/archive/refs/heads/main.zip"
$RimeIceUrl = "https://github.com/iDvel/rime-ice.git"
$RimeIceZipUrl = "https://github.com/iDvel/rime-ice/archive/refs/heads/main.zip"

# 安全判断是否为本地执行还是网络管道 (iex) 执行
$ScriptPath = if ($MyInvocation.MyCommand.Path) { $MyInvocation.MyCommand.Path } else { "" }
$ScriptDir = if ($ScriptPath) { Split-Path -Parent $ScriptPath } else { "" }
$TempDir = $null

$NeedDownload = $true
if ($ScriptDir -and (Test-Path (Join-Path $ScriptDir "fonts"))) {
    $NeedDownload = $false
}

# 辅助函数：下载并解压缩
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

# 1. 准备个人配置文件与字体资源
if ($NeedDownload) {
    Write-Host "📥 正在获取 Rime_Config 仓库资源..." -ForegroundColor Cyan
    $TempDir = Join-Path $env:TEMP "Rime_Config_Temp"
    if (Test-Path $TempDir) { Remove-Item -Recurse -Force $TempDir }
    
    if (Get-Command git -ErrorAction SilentlyContinue) {
        git clone --depth=1 $RepoUrl $TempDir
    } else {
        Download-And-Extract-Zip -Url $RepoZipUrl -DestDir $TempDir
    }
    $ScriptDir = $TempDir
}

# 永久保留一套配置仓库于本地用户目录 (供 sync 脚本与守护服务使用)
if (-not (Test-Path $PermanentConfigDir)) {
    if (Get-Command git -ErrorAction SilentlyContinue) {
        git clone $RepoUrl $PermanentConfigDir 2>$null
    } else {
        Copy-Item -Path $ScriptDir -Destination $PermanentConfigDir -Recurse -Force
    }
}

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

# 3. 拉取/同步 雾凇拼音 (rime-ice) 词库底座
Write-Host "❄️  正在同步 雾凇拼音 (rime-ice) 官方词库..." -ForegroundColor Cyan
if (-not (Test-Path $RimeDir)) {
    New-Item -ItemType Directory -Path $RimeDir -Force | Out-Null
}

if (Test-Path (Join-Path $RimeDir ".git")) {
    Push-Location $RimeDir
    try { git pull --ff-only } catch {}
    Pop-Location
} else {
    $TempRimeIce = Join-Path $env:TEMP "rime_ice_temp"
    if (Test-Path $TempRimeIce) { Remove-Item -Recurse -Force $TempRimeIce -ErrorAction SilentlyContinue }
    
    if (Get-Command git -ErrorAction SilentlyContinue) {
        git clone --depth=1 $RimeIceUrl $TempRimeIce
        Copy-Item -Path (Join-Path $TempRimeIce "*") -Destination $RimeDir -Recurse -Force
        if (Test-Path (Join-Path $TempRimeIce ".git")) {
            Copy-Item -Path (Join-Path $TempRimeIce ".git") -Destination $RimeDir -Recurse -Force
        }
    } else {
        Download-And-Extract-Zip -Url $RimeIceZipUrl -DestDir $RimeDir
    }
    if (Test-Path $TempRimeIce) { Remove-Item -Recurse -Force $TempRimeIce -ErrorAction SilentlyContinue }
}
Write-Host "✅ 雾凇拼音词库同步完成！" -ForegroundColor Green

# 4. 复制个人自定义配置 (*.custom.yaml)
Write-Host "⚙️  正在应用个人配置与 Rheatin Solarized 皮肤..." -ForegroundColor Cyan
Copy-Item -Path (Join-Path $ScriptDir "*.custom.yaml") -Destination $RimeDir -Force
if (Test-Path (Join-Path $ScriptDir "custom_phrase.txt")) {
    Copy-Item -Path (Join-Path $ScriptDir "custom_phrase.txt") -Destination $RimeDir -Force
}
Write-Host "✅ 个人配置应用成功！" -ForegroundColor Green

# 5. 导入跨平台 (Mac/云端) 历史词频与自造词快照
if (Test-Path (Join-Path $ScriptDir "sync")) {
    Write-Host "🧠 正在导入跨平台自造词与历史词频..." -ForegroundColor Cyan
    $TargetSync = Join-Path $RimeDir "sync"
    if (-not (Test-Path $TargetSync)) { New-Item -ItemType Directory -Path $TargetSync -Force | Out-Null }
    Copy-Item -Path (Join-Path $ScriptDir "sync\*") -Destination $TargetSync -Recurse -Force
    Write-Host "✅ 跨平台词频快照就绪！" -ForegroundColor Green
}

# 6. 安装思源宋体到 Windows 系统
$FontsSource = Join-Path $ScriptDir "fonts"
if (Test-Path $FontsSource) {
    Write-Host "🔤 正在安装并注册思源宋体..." -ForegroundColor Cyan
    $UserFontsDir = Join-Path $env:LOCALAPPDATA "Microsoft\Windows\Fonts"
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
        Get-ChildItem -Path $FontsSource -Filter "*.otf" | ForEach-Object {
            $TargetSystemFont = Join-Path $env:WINDIR "Fonts\$($_.Name)"
            if (-not (Test-Path $TargetSystemFont)) {
                $FontsFolder.CopyHere($_.FullName, 16)
            }
        }
    } catch {}

    Get-ChildItem -Path $FontsSource -Filter "*.otf" | ForEach-Object {
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
            "思源宋体 Heavy (OpenType)"
        )
        foreach ($alias in $Aliases) {
            Set-ItemProperty -Path $RegKeyPath -Name $alias -Value $DestPath -Force -ErrorAction SilentlyContinue
        }
        
        try { [FontHelper]::AddFontResource($DestPath) | Out-Null } catch {}
    }
    try { [FontHelper]::SendMessage([IntPtr]0xffff, 0x001D, [IntPtr]::Zero, [IntPtr]::Zero) | Out-Null } catch {}
    Write-Host "✅ 思源宋体安装与即时注册完成！" -ForegroundColor Green
}

# 7. 配置 Windows 托盘「用户词典同步」自动 Push 到 GitHub 守护服务
Write-Host "⚡ 配置 Windows 词典同步自动 Push 守护服务..." -ForegroundColor Cyan
$StartupFolder = [Environment]::GetFolderPath("Startup")
$VbsPath = Join-Path $StartupFolder "RimeSyncWatcher.vbs"
$WatcherScriptPath = Join-Path $PermanentConfigDir "sync_watcher.ps1"

# 复制 sync 相关脚本到永久目录
Copy-Item -Path (Join-Path $ScriptDir "sync.ps1") -Destination $PermanentConfigDir -Force
Copy-Item -Path (Join-Path $ScriptDir "sync_watcher.ps1") -Destination $PermanentConfigDir -Force

$VbsContent = "CreateObject(`"Wscript.Shell`").Run `"powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"`"$WatcherScriptPath`"`"`", 0, False"
Set-Content -Path $VbsPath -Value $VbsContent -Encoding ASCII

# 立即在后台静默启动 Watcher
Start-Process "wscript.exe" -ArgumentList "`"$VbsPath`"" -WindowStyle Hidden
Write-Host "✅ 自动同步监听守护进程已激活！" -ForegroundColor Green

# 8. 重启 Weasel 服务并重新部署与双向合并
Write-Host "🔄 正在重启小狼毫服务并重新部署..." -ForegroundColor Cyan
Stop-Process -Name "WeaselServer" -Force -ErrorAction SilentlyContinue
Stop-Process -Name "WeaselDeployer" -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 1

$Deployer = Get-ChildItem -Path "${env:ProgramFiles(x86)}\Rime", "${env:ProgramFiles}\Rime" -Filter "WeaselDeployer.exe" -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
$WeaselServer = Get-ChildItem -Path "${env:ProgramFiles(x86)}\Rime", "${env:ProgramFiles}\Rime" -Filter "WeaselServer.exe" -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1

if ($Deployer) {
    Start-Process -FilePath $Deployer.FullName -ArgumentList "/deploy" -Wait
    Start-Process -FilePath $Deployer.FullName -ArgumentList "/sync" -Wait
    Write-Host "🎉 部署与双向词频合并完成！" -ForegroundColor Green
}

if ($WeaselServer) {
    Start-Process -FilePath $WeaselServer.FullName
}

if ($TempDir -and (Test-Path $TempDir)) {
    Remove-Item -Recurse -Force $TempDir -ErrorAction SilentlyContinue
}

Write-Host "====================================================" -ForegroundColor Cyan
Write-Host "🎉 全部安装、配置与词频恢复已完成！" -ForegroundColor Green
Write-Host "💡 提示：在 Windows 托盘点击「用户词典同步」将自动同步并推送到 GitHub！" -ForegroundColor Yellow
Write-Host "====================================================" -ForegroundColor Cyan
