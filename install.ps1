# ==============================================================================
# Rime 自动配置与安装脚本 (Windows / 白霜拼音 + 万象语言模型 + MoeType)
# Repository: https://github.com/rheatin/Rime_Config.git
# ==============================================================================

$ErrorActionPreference = "Continue"

Write-Host "====================================================" -ForegroundColor Cyan
Write-Host " 🚀 开始配置 Rime 白霜拼音 + 万象语言模型 (Windows) " -ForegroundColor Green
Write-Host "====================================================" -ForegroundColor Cyan

# 先彻底终止可能卡在维护中的旧后台进程
Write-Host "🧹 正在清理可能卡住的旧输入法进程..." -ForegroundColor Cyan
Stop-Process -Name "WeaselDeployer" -Force -ErrorAction SilentlyContinue
Stop-Process -Name "WeaselServer" -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 1

$RimeDir = Join-Path $env:APPDATA "Rime"
$PermanentConfigDir = Join-Path $env:USERPROFILE "Rime_Config"
$RepoUrl = "https://github.com/rheatin/Rime_Config.git"
$RepoZipUrl = "https://github.com/rheatin/Rime_Config/archive/refs/heads/main.zip"
$RimeFrostUrl = "https://github.com/gaboolic/rime-frost.git"
$RimeFrostZipUrl = "https://github.com/gaboolic/rime-frost/archive/refs/heads/main.zip"
$WanxiangModelUrl = "https://github.com/amzxyz/RIME-LMDG/releases/download/LTS/wanxiang-lts-zh-hans.gram"
$MoeTypeReleaseUrl = "https://github.com/suiginko/moetype/releases/latest/download/toneless_moe.dict.yaml"

$ScriptPath = if ($MyInvocation.MyCommand.Path) { $MyInvocation.MyCommand.Path } else { "" }
$ScriptDir = if ($ScriptPath) { Split-Path -Parent $ScriptPath } else { "" }
$TempDir = $null

$NeedDownload = $true
if ($ScriptDir -and (Test-Path (Join-Path $ScriptDir "fonts"))) {
    $NeedDownload = $false
}

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
        git clone --depth=1 $RepoUrl $TempDir 2>$null
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
} else {
    if (Test-Path (Join-Path $PermanentConfigDir ".git")) {
        Push-Location $PermanentConfigDir
        try { git pull --rebase origin main 2>$null } catch {}
        Pop-Location
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

# 3. 拉取/同步 白霜拼音 (rime-frost) 词库底座
Write-Host "❄️  正在同步 白霜拼音 (rime-frost) 官方词库..." -ForegroundColor Cyan
if (-not (Test-Path $RimeDir)) {
    New-Item -ItemType Directory -Path $RimeDir -Force | Out-Null
}

$TempFrost = Join-Path $env:TEMP "rime_frost_temp"
if (Test-Path $TempFrost) { Remove-Item -Recurse -Force $TempFrost }

if (Get-Command git -ErrorAction SilentlyContinue) {
    git clone --depth=1 $RimeFrostUrl $TempFrost 2>$null
    Copy-Item -Path (Join-Path $TempFrost "*") -Destination $RimeDir -Recurse -Force
    if (Test-Path (Join-Path $TempFrost ".git")) {
        Copy-Item -Path (Join-Path $TempFrost ".git") -Destination $RimeDir -Recurse -Force
    }
} else {
    Download-And-Extract-Zip -Url $RimeFrostZipUrl -DestDir $RimeDir
}
if (Test-Path $TempFrost) { Remove-Item -Recurse -Force $TempFrost -ErrorAction SilentlyContinue }
Write-Host "✅ 白霜拼音词库同步完成！" -ForegroundColor Green

# 4. 下载万象 (Wanxiang) LTS 语言模型 (.gram)
$ModelTarget = Join-Path $RimeDir "wanxiang-lts-zh-hans.gram"
if ((Test-Path $ModelTarget) -and ((Get-Item $ModelTarget).Length -gt 350000000)) {
    Write-Host "✅ 检测到万象语言模型已就绪，跳过下载！" -ForegroundColor Green
} else {
    Write-Host "🧠 正在下载万象 (Wanxiang) LTS 语言模型 (~400MB)..." -ForegroundColor Cyan
    try {
        $ModelTemp = Join-Path $env:TEMP "wanxiang-lts-zh-hans.gram.tmp"
        Invoke-WebRequest -Uri $WanxiangModelUrl -OutFile $ModelTemp
        Move-Item -Path $ModelTemp -Destination $ModelTarget -Force
        Write-Host "✅ 万象语言模型下载完成！" -ForegroundColor Green
    } catch {
        Write-Host "⚠️ 万象语言模型下载失败: $_" -ForegroundColor Yellow
    }
}

# 5. 联网下载 MoeType 萌娘百科最新无声调词库并动态去重
Write-Host "🌸 正在联网获取 MoeType (萌娘百科) 最新官方词库..." -ForegroundColor Cyan
$RawMoeTemp = Join-Path $env:TEMP "toneless_moe_raw.dict.yaml"
try {
    Invoke-WebRequest -Uri $MoeTypeReleaseUrl -OutFile $RawMoeTemp
    Write-Host "✂️  正在对 MoeType 进行动态去重 (只保留独有词条)..." -ForegroundColor Cyan
    
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
    
    $TargetMoe = Join-Path $RimeDir "moe.dict.yaml"
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
    Write-Host "   去重完成：保留独有词条 $kept，剔除重复词条 $removed" -ForegroundColor Green
} catch {
    Write-Host "⚠️ MoeType 下载/处理跳过: $_" -ForegroundColor Yellow
}

# 6. 复制个人自定义配置与聚合词库定义 (*.custom.yaml & *.dict.yaml)
Write-Host "⚙️  正在应用个人配置与 Rheatin Solarized 皮肤..." -ForegroundColor Cyan
Copy-Item -Path (Join-Path $ScriptDir "*.custom.yaml") -Destination $RimeDir -Force
Copy-Item -Path (Join-Path $ScriptDir "*.dict.yaml") -Destination $RimeDir -Force
if (Test-Path (Join-Path $ScriptDir "custom_phrase.txt")) {
    Copy-Item -Path (Join-Path $ScriptDir "custom_phrase.txt") -Destination $RimeDir -Force
}
Write-Host "✅ 个人配置应用成功！" -ForegroundColor Green

# 7. 导入跨平台历史词频快照
if (Test-Path (Join-Path $ScriptDir "sync")) {
    Write-Host "🧠 正在导入跨平台自造词与历史词频..." -ForegroundColor Cyan
    $TargetSync = Join-Path $RimeDir "sync"
    if (-not (Test-Path $TargetSync)) { New-Item -ItemType Directory -Path $TargetSync -Force | Out-Null }
    Copy-Item -Path (Join-Path $ScriptDir "sync\*") -Destination $TargetSync -Recurse -Force
    Write-Host "✅ 跨平台词频快照就绪！" -ForegroundColor Green
}

# 8. 安装思源宋体 (若已安装则跳过)
$FontsSource = Join-Path $ScriptDir "fonts"
if (Test-Path $FontsSource) {
    $UserFontsDir = Join-Path $env:LOCALAPPDATA "Microsoft\Windows\Fonts"
    $SystemFontsDir = Join-Path $env:WINDIR "Fonts"
    
    $AllInstalled = $true
    Get-ChildItem -Path $FontsSource -Filter "*.otf" | ForEach-Object {
        $InstalledInUser = Test-Path (Join-Path $UserFontsDir $_.Name)
        $InstalledInSys = Test-Path (Join-Path $SystemFontsDir $_.Name)
        if (-not ($InstalledInUser -or $InstalledInSys)) {
            $AllInstalled = $false
        }
    }

    if ($AllInstalled) {
        Write-Host "✅ 检测到思源宋体已安装，自动跳过安装流程！" -ForegroundColor Green
    } else {
        Write-Host "🔤 正在安装并注册思源宋体..." -ForegroundColor Cyan
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
                $TargetSystemFont = Join-Path $SystemFontsDir $_.Name
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
}

# 9. 配置 Windows 用户资料同步自动 Push 守护服务
Write-Host "⚡ 配置 Windows 用户资料同步自动 Push 守护服务..." -ForegroundColor Cyan
$StartupFolder = [Environment]::GetFolderPath("Startup")
$VbsPath = Join-Path $StartupFolder "RimeSyncWatcher.vbs"
$WatcherScriptPath = Join-Path $PermanentConfigDir "sync_watcher.ps1"

Copy-Item -Path (Join-Path $ScriptDir "sync.ps1") -Destination $PermanentConfigDir -Force
Copy-Item -Path (Join-Path $ScriptDir "sync_watcher.ps1") -Destination $PermanentConfigDir -Force

$VbsContent = "CreateObject(`"Wscript.Shell`").Run `"powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"`"$WatcherScriptPath`"`"`", 0, False"
Set-Content -Path $VbsPath -Value $VbsContent -Encoding ASCII

Start-Process "wscript.exe" -ArgumentList "`"$VbsPath`"" -WindowStyle Hidden
Write-Host "✅ 自动同步监听守护进程已激活！" -ForegroundColor Green

# 10. 重新部署小狼毫
Write-Host "🔄 正在部署小狼毫 (首次编译语言模型需约 15~20 秒)..." -ForegroundColor Cyan
$Deployer = Get-ChildItem -Path "${env:ProgramFiles(x86)}\Rime", "${env:ProgramFiles}\Rime" -Filter "WeaselDeployer.exe" -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
$WeaselServer = Get-ChildItem -Path "${env:ProgramFiles(x86)}\Rime", "${env:ProgramFiles}\Rime" -Filter "WeaselServer.exe" -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1

if ($Deployer) {
    Start-Process -FilePath $Deployer.FullName -ArgumentList "/deploy" -Wait
    Start-Process -FilePath $Deployer.FullName -ArgumentList "/sync" -Wait
    Stop-Process -Name "WeaselDeployer" -Force -ErrorAction SilentlyContinue
    Write-Host "🎉 部署完成！" -ForegroundColor Green
}

if ($WeaselServer) {
    Start-Process -FilePath $WeaselServer.FullName
}

if ($TempDir -and (Test-Path $TempDir)) {
    Remove-Item -Recurse -Force $TempDir -ErrorAction SilentlyContinue
}

Write-Host "====================================================" -ForegroundColor Cyan
Write-Host "🎉 全部安装、配置、白霜拼音 + 万象语言模型部署完成！" -ForegroundColor Green
Write-Host "💡 提示：在 Windows 托盘点击「用户资料同步」将自动同步并推送到 GitHub！" -ForegroundColor Yellow
Write-Host "====================================================" -ForegroundColor Cyan
