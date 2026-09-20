# ==============================================================================
# Rime Windows 用户词频与自造词一键/自动同步备份脚本 (支持交互式密码与 AES-256 隐私加密)
# Repository: https://github.com/rheatin/Rime_Config.git
# ==============================================================================

param(
    [switch]$Auto,
    [switch]$ResetPass
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

# 获取同步密码 (支持交互式输入、Windows DPAPI 本地安全保护记忆与免输)
function Get-VaultPass {
    param([switch]$Auto, [switch]$ResetPass)

    # 1. 优先读取环境变量
    if ($env:RIME_VAULT_PASS) {
        return $env:RIME_VAULT_PASS
    }

    $SavedPassFile = Join-Path $RimeDir ".vault_pass.dpapi"

    # 如果请求重置密码，删除旧凭据
    if ($ResetPass -and (Test-Path $SavedPassFile)) {
        Remove-Item -Path $SavedPassFile -Force -ErrorAction SilentlyContinue
    } else {
        # 2. 尝试读取通过 Windows DPAPI 本地硬件/用户凭据保护存储的密码
        if (Test-Path $SavedPassFile) {
            try {
                $EncBytes = [System.IO.File]::ReadAllBytes($SavedPassFile)
                $DecBytes = [System.Security.Cryptography.ProtectedData]::Unprotect($EncBytes, $null, [System.Security.Cryptography.DataProtectionScope]::CurrentUser)
                $DecPass = [System.Text.Encoding]::UTF8.GetString($DecBytes)
                if ($DecPass) { return $DecPass }
            } catch {}
        }
    }

    # 3. 如果是后台自动监听模式，无法交互输入
    if ($Auto) {
        return $null
    }

    # 4. 交互提示用户输入密码
    Write-Host "`n====================================================" -ForegroundColor Cyan
    Write-Host "🔒 Rime 隐私数据加密同步 (首次配置 / 验证)" -ForegroundColor Yellow
    Write-Host "请输入你的同步密码 (与 Mac 端设置的密码一致即可自动互通)："
    $SecurePass = Read-Host "🔑 请输入密码" -AsSecureString
    $BSTR = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($SecurePass)
    $PlainPass = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR)

    if (-not $PlainPass) {
        Write-Host "⚠️ 未输入密码，本次跳过加密隐私数据同步。" -ForegroundColor Yellow
        return $null
    }

    # 询问是否记住密码
    $Remember = Read-Host "是否记住该密码 (下次同步自动免输，通过 Windows DPAPI 本地硬件级加密) [Y/n]?"
    if (($Remember -eq "") -or ($Remember -match "^[Yy]")) {
        try {
            $PassBytes = [System.Text.Encoding]::UTF8.GetBytes($PlainPass)
            $EncBytes = [System.Security.Cryptography.ProtectedData]::Protect($PassBytes, $null, [System.Security.Cryptography.DataProtectionScope]::CurrentUser)
            [System.IO.File]::WriteAllBytes($SavedPassFile, $EncBytes)
            Write-Host "✅ 密码已安全保存在 Windows 用户保护区，后续同步将全自动免密！" -ForegroundColor Green
        } catch {}
    }
    Write-Host "====================================================`n" -ForegroundColor Cyan

    return $PlainPass
}

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
if ((Test-Path $VaultEnc) -and $OpenSSL) {
    $VaultPass = Get-VaultPass -Auto:$Auto -ResetPass:$ResetPass
    if ($VaultPass) {
        Log-Message "正在解密隐私数据包 (vault.enc)..."
        $TempTar = Join-Path $env:TEMP "rime_vault_dec.tar.gz"
        try {
            $VaultPass | & $OpenSSL enc -d -aes-256-cbc -salt -pbkdf2 -pass stdin -in $VaultEnc -out $TempTar 2>$null
            if (Test-Path $TempTar) {
                tar -xzf $TempTar -C $ScriptDir 2>$null
                Remove-Item -Path $TempTar -Force -ErrorAction SilentlyContinue
                Log-Message "✅ 隐私短语与词频解密提取成功！"
            }
        } catch {}
    }
}

# 2. 检查并应用从 Git 同步过来的最新配置文件、Lua 插件与系统短语
$ConfigUpdated = $false

$RepoLua = Join-Path $ScriptDir "lua"
if (Test-Path $RepoLua) {
    $DstLua = Join-Path $RimeDir "lua"
    if (-not (Test-Path $DstLua)) { New-Item -ItemType Directory -Path $DstLua -Force | Out-Null }
    Copy-Item -Path (Join-Path $RepoLua "*") -Destination $DstLua -Recurse -Force -ErrorAction SilentlyContinue
    $ConfigUpdated = $true
}

$RepoSnippetsYaml = Join-Path $ScriptDir "snippets.yaml"
$RimeSnippetsYaml = Join-Path $RimeDir "snippets.yaml"
if (Test-Path $RepoSnippetsYaml) {
    if ((-not (Test-Path $RimeSnippetsYaml)) -or ((Get-FileHash $RepoSnippetsYaml).Hash -ne (Get-FileHash $RimeSnippetsYaml).Hash)) {
        Log-Message "检测到代码片段库更新: snippets.yaml，正在应用..."
        Copy-Item -Path $RepoSnippetsYaml -Destination $RimeSnippetsYaml -Force
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
if ($OpenSSL) {
    $VaultPass = Get-VaultPass -Auto:$Auto -ResetPass:$ResetPass
    if ($VaultPass) {
        $TempTar = Join-Path $env:TEMP "rime_vault.tar.gz"
        try {
            Push-Location $ScriptDir
            tar -czf $TempTar custom_phrase.txt sync 2>$null
            if (Test-Path $TempTar) {
                $VaultPass | & $OpenSSL enc -aes-256-cbc -salt -pbkdf2 -pass stdin -in $TempTar -out $VaultEnc 2>$null
                Remove-Item -Path $TempTar -Force -ErrorAction SilentlyContinue
                Log-Message "🔒 隐私短语与词频已成功通过 AES-256 加密打包 (vault.enc)！"
            }
            Pop-Location
        } catch {}
    }
}

# 4. 提交并推送到 GitHub (仅提交密文包与脱敏模板)
if (Test-Path (Join-Path $ScriptDir ".git")) {
    Push-Location $ScriptDir
    git add vault.enc custom_phrase.example.txt snippets.yaml 2>$null
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
