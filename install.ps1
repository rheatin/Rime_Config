# ==============================================================================
# Rime 自动配置与安装脚本 (Windows / Weasel 小狼毫)
# Repository: https://github.com/rheatin/Rime_Config.git
# ==============================================================================

$ErrorActionPreference = "Stop"

Write-Host "====================================================" -ForegroundColor Cyan
Write-Host "       🚀 开始配置 Rime 雾凇拼音与个人环境 (Windows)   " -ForegroundColor Green
Write-Host "====================================================" -ForegroundColor Cyan

$RimeDir = Join-Path $env:APPDATA "Rime"
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

# 2. 检测与安装 Weasel (小狼毫)
$WeaselDir = "${env:ProgramFiles(x86)}\Rime\weasel-*"
$WeaselInstalled = Test-Path $WeaselDir

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
    git pull --ff-only
    Pop-Location
} else {
    if (Get-Command git -ErrorAction SilentlyContinue) {
        git clone --depth=1 $RimeIceUrl $RimeDir
    } else {
        Download-And-Extract-Zip -Url $RimeIceZipUrl -DestDir $RimeDir
    }
}

# 4. 复制个人自定义配置 (*.custom.yaml)
Write-Host "⚙️  正在应用个人配置与 Rheatin Solarized 皮肤..." -ForegroundColor Cyan
Copy-Item -Path (Join-Path $ScriptDir "*.custom.yaml") -Destination $RimeDir -Force
if (Test-Path (Join-Path $ScriptDir "custom_phrase.txt")) {
    Copy-Item -Path (Join-Path $ScriptDir "custom_phrase.txt") -Destination $RimeDir -Force
}
Write-Host "✅ 个人配置应用成功！" -ForegroundColor Green

# 5. 导入个人历史词频快照
if (Test-Path (Join-Path $ScriptDir "sync")) {
    Write-Host "🧠 正在同步历史自造词与词频快照..." -ForegroundColor Cyan
    $TargetSync = Join-Path $RimeDir "sync"
    if (-not (Test-Path $TargetSync)) { New-Item -ItemType Directory -Path $TargetSync -Force | Out-Null }
    Copy-Item -Path (Join-Path $ScriptDir "sync\*") -Destination $TargetSync -Recurse -Force
    Write-Host "✅ 词频快照就绪！" -ForegroundColor Green
}

# 6. 安装思源宋体到 Windows 字体库
$FontsSource = Join-Path $ScriptDir "fonts"
if (Test-Path $FontsSource) {
    Write-Host "🔤 正在安装思源宋体..." -ForegroundColor Cyan
    try {
        $ShellApp = New-Object -ComObject Shell.Application
        $FontsFolder = $ShellApp.Namespace(0x14)
        Get-ChildItem -Path $FontsSource -Filter "*.otf" | ForEach-Object {
            $FontName = $_.Name
            $TargetFont = Join-Path $env:WINDIR "Fonts\$FontName"
            if (-not (Test-Path $TargetFont)) {
                $FontsFolder.CopyHere($_.FullName, 16)
            }
        }
        Write-Host "✅ 字体安装完成！" -ForegroundColor Green
    } catch {
        Write-Host "⚠️ 字体自动注册跳过，可手动双击 fonts 目录下字体安装。" -ForegroundColor Yellow
    }
}

# 7. 重新部署 Weasel 与合并词频
Write-Host "🔄 正在触发小狼毫重新部署与词频合并..." -ForegroundColor Cyan
$Deployer = Get-ChildItem -Path "${env:ProgramFiles(x86)}\Rime" -Filter "WeaselDeployer.exe" -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $Deployer) {
    $Deployer = Get-ChildItem -Path "${env:ProgramFiles}\Rime" -Filter "WeaselDeployer.exe" -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
}

if ($Deployer) {
    Start-Process -FilePath $Deployer.FullName -ArgumentList "/deploy" -Wait
    Start-Process -FilePath $Deployer.FullName -ArgumentList "/sync" -Wait
    Write-Host "🎉 部署与词频合并完成！" -ForegroundColor Green
}

if ($TempDir -and (Test-Path $TempDir)) {
    Remove-Item -Recurse -Force $TempDir -ErrorAction SilentlyContinue
}

Write-Host "====================================================" -ForegroundColor Cyan
Write-Host "🎉 全部安装、配置与词频恢复已完成！" -ForegroundColor Green
Write-Host "====================================================" -ForegroundColor Cyan
