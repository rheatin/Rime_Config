# ==============================================================================
# Rime Windows 用户词频与自造词一键/自动同步备份脚本 (支持 AES-256 隐私加密保护)
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

# 寻找 OpenSSL 路径 (Git for Windows 内置 openssl.exe)
$OpenSSL = $null
$Cmd = Get-Command "openssl" -ErrorAction SilentlyContinue
if ($Cmd) {
    $OpenSSL = $Cmd.Source
} else {
    $GitPaths = @(
        "${env:ProgramFiles}\Git\usr\bin\openssl.exe",
        "${env:ProgramFiles(x86)}\Git\usr\bin\openssl.exe",
        "${env:LOCALAPPDATA}\Programs\Git\usr\bin\openssl.exe"
    )
    foreach ($p in $GitPaths) {
        if (Test-Path $p) { $OpenSSL = $p; break }
    }
}

$VaultKeyFile = Join-Path $RimeDir ".vault_key"

# 1. 如果是手动运行，先触发 WeaselDeployer
if (-not $Auto) {
    Log-Message "手动触发模式：正在调用小狼毫导出..."
    $Deployer = Get-ChildItem -Path "${env:ProgramFiles(x86)}\Rime", "${env:ProgramFiles}\Rime" -Filter "WeaselDeployer.exe" -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($Deployer) {
        Start-Process -FilePath $Deployer.FullName -ArgumentList "/sync" -Wait
    }
} else {
    Log-Message "自动监听模式：等待 WeaselDeployer 写入完成..."
    $WaitCount = 0
    while ((Get-Process -Name "WeaselDeployer" -ErrorAction SilentlyContinue) -and ($WaitCount -lt 15)) {
        Start-Sleep -Seconds 1
        $WaitCount++
    }
    Start-Sleep -Seconds 2
}

# 2. 先拉取远端最新变更
if (Test-Path (Join-Path $ScriptDir ".git")) {
    Push-Location $ScriptDir
    try {
        git pull --rebase origin main 2>&1 | Out-String | ForEach-Object { Log-Message "Git Pull: $_" }
    } catch {}
    Pop-Location
}

# 2.0 自动解密远端同步的隐私数据包 (vault.enc)
$VaultEnc = Join-Path $ScriptDir "vault.enc"
if ((Test-Path $VaultEnc) -and (Test-Path $VaultKeyFile) -and $OpenSSL) {
    Log-Message "正在使用本地密钥解密隐私数据包 (vault.enc)..."
    $TempTar = Join-Path $env:TEMP "rime_vault_dec.tar.gz"
    try {
        & $OpenSSL enc -d -aes-256-cbc -salt -pbkdf2 -in $VaultEnc -out $TempTar -pass "file:$VaultKeyFile" 2>$null
        if (Test-Path $TempTar) {
            tar -xzf $TempTar -C $ScriptDir 2>$null
            Remove-Item -Path $TempTar -Force -ErrorAction SilentlyContinue
            Log-Message "✅ 隐私短语与词频解密提取成功！"
        }
    } catch {}
} elseif ((Test-Path $VaultEnc) -and (-not (Test-Path $VaultKeyFile))) {
    Log-Message "⚠️ 提示：检测到加密数据包 vault.enc，但未找到本地密钥文件 $VaultKeyFile"
    Log-Message "💡 请将 Mac 端 ~/Library/Rime/.vault_key 文件复制到 Windows 的 $VaultKeyFile 即可自动解密同步！"
}

# 2.1 自动执行平台专一化瘦身清理
$CleanScript = Join-Path $ScriptDir "clean.ps1"
if (Test-Path $CleanScript) {
    & $CleanScript -Quiet
}

# 2.2 检查并应用从 Git 同步过来的最新配置文件、Lua 插件与系统短语
$ConfigUpdated = $false

$RepoLua = Join-Path $ScriptDir "lua"
if (Test-Path $RepoLua) {
    $DstLua = Join-Path $RimeDir "lua"
    if (-not (Test-Path $DstLua)) { New-Item -ItemType Directory -Path $DstLua -Force | Out-Null }
    Copy-Item -Path (Join-Path $RepoLua "*") -Destination $DstLua -Recurse -Force -ErrorAction SilentlyContinue
    $ConfigUpdated = $true
}

$RepoSnippets = Join-Path $ScriptDir "snippets.txt"
$RimeSnippets = Join-Path $RimeDir "snippets.txt"
if (Test-Path $RepoSnippets) {
    if ((-not (Test-Path $RimeSnippets)) -or ((Get-FileHash $RepoSnippets).Hash -ne (Get-FileHash $RimeSnippets).Hash)) {
        Log-Message "检测到代码片段库更新: snippets.txt，正在应用..."
        Copy-Item -Path $RepoSnippets -Destination $RimeSnippets -Force
        $ConfigUpdated = $true
    }
}

Get-ChildItem -Path $ScriptDir -Filter "*.custom.yaml" -File -ErrorAction SilentlyContinue | Where-Object { $_.Name -ne "squirrel.custom.yaml" } | ForEach-Object {
    $src = $_.FullName
    $dst = Join-Path $RimeDir $_.Name
    if ((-not (Test-Path $dst)) -or ((Get-FileHash $src).Hash -ne (Get-FileHash $dst).Hash)) {
        Log-Message "检测到配置文件更新: $($_.Name)，正在应用到小狼毫用户目录..."
        Copy-Item -Path $src -Destination $dst -Force
        $ConfigUpdated = $true
    }
}

Get-ChildItem -Path $ScriptDir -Filter "*.dict.yaml" -File -ErrorAction SilentlyContinue | ForEach-Object {
    $src = $_.FullName
    $dst = Join-Path $RimeDir $_.Name
    if ((-not (Test-Path $dst)) -or ((Get-FileHash $src).Hash -ne (Get-FileHash $dst).Hash)) {
        Log-Message "检测到词库文件更新: $($_.Name)，正在应用到小狼毫用户目录..."
        Copy-Item -Path $src -Destination $dst -Force
        $ConfigUpdated = $true
    }
}

$RepoPhrase = Join-Path $ScriptDir "custom_phrase.txt"
$RimePhrase = Join-Path $RimeDir "custom_phrase.txt"
if (Test-Path $RepoPhrase) {
    if ((-not (Test-Path $RimePhrase)) -or ((Get-FileHash $RepoPhrase).Hash -ne (Get-FileHash $RimePhrase).Hash)) {
        Log-Message "发现最新的系统自定义短语，正在更新到小狼毫用户目录..."
        Copy-Item -Path $RepoPhrase -Destination $RimePhrase -Force
        $ConfigUpdated = $true
    }
}

# 3. 归档词频文件到仓库
$SourceSync = Join-Path $RimeDir "sync"
$TargetSync = Join-Path $ScriptDir "sync"

if (Test-Path $SourceSync) {
    Log-Message "正在归档词频文件从 $SourceSync 到 $TargetSync..."
    if (-not (Test-Path $TargetSync)) { New-Item -ItemType Directory -Path $TargetSync -Force | Out-Null }
    
    Copy-Item -Path (Join-Path $SourceSync "*") -Destination $TargetSync -Recurse -Force -ErrorAction SilentlyContinue
    Get-ChildItem -Path $TargetSync -Recurse -File | Where-Object { $_.Extension -ne ".txt" } | Remove-Item -Force -ErrorAction SilentlyContinue
}

# 3.1 对 custom_phrase.txt 与 sync/ 进行 AES-256 加密打包 (vault.enc)
if ((Test-Path $VaultKeyFile) -and $OpenSSL) {
    $TempTar = Join-Path $env:TEMP "rime_vault.tar.gz"
    try {
        Push-Location $ScriptDir
        tar -czf $TempTar custom_phrase.txt sync 2>$null
        if (Test-Path $TempTar) {
            & $OpenSSL enc -aes-256-cbc -salt -pbkdf2 -in $TempTar -out $VaultEnc -pass "file:$VaultKeyFile" 2>$null
            Remove-Item -Path $TempTar -Force -ErrorAction SilentlyContinue
            Log-Message "🔒 隐私短语与词频已成功通过 AES-256 加密打包 (vault.enc)！"
        }
        Pop-Location
    } catch {}
}

# 4. 提交并推送到 GitHub (仅提交密文包与脱敏模板)
if (Test-Path (Join-Path $ScriptDir ".git")) {
    Push-Location $ScriptDir
    git add vault.enc custom_phrase.example.txt snippets.txt 2>$null
    $Status = git status --porcelain
    
    if ($Status) {
        git commit -m "sync(windows): 自动同步加密词频与短语 $DateStr" 2>&1 | Out-String | ForEach-Object { Log-Message "Git Commit: $_" }
        
        $PushOut = git push origin main 2>&1 | Out-String
        Log-Message "Git Push 结果: $PushOut"
        
        if ($LASTEXITCODE -eq 0) {
            Log-Message "🎉 同步并推送到 GitHub 成功！"
            try {
                [void] [System.Reflection.Assembly]::LoadWithPartialName("System.Windows.Forms")
                $Notify = New-Object System.Windows.Forms.NotifyIcon
                $Notify.Icon = [System.Drawing.SystemIcons]::Information
                $Notify.Visible = $true
                $Notify.ShowBalloonTip(3000, "Rime 词频同步", "Windows 自造词与短语已安全加密备份到 GitHub！", [System.Windows.Forms.ToolTipIcon]::Info)
            } catch {}
        } else {
            Log-Message "❌ Git Push 失败，请检查网络或 GitHub 权限。"
        }
    } else {
        Log-Message "✨ 词频已是最新，无新增改动。"
    }
    Pop-Location
}

if ($ConfigUpdated) {
    Log-Message "正在触发小狼毫重新部署以使最新配置与短语生效..."
    $Deployer = Get-ChildItem -Path "${env:ProgramFiles(x86)}\Rime", "${env:ProgramFiles}\Rime" -Filter "WeaselDeployer.exe" -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($Deployer) {
        Start-Process -FilePath $Deployer.FullName -ArgumentList "/deploy" -Wait
    }
}

Log-Message "===== 同步流程结束 =====`n"
