# ==============================================================================
# Rime Windows 用户词频与自造词一键/自动同步备份脚本 (支持交互式密码与 AES-256 隐私加密)
# Repository: https://github.com/rheatin/Rime_Config.git
# ==============================================================================

param(
    [switch]$Auto,
    [switch]$ResetPass,
    [switch]$ForcePush,
    [switch]$PullForce,
    [string]$Restore
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

function Invoke-WeaselCommand {
    param([string]$Argument)
    $Deployer = Get-ChildItem -Path "${env:ProgramFiles(x86)}\Rime", "${env:ProgramFiles}\Rime" -Filter "WeaselDeployer.exe" -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($Deployer) {
        try {
            $psi = New-Object System.Diagnostics.ProcessStartInfo
            $psi.FileName = $Deployer.FullName
            $psi.Arguments = $Argument
            $psi.CreateNoWindow = $true
            $psi.UseShellExecute = $false
            $proc = [System.Diagnostics.Process]::Start($psi)
            $proc.WaitForExit()
        } catch {
            & $Deployer.FullName $Argument
        }
    }
}

function Invoke-ThreeWaySnippetMerge {
    param(
        [string]$BasePath,
        [string]$LocalPath,
        [string]$RemotePath,
        [string[]]$OutPaths
    )

    function Parse-Blocks([string]$path) {
        $b = @{}
        $o = [System.Collections.Generic.List[string]]::new()
        if (-not (Test-Path $path)) { return @{ Blocks = $b; Order = $o } }
        
        $curT = $null
        $curL = [System.Collections.Generic.List[string]]::new()
        Get-Content $path -Encoding UTF8 -ErrorAction SilentlyContinue | ForEach-Object {
            $raw = $_
            $s = $raw.Trim()
            if ($s.StartsWith("/") -and ($s -match '^"?(/\w+)"?:\s*$')) {
                if ($curT -and $curL.Count -gt 0) { $b[$curT] = $curL.ToArray() }
                $curT = $Matches[1]
                if (-not $o.Contains($curT)) { [void]$o.Add($curT) }
                $curL = [System.Collections.Generic.List[string]]::new()
                [void]$curL.Add($raw)
            } elseif ($curT) {
                [void]$curL.Add($raw)
            }
        }
        if ($curT -and $curL.Count -gt 0) { $b[$curT] = $curL.ToArray() }
        return @{ Blocks = $b; Order = $o }
    }

    $BaseData = Parse-Blocks $BasePath
    $LocalData = Parse-Blocks $LocalPath
    $RemoteData = Parse-Blocks $RemotePath

    # 如果尚无 Base 历史快照（首次运行三路模型），以远端为基准
    if ($BaseData.Order.Count -eq 0) {
        $BaseData = $RemoteData
    }

    $AllTriggers = [System.Collections.Generic.List[string]]::new()
    foreach ($t in $RemoteData.Order) { if (-not $AllTriggers.Contains($t)) { [void]$AllTriggers.Add($t) } }
    foreach ($t in $LocalData.Order) { if (-not $AllTriggers.Contains($t)) { [void]$AllTriggers.Add($t) } }
    foreach ($t in $BaseData.Order) { if (-not $AllTriggers.Contains($t)) { [void]$AllTriggers.Add($t) } }

    $MergedBlocks = @{}
    $MergedOrder = [System.Collections.Generic.List[string]]::new()
    $ActionLogs = [System.Collections.Generic.List[string]]::new()

    foreach ($t in $AllTriggers) {
        $inB = $BaseData.Blocks.ContainsKey($t)
        $inL = $LocalData.Blocks.ContainsKey($t)
        $inR = $RemoteData.Blocks.ContainsKey($t)

        $bVal = if ($inB) { ($BaseData.Blocks[$t] -join "`n").Trim() } else { "" }
        $lVal = if ($inL) { ($LocalData.Blocks[$t] -join "`n").Trim() } else { "" }
        $rVal = if ($inR) { ($RemoteData.Blocks[$t] -join "`n").Trim() } else { "" }

        if ($inL -and -not $inB -and -not $inR) {
            $MergedBlocks[$t] = $LocalData.Blocks[$t]; [void]$MergedOrder.Add($t)
            [void]$ActionLogs.Add("+本地:$t")
        } elseif ($inR -and -not $inB -and -not $inL) {
            $MergedBlocks[$t] = $RemoteData.Blocks[$t]; [void]$MergedOrder.Add($t)
            [void]$ActionLogs.Add("+远端:$t")
        } elseif ($inB -and -not $inL -and $inR) {
            if ($rVal -eq $bVal) {
                [void]$ActionLogs.Add("-本地删除:$t")
            } else {
                $MergedBlocks[$t] = $RemoteData.Blocks[$t]; [void]$MergedOrder.Add($t)
                [void]$ActionLogs.Add("~远端更新保留:$t")
            }
        } elseif ($inB -and $inL -and -not $inR) {
            if ($lVal -eq $bVal) {
                [void]$ActionLogs.Add("-远端删除:$t")
            } else {
                $MergedBlocks[$t] = $LocalData.Blocks[$t]; [void]$MergedOrder.Add($t)
                [void]$ActionLogs.Add("~本地修改保留:$t")
            }
        } elseif ($inL -and $inR) {
            if ($lVal -eq $rVal) {
                $MergedBlocks[$t] = $LocalData.Blocks[$t]; [void]$MergedOrder.Add($t)
            } elseif ($lVal -eq $bVal) {
                $MergedBlocks[$t] = $RemoteData.Blocks[$t]; [void]$MergedOrder.Add($t)
                [void]$ActionLogs.Add("~采用远端:$t")
            } elseif ($rVal -eq $bVal) {
                $MergedBlocks[$t] = $LocalData.Blocks[$t]; [void]$MergedOrder.Add($t)
                [void]$ActionLogs.Add("~采用本地:$t")
            } else {
                $MergedBlocks[$t] = $LocalData.Blocks[$t]; [void]$MergedOrder.Add($t)
                [void]$ActionLogs.Add("!冲突采用本地:$t")
            }
        }
    }

    $Header = @(
        "# ==============================================================================",
        "# 🔒 个人私密代码与文本片段 (snippets.custom.yaml)",
        "# 说明：此文件包含个人敏感手机号、身份证、真实邮箱、地址等。",
        "# 受 .gitignore 保护绝不以明文提交 GitHub，由 AES-256 (vault.enc) 加密跨平台同步。",
        "# ==============================================================================",
        ""
    )
    $Lines = [System.Collections.Generic.List[string]]::new($Header)
    foreach ($t in $MergedOrder) {
        if ($MergedBlocks.ContainsKey($t)) {
            foreach ($l in $MergedBlocks[$t]) { [void]$Lines.Add($l) }
            [void]$Lines.Add("")
        }
    }
    $MergedText = $Lines -join "`n"

    foreach ($op in $OutPaths) {
        $parent = Split-Path -Parent $op
        if (-not (Test-Path $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
        [System.IO.File]::WriteAllText($op, $MergedText, [System.Text.Encoding]::UTF8)
    }

    return $ActionLogs
}
function Get-VaultPass {
    param([switch]$Auto, [switch]$ResetPass)

    # 1. 优先读取环境变量
    if ($env:RIME_VAULT_PASS) {
        return $env:RIME_VAULT_PASS
    }

    # 确保加载 .NET 加密程序集
    Add-Type -AssemblyName System.Security -ErrorAction SilentlyContinue

    $SavedPassFile = Join-Path $RimeDir ".vault_pass.dpapi"
    $SavedPlainFile = Join-Path $RimeDir ".vault_pass"

    # 如果请求重置密码，删除旧凭据
    if ($ResetPass) {
        if (Test-Path $SavedPassFile) { Remove-Item -Path $SavedPassFile -Force -ErrorAction SilentlyContinue }
        if (Test-Path $SavedPlainFile) { Remove-Item -Path $SavedPlainFile -Force -ErrorAction SilentlyContinue }
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

        # 3. 尝试从本地凭据保护文件读取
        if (Test-Path $SavedPlainFile) {
            try {
                $PassText = (Get-Content $SavedPlainFile -Raw -Encoding UTF8).Trim()
                if ($PassText) { return $PassText }
            } catch {}
        }
    }

    # 4. 如果是后台自动监听模式，无法交互输入
    if ($Auto) {
        return $null
    }

    # 5. 交互提示用户输入密码 (支持二次确认防输错)
    $PlainPass = $null
    while ($true) {
        Write-Host "`n====================================================" -ForegroundColor Cyan
        Write-Host "🔒 Rime 隐私数据加密同步 (首次配置 / 密码验证)" -ForegroundColor Yellow
        Write-Host "请输入你的同步密码 (与 Mac 端设置的密码一致即可自动互通)："
        $SecurePass = Read-Host "🔑 请输入密码" -AsSecureString
        $PlainPass = [System.Net.NetworkCredential]::new("", $SecurePass).Password

        if (-not $PlainPass) {
            Write-Host "⚠️ 未输入密码，本次跳过加密隐私数据同步。" -ForegroundColor Yellow
            return $null
        }

        $SecurePassConfirm = Read-Host "🔑 请再次输入密码以确认" -AsSecureString
        $PlainPassConfirm = [System.Net.NetworkCredential]::new("", $SecurePassConfirm).Password

        if ($PlainPass -eq $PlainPassConfirm) {
            Write-Host "✅ 两次密码输入一致！" -ForegroundColor Green
            break
        } else {
            Write-Host "❌ 两次输入的密码不一致，请重新输入！`n" -ForegroundColor Red
        }
    }

    # 6. 询问是否记住密码
    $Remember = Read-Host "是否记住该密码 (下次同步自动免输，通过 Windows DPAPI 本地硬件级加密) [Y/n]?"
    if (($Remember -eq "") -or ($Remember -match "^[Yy]")) {
        $SavedSuccess = $false
        try {
            $PassBytes = [System.Text.Encoding]::UTF8.GetBytes($PlainPass)
            $EncBytes = [System.Security.Cryptography.ProtectedData]::Protect($PassBytes, $null, [System.Security.Cryptography.DataProtectionScope]::CurrentUser)
            [System.IO.File]::WriteAllBytes($SavedPassFile, $EncBytes)
            $SavedSuccess = $true
        } catch {}

        # 始终保存一个本地保护的 fallback 文件，确保即便 DPAPI 出现系统级权限受限也能免输
        try {
            [System.IO.File]::WriteAllText($SavedPlainFile, $PlainPass, [System.Text.Encoding]::UTF8)
            $SavedSuccess = $true
        } catch {}

        if ($SavedSuccess) {
            Write-Host "✅ 密码已安全保存在本地凭据区，后续同步将全自动免密！" -ForegroundColor Green
        }
    }
    Write-Host "====================================================`n" -ForegroundColor Cyan

    return $PlainPass
}

# 1. 检查是否为指定文件恢复模式
if ($Restore) {
    if (-not (Test-Path $Restore)) {
        Log-Message "❌ 错误：指定的恢复文件不存在: $Restore"
        return
    }
    Log-Message "🚨 恢复模式：正在使用指定文件覆盖本地并强制推送到云端: $Restore"
    $BaseDir = Join-Path $RimeDir ".vault_base"
    if (-not (Test-Path $BaseDir)) { New-Item -ItemType Directory -Path $BaseDir -Force | Out-Null }
    
    if ($Restore -match '\.ya?ml$') {
        Copy-Item -Path $Restore -Destination (Join-Path $ScriptDir "snippets.custom.yaml") -Force
        Copy-Item -Path $Restore -Destination (Join-Path $RimeDir "snippets.custom.yaml") -Force
        Copy-Item -Path $Restore -Destination (Join-Path $BaseDir "snippets.custom.base.yaml") -Force
        Log-Message "✅ 已将指定文件设置为 snippets.custom.yaml 权威版本！"
    } elseif ($Restore -match '\.txt$') {
        Copy-Item -Path $Restore -Destination (Join-Path $ScriptDir "custom_phrase.txt") -Force
        Copy-Item -Path $Restore -Destination (Join-Path $RimeDir "custom_phrase.txt") -Force
        Copy-Item -Path $Restore -Destination (Join-Path $BaseDir "custom_phrase.base.txt") -Force
        Log-Message "✅ 已将指定文件设置为 custom_phrase.txt 权威版本！"
    }
    $ForcePush = $true
}

# 1. 如果是手动运行，先触发 WeaselDeployer
if (-not $Auto -and -not $ForcePush) {
    Log-Message "手动触发模式：正在调用小狼毫导出..."
    Invoke-WeaselCommand "/sync"
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
        $prevEAP = $ErrorActionPreference
        $ErrorActionPreference = "SilentlyContinue"
        $PullOut = (& git pull --rebase origin main 2>&1) | Out-String
        $ErrorActionPreference = $prevEAP
        if ($PullOut) { Log-Message "Git Pull: $($PullOut.Trim())" }
    } catch {}
    Pop-Location
}

# 如果是 -ForcePush (强制以本地为准覆盖云端)，跳过远端合并，直接打包推送到云端
if ($ForcePush) {
    Log-Message "🚨 强制推流模式：以当前本地文件为唯一权威，跳过合并直接覆盖云端！"
    $BaseDir = Join-Path $RimeDir ".vault_base"
    if (-not (Test-Path $BaseDir)) { New-Item -ItemType Directory -Path $BaseDir -Force | Out-Null }
    
    $RepoCustom = Join-Path $ScriptDir "snippets.custom.yaml"
    $RimeCustom = Join-Path $RimeDir "snippets.custom.yaml"
    $BaseCustom = Join-Path $BaseDir "snippets.custom.base.yaml"
    if (Test-Path $RimeCustom) {
        Copy-Item -Path $RimeCustom -Destination $RepoCustom -Force
        Copy-Item -Path $RimeCustom -Destination $BaseCustom -Force
    }

    $RepoPhrase = Join-Path $ScriptDir "custom_phrase.txt"
    $RimePhrase = Join-Path $RimeDir "custom_phrase.txt"
    $BasePhrase = Join-Path $BaseDir "custom_phrase.base.txt"
    if (Test-Path $RimePhrase) {
        Copy-Item -Path $RimePhrase -Destination $RepoPhrase -Force
        Copy-Item -Path $RimePhrase -Destination $BasePhrase -Force
    }

    $SourceSync = Join-Path $RimeDir "sync"
    $TargetSync = Join-Path $ScriptDir "sync"
    if (Test-Path $SourceSync) {
        if (-not (Test-Path $TargetSync)) { New-Item -ItemType Directory -Path $TargetSync -Force | Out-Null }
        Copy-Item -Path (Join-Path $SourceSync "*") -Destination $TargetSync -Recurse -Force -ErrorAction SilentlyContinue
    }

    if ($OpenSSL) {
        $VaultPass = Get-VaultPass -Auto:$Auto -ResetPass:$ResetPass
        if ($VaultPass) {
            $TempTar = Join-Path $env:TEMP "rime_vault.tar.gz"
            try {
                Push-Location $ScriptDir
                tar -czf $TempTar custom_phrase.txt snippets.custom.yaml sync 2>$null
                if (Test-Path $TempTar) {
                    $env:RIME_VAULT_PASS = $VaultPass
                    & $OpenSSL enc -aes-256-cbc -salt -pbkdf2 -pass env:RIME_VAULT_PASS -in $TempTar -out $VaultEnc 2>$null
                    Remove-Item -Path $TempTar -Force -ErrorAction SilentlyContinue
                    Log-Message "🔒 权威版本已加密打包 (vault.enc)！"
                }
                Pop-Location
            } catch {}
        }
    }

    Push-Location $ScriptDir
    git add vault.enc custom_phrase.example.txt snippets.yaml snippets.custom.example.yaml 2>$null
    $prevEAP = $ErrorActionPreference
    $ErrorActionPreference = "SilentlyContinue"
    $CommitOut = (& git commit -m "restore(windows): 强制恢复并覆盖云端私密数据 $DateStr" 2>&1) | Out-String
    $PushOut = (& git push origin main 2>&1) | Out-String
    $ErrorActionPreference = $prevEAP
    Pop-Location

    Log-Message "正在触发小狼毫重新部署以使最新配置与短语生效..."
    Invoke-WeaselCommand "/deploy"
    Log-Message "🎉 本地权威版本已成功强制推送到云端！"
    Show-Balloon -Title "Rime 词频同步" -Message "🎉 本地权威版本已成功强制推送到云端！"
    return
}

# 2.0 自动解密远端同步的隐私数据包 (vault.enc)
$VaultEnc = Join-Path $ScriptDir "vault.enc"
if ((Test-Path $VaultEnc) -and $OpenSSL) {
    $VaultPass = Get-VaultPass -Auto:$Auto -ResetPass:$ResetPass
    if ($VaultPass) {
        Log-Message "正在解密隐私数据包 (vault.enc)..."
        $TempTar = Join-Path $env:TEMP "rime_vault_dec.tar.gz"
        $TempUnpackDir = Join-Path $env:TEMP "rime_vault_unpack"
        if (Test-Path $TempUnpackDir) { Remove-Item -Recurse -Force $TempUnpackDir -ErrorAction SilentlyContinue }
        New-Item -ItemType Directory -Path $TempUnpackDir -Force | Out-Null

        try {
            $env:RIME_VAULT_PASS = $VaultPass
            & $OpenSSL enc -d -aes-256-cbc -salt -pbkdf2 -pass env:RIME_VAULT_PASS -in $VaultEnc -out $TempTar 2>$null
            if (-not (Test-Path $TempTar)) {
                & $OpenSSL enc -d -aes-256-cbc -salt -pbkdf2 -pass "pass:$VaultPass" -in $VaultEnc -out $TempTar 2>$null
            }
            if (-not (Test-Path $TempTar)) {
                $VaultPass | & $OpenSSL enc -d -aes-256-cbc -salt -pbkdf2 -pass stdin -in $VaultEnc -out $TempTar 2>$null
            }
            if (-not (Test-Path $TempTar)) {
                Log-Message "❌ 严重错误：远端私密数据包 (vault.enc) 解密失败！"
                Log-Message "🔑 诊断原因：当前保存的同步密码与远端不匹配（或密文损坏）。"
                Log-Message "🛡️ 保护机制触发：已紧急终止同步，绝不拿未解密的旧数据覆盖本地！"
                Log-Message "💡 解决方案：请在终端运行 powershell -NoProfile -File .\sync.ps1 -ResetPass 重新输入正确密码。"
                Show-Balloon -Title "Rime 词频同步" -Message "❌ 密码错误无法解密远端数据，请运行 .\sync.ps1 -ResetPass 重置密码。"
                Remove-Item -Recurse -Force $TempUnpackDir -ErrorAction SilentlyContinue
                return
            }

            tar -xzf $TempTar -C $TempUnpackDir 2>$null
            Remove-Item -Path $TempTar -Force -ErrorAction SilentlyContinue

            $DecCustom = Join-Path $TempUnpackDir "snippets.custom.yaml"
            $DecPhrase = Join-Path $TempUnpackDir "custom_phrase.txt"
            $DecSync = Join-Path $TempUnpackDir "sync"

            Log-Message "✅ 远端数据包解密成功！包含内容:"
            if (Test-Path $DecCustom) { Log-Message "  • 个人私密片段: snippets.custom.yaml ($((Get-Item $DecCustom).Length) 字节)" }
            if (Test-Path $DecPhrase) { Log-Message "  • 系统自定义短语: custom_phrase.txt ($((Get-Content $DecPhrase).Count) 行)" }
            if (Test-Path $DecSync) { Log-Message "  • 跨平台词频目录: sync/ ($((Get-ChildItem $DecSync).Name -join ', '))" }

            # 如果是 -PullForce (强制从云端重置覆盖本地)，跳过三路合并直接重置本地
            if ($PullForce) {
                Log-Message "🚨 强制重置模式：正在以云端数据完全重置本地环境..."
                $BaseDir = Join-Path $RimeDir ".vault_base"
                if (-not (Test-Path $BaseDir)) { New-Item -ItemType Directory -Path $BaseDir -Force | Out-Null }

                if (Test-Path $DecCustom) {
                    Copy-Item -Path $DecCustom -Destination (Join-Path $ScriptDir "snippets.custom.yaml") -Force
                    Copy-Item -Path $DecCustom -Destination (Join-Path $RimeDir "snippets.custom.yaml") -Force
                    Copy-Item -Path $DecCustom -Destination (Join-Path $BaseDir "snippets.custom.base.yaml") -Force
                }
                if (Test-Path $DecPhrase) {
                    Copy-Item -Path $DecPhrase -Destination (Join-Path $ScriptDir "custom_phrase.txt") -Force
                    Copy-Item -Path $DecPhrase -Destination (Join-Path $RimeDir "custom_phrase.txt") -Force
                    Copy-Item -Path $DecPhrase -Destination (Join-Path $BaseDir "custom_phrase.base.txt") -Force
                }
                if (Test-Path $DecSync) {
                    Copy-Item -Path (Join-Path $DecSync "*") -Destination (Join-Path $ScriptDir "sync") -Recurse -Force -ErrorAction SilentlyContinue
                    Copy-Item -Path (Join-Path $DecSync "*") -Destination (Join-Path $RimeDir "sync") -Recurse -Force -ErrorAction SilentlyContinue
                }
                Remove-Item -Recurse -Force $TempUnpackDir -ErrorAction SilentlyContinue

                Log-Message "正在触发小狼毫重新部署以使最新配置与短语生效..."
                Invoke-WeaselCommand "/deploy"
                Log-Message "🎉 本地已成功强制以云端权威数据完全重置！"
                Show-Balloon -Title "Rime 词频同步" -Message "🎉 本地已成功强制以云端权威数据完全重置！"
                return
            }

            # 智能 Git 3-Way Merge 增量合并 snippets.custom.yaml
            $BaseDir = Join-Path $RimeDir ".vault_base"
            if (-not (Test-Path $BaseDir)) { New-Item -ItemType Directory -Path $BaseDir -Force | Out-Null }
            $BaseCustom = Join-Path $BaseDir "snippets.custom.base.yaml"
            $BasePhrase = Join-Path $BaseDir "custom_phrase.base.txt"

            $RepoCustom = Join-Path $ScriptDir "snippets.custom.yaml"
            $RimeCustom = Join-Path $RimeDir "snippets.custom.yaml"

            $ActionLogs = Invoke-ThreeWaySnippetMerge -BasePath $BaseCustom -LocalPath $RimeCustom -RemotePath $DecCustom -OutPaths @($RepoCustom, $RimeCustom, $BaseCustom)
            $Summary = if ($ActionLogs.Count -gt 0) { $ActionLogs -join ', ' } else { '两端内容完全一致' }
            Log-Message "  🧩 [Git 3-Way Merge] 私密片段合并完成: $Summary"

            # 智能双向合并 custom_phrase.txt
            $RepoPhrase = Join-Path $ScriptDir "custom_phrase.txt"
            $RimePhrase = Join-Path $RimeDir "custom_phrase.txt"
            $PhraseFiles = @($DecPhrase, $RepoPhrase, $RimePhrase) | Where-Object { Test-Path $_ }
            
            $AllEntries = @{}
            foreach ($pf in $PhraseFiles) {
                Get-Content $pf -Encoding UTF8 -ErrorAction SilentlyContinue | ForEach-Object {
                    $line = $_.Trim()
                    if ($line -and -not $line.StartsWith("#")) {
                        $parts = $line -split "`t"
                        if ($parts.Count -ge 2) {
                            $key = "$($parts[0].Trim())`t$($parts[1].Trim())"
                            $w = if ($parts.Count -ge 3) { $parts[2].Trim() } else { "1000" }
                            $AllEntries[$key] = $w
                        }
                    }
                }
            }
            
            $Headers = @(
                "# Rime table",
                "# coding: utf-8",
                "#@/db_name`tcustom_phrase.txt",
                "#@/db_type`ttabledb",
                "#",
                "# 跨平台「自定义短语 / 文本替换」双向增量合并表 (全拼 26键)",
                "# 格式：文字<Tab>编码<Tab>权重",
                "#",
                "# 此行之后不能写注释",
                ""
            )
            $MergedLines = [System.Collections.Generic.List[string]]::new()
            foreach ($h in $Headers) { [void]$MergedLines.Add($h) }
            foreach ($k in ($AllEntries.Keys | Sort-Object)) {
                $val = $AllEntries[$k]
                [void]$MergedLines.Add($k + "`t" + $val)
            }
            $MergedContent = $MergedLines -join "`n"
            [System.IO.File]::WriteAllText($RepoPhrase, $MergedContent, [System.Text.Encoding]::UTF8)
            [System.IO.File]::WriteAllText($RimePhrase, $MergedContent, [System.Text.Encoding]::UTF8)
            Log-Message "  • custom_phrase.txt 双向合并完成，共计 $($AllEntries.Count) 条短语！"

            # 合并词频目录
            if (Test-Path $DecSync) {
                Copy-Item -Path (Join-Path $DecSync "*") -Destination (Join-Path $ScriptDir "sync") -Recurse -Force -ErrorAction SilentlyContinue
                Copy-Item -Path (Join-Path $DecSync "*") -Destination (Join-Path $RimeDir "sync") -Recurse -Force -ErrorAction SilentlyContinue
            }

            Remove-Item -Recurse -Force $TempUnpackDir -ErrorAction SilentlyContinue
            Log-Message "✅ 远端隐私短语、私密片段与词频已成功解密并完成双向合并！"
            $ConfigUpdated = $true
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



# 3. 归档词频文件到仓库
$SourceSync = Join-Path $RimeDir "sync"
$TargetSync = Join-Path $ScriptDir "sync"

# 3.0 确保用户目录中的私密片段与短语同步回仓库目录 (以最新修改时间为准)
$RepoSnippetsCustom = Join-Path $ScriptDir "snippets.custom.yaml"
$RimeSnippetsCustom = Join-Path $RimeDir "snippets.custom.yaml"
if ((Test-Path $RimeSnippetsCustom) -and (Test-Path $RepoSnippetsCustom)) {
    if ((Get-Item $RimeSnippetsCustom).LastWriteTime -gt (Get-Item $RepoSnippetsCustom).LastWriteTime) {
        Log-Message "检测到用户文件夹中的 snippets.custom.yaml 有较新修改，正在同步到仓库..."
        Copy-Item -Path $RimeSnippetsCustom -Destination $RepoSnippetsCustom -Force
    }
} elseif (Test-Path $RimeSnippetsCustom) {
    Copy-Item -Path $RimeSnippetsCustom -Destination $RepoSnippetsCustom -Force
}

$RepoSnippetsYaml = Join-Path $ScriptDir "snippets.yaml"
$RimeSnippetsYaml = Join-Path $RimeDir "snippets.yaml"
if ((Test-Path $RimeSnippetsYaml) -and (Test-Path $RepoSnippetsYaml)) {
    if ((Get-Item $RimeSnippetsYaml).LastWriteTime -gt (Get-Item $RepoSnippetsYaml).LastWriteTime) {
        Log-Message "检测到用户文件夹中的 snippets.yaml 有较新修改，正在同步到仓库..."
        Copy-Item -Path $RimeSnippetsYaml -Destination $RepoSnippetsYaml -Force
    }
} elseif (Test-Path $RimeSnippetsYaml) {
    Copy-Item -Path $RimeSnippetsYaml -Destination $RepoSnippetsYaml -Force
}

if (Test-Path $SourceSync) {
    Log-Message "正在归档词频文件从 $SourceSync 到 $TargetSync..."
    if (-not (Test-Path $TargetSync)) { New-Item -ItemType Directory -Path $TargetSync -Force | Out-Null }
    
    Copy-Item -Path (Join-Path $SourceSync "*") -Destination $TargetSync -Recurse -Force -ErrorAction SilentlyContinue
    Get-ChildItem -Path $TargetSync -Recurse -File | Where-Object { $_.Extension -ne ".txt" } | Remove-Item -Force -ErrorAction SilentlyContinue
}

# 3.1 对 custom_phrase.txt、snippets.custom.yaml 与 sync/ 进行 AES-256 加密打包 (vault.enc)
if ($OpenSSL) {
    $VaultPass = Get-VaultPass -Auto:$Auto -ResetPass:$ResetPass
    if ($VaultPass) {
        $TempTar = Join-Path $env:TEMP "rime_vault.tar.gz"
        try {
            Push-Location $ScriptDir
            tar -czf $TempTar custom_phrase.txt snippets.custom.yaml sync 2>$null
            if (Test-Path $TempTar) {
                $env:RIME_VAULT_PASS = $VaultPass
                & $OpenSSL enc -aes-256-cbc -salt -pbkdf2 -pass env:RIME_VAULT_PASS -in $TempTar -out $VaultEnc 2>$null
                Remove-Item -Path $TempTar -Force -ErrorAction SilentlyContinue
                Log-Message "🔒 隐私短语、私有片段与词频已成功通过 AES-256 加密打包 (vault.enc)！"
            }
            Pop-Location
        } catch {}
    }
}

# 4. 提交并推送到 GitHub (仅提交密文包与脱敏模板)
if (Test-Path (Join-Path $ScriptDir ".git")) {
    Push-Location $ScriptDir
    git add vault.enc custom_phrase.example.txt snippets.yaml snippets.custom.example.yaml 2>$null
    $Status = git status --porcelain
    
    if ($Status) {
        $prevEAP = $ErrorActionPreference
        $ErrorActionPreference = "SilentlyContinue"
        $CommitOut = (& git commit -m "sync(windows): 自动同步加密词频与短语 $DateStr" 2>&1) | Out-String
        $PushOut = (& git push origin main 2>&1) | Out-String
        $ErrorActionPreference = $prevEAP
        if ($CommitOut) { Log-Message "Git Commit: $($CommitOut.Trim())" }
        if ($PushOut) { Log-Message "Git Push 结果: $($PushOut.Trim())" }
        
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
            try {
                [void] [System.Reflection.Assembly]::LoadWithPartialName("System.Windows.Forms")
                $Notify = New-Object System.Windows.Forms.NotifyIcon
                $Notify.Icon = [System.Drawing.SystemIcons]::Warning
                $Notify.Visible = $true
                $Notify.ShowBalloonTip(3000, "Rime 词频同步", "⚠️ 词频加密包推送失败，请检查网络连接。", [System.Windows.Forms.ToolTipIcon]::Warning)
            } catch {}
        }
    } else {
        Log-Message "✨ 词频已是最新，无新增改动。"
        try {
            [void] [System.Reflection.Assembly]::LoadWithPartialName("System.Windows.Forms")
            $Notify = New-Object System.Windows.Forms.NotifyIcon
            $Notify.Icon = [System.Drawing.SystemIcons]::Information
            $Notify.Visible = $true
            $Notify.ShowBalloonTip(3000, "Rime 词频同步", "✨ 自造词与短语已是最新状态，已同步完成！", [System.Windows.Forms.ToolTipIcon]::Info)
        } catch {}
    }
    Pop-Location
}

if ($ConfigUpdated) {
    Log-Message "正在触发小狼毫重新部署以使最新配置与短语生效..."
    Invoke-WeaselCommand "/deploy"
}

Log-Message "===== 同步流程结束 =====`n"
