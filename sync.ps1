# ==============================================================================
# Rime Windows 用户词频与自造词一键/自动同步备份脚本 (支持交互式密码与 AES-256 隐私加密)
# Repository: https://github.com/rheatin/Rime_Config.git
# ==============================================================================

param(
    [switch]$Auto,
    [switch]$ResetPass,
    [switch]$ForcePush,
    [switch]$PullForce,
    [string]$Restore,
    [switch]$VerboseLog,
    [switch]$v
)

$ErrorActionPreference = "Continue"

if ($v) { $VerboseLog = $true }

$LogFile = Join-Path $env:TEMP "rime_sync.log"
$DateStr = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

function Log-Message {
    param([string]$Msg)
    $Line = "[$DateStr] $Msg"
    Add-Content -Path $LogFile -Value $Line -ErrorAction SilentlyContinue
    Write-Host $Msg
}

function Log-Verbose {
    param([string]$Msg)
    $Line = "[$DateStr] [VERBOSE] $Msg"
    Add-Content -Path $LogFile -Value $Line -ErrorAction SilentlyContinue
    if ($VerboseLog) {
        Write-Host "🔍 [VERBOSE] $Msg" -ForegroundColor DarkCyan
    }
}

Log-Message "===== 开始执行 Rime 词频同步 (Auto=$Auto, Verbose=$VerboseLog) ====="

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
if (-not $ScriptDir) { $ScriptDir = Join-Path $env:USERPROFILE "Rime_Config" }
$RimeDir = Join-Path $env:APPDATA "Rime"

Log-Verbose "本地仓库路径 (ScriptDir): $ScriptDir"
Log-Verbose "小狼毫用户目录 (RimeDir): $RimeDir"

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
Log-Verbose "OpenSSL 可执行文件路径: $OpenSSL"

function Show-Balloon {
    param([string]$Title = "Rime 词频同步", [string]$Message = "", [string]$Icon = "Info")
    try {
        [void] [System.Reflection.Assembly]::LoadWithPartialName("System.Windows.Forms")
        $Notify = New-Object System.Windows.Forms.NotifyIcon
        $Notify.Icon = [System.Drawing.SystemIcons]::Information
        $Notify.Visible = $true
        $Notify.ShowBalloonTip(3000, $Title, $Message, [System.Windows.Forms.ToolTipIcon]::$Icon)
    } catch {}
}

function Invoke-WeaselCommand {
    param([string]$Argument)
    $Deployer = Get-ChildItem -Path "${env:ProgramFiles(x86)}\Rime", "${env:ProgramFiles}\Rime" -Filter "WeaselDeployer.exe" -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($Deployer) {
        Log-Verbose "正在调用 WeaselDeployer: $($Deployer.FullName) $Argument"
        try {
            $psi = New-Object System.Diagnostics.ProcessStartInfo
            $psi.FileName = $Deployer.FullName
            $psi.Arguments = $Argument
            $psi.CreateNoWindow = $true
            $psi.UseShellExecute = $false
            $proc = [System.Diagnostics.Process]::Start($psi)
            $proc.WaitForExit()
            Log-Verbose "WeaselDeployer $Argument 执行完成，退出码: $($proc.ExitCode)"
        } catch {
            & $Deployer.FullName $Argument
        }
    } else {
        Log-Message "⚠️ 未找到 WeaselDeployer.exe，跳过小狼毫内部命令触发。"
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

    # 如果尚无 Base 历史快照（首次运行三路模型），以拉取前的本地为初始基准，让远端新改动顺利采纳
    if ($BaseData.Order.Count -eq 0) {
        $BaseData = $LocalData
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
                # 双方均有修改冲突，优先采纳远端带来的新条目
                $MergedBlocks[$t] = $RemoteData.Blocks[$t]
                [void]$MergedOrder.Add($t)
                [void]$ActionLogs.Add("!冲突采用远端:$t")
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
    $Lines = [System.Collections.Generic.List[string]]::new()
    foreach ($h in $Header) { [void]$Lines.Add($h) }
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
        Log-Verbose "已写入 Snippets 目标: $op"
    }

    return $ActionLogs
}

# 获取同步密码 (支持交互式输入、Windows DPAPI 本地安全保护记忆与免输)
function Get-VaultPass {
    param([switch]$Auto, [switch]$ResetPass)

    if ($env:RIME_VAULT_PASS) {
        Log-Verbose "从环境变量读取到 RIME_VAULT_PASS (长度: $($env:RIME_VAULT_PASS.Length))"
        return $env:RIME_VAULT_PASS
    }

    Add-Type -AssemblyName System.Security -ErrorAction SilentlyContinue

    $SavedPassFile = Join-Path $RimeDir ".vault_pass.dpapi"
    $SavedPlainFile = Join-Path $RimeDir ".vault_pass"

    if ($ResetPass) {
        Log-Verbose "检测到 -ResetPass 参数，正在清除本地旧密码凭据缓存..."
        if (Test-Path $SavedPassFile) { Remove-Item -Path $SavedPassFile -Force -ErrorAction SilentlyContinue }
        if (Test-Path $SavedPlainFile) { Remove-Item -Path $SavedPlainFile -Force -ErrorAction SilentlyContinue }
    } else {
        if (Test-Path $SavedPassFile) {
            try {
                $EncBytes = [System.IO.File]::ReadAllBytes($SavedPassFile)
                $DecBytes = [System.Security.Cryptography.ProtectedData]::Unprotect($EncBytes, $null, [System.Security.Cryptography.DataProtectionScope]::CurrentUser)
                $DecPass = [System.Text.Encoding]::UTF8.GetString($DecBytes)
                if ($DecPass) {
                    Log-Verbose "从 DPAPI 凭据安全提取密码成功 (长度: $($DecPass.Length))"
                    return $DecPass
                }
            } catch {
                Log-Verbose "从 DPAPI 提取密码异常: $_"
            }
        }

        if (Test-Path $SavedPlainFile) {
            try {
                $PassText = (Get-Content $SavedPlainFile -Raw -Encoding UTF8).Trim()
                if ($PassText) {
                    Log-Verbose "从本地安全回落文件读取密码成功 (长度: $($PassText.Length))"
                    return $PassText
                }
            } catch {}
        }
    }

    if ($Auto) {
        Log-Verbose "后台自动模式无法弹出交互输入，Get-VaultPass 返回 null"
        return $null
    }

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

    $Remember = Read-Host "是否记住该密码 (下次同步自动免输，通过 Windows DPAPI 本地硬件级加密) [Y/n]?"
    if (($Remember -eq "") -or ($Remember -match "^[Yy]")) {
        $SavedSuccess = $false
        try {
            $PassBytes = [System.Text.Encoding]::UTF8.GetBytes($PlainPass)
            $EncBytes = [System.Security.Cryptography.ProtectedData]::Protect($PassBytes, $null, [System.Security.Cryptography.DataProtectionScope]::CurrentUser)
            [System.IO.File]::WriteAllBytes($SavedPassFile, $EncBytes)
            $SavedSuccess = $true
        } catch {}

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

# 2. 如果是手动运行，先触发 WeaselDeployer 导出
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

# 3. 先拉取远端最新变更
if (Test-Path (Join-Path $ScriptDir ".git")) {
    Push-Location $ScriptDir
    try {
        $prevEAP = $ErrorActionPreference
        $ErrorActionPreference = "SilentlyContinue"
        $PullOut = (& git pull --rebase origin main 2>&1) | Out-String
        $ErrorActionPreference = $prevEAP
        if ($PullOut) { Log-Message "Git Pull: $($PullOut.Trim())" }
    } catch {
        Log-Verbose "Git Pull 异常: $_"
    }
    Pop-Location
}

# 4. 【关键步骤】立即将从 Git 拉取到的最新 Lua 扩展与配置文件复制到用户目录
$ConfigUpdated = $false

$RepoLua = Join-Path $ScriptDir "lua"
if (Test-Path $RepoLua) {
    $DstLua = Join-Path $RimeDir "lua"
    if (-not (Test-Path $DstLua)) { New-Item -ItemType Directory -Path $DstLua -Force | Out-Null }
    Copy-Item -Path (Join-Path $RepoLua "*") -Destination $DstLua -Recurse -Force -ErrorAction SilentlyContinue
    Log-Verbose "已同步最新 Lua 插件目录: $DstLua"
    $ConfigUpdated = $true
}

$RepoSnippetsYaml = Join-Path $ScriptDir "snippets.yaml"
$RimeSnippetsYaml = Join-Path $RimeDir "snippets.yaml"
if (Test-Path $RepoSnippetsYaml) {
    Copy-Item -Path $RepoSnippetsYaml -Destination $RimeSnippetsYaml -Force
    Log-Verbose "已同步公共 Snippets 模板: $RimeSnippetsYaml"
    $ConfigUpdated = $true
}

Get-ChildItem -Path $ScriptDir -Filter "*.custom.yaml" -File -ErrorAction SilentlyContinue | Where-Object { $_.Name -ne "squirrel.custom.yaml" -and $_.Name -ne "snippets.custom.yaml" } | ForEach-Object {
    $src = $_.FullName
    $dst = Join-Path $RimeDir $_.Name
    Copy-Item -Path $src -Destination $dst -Force
    Log-Verbose "已同步自定义配置文件: $($_.Name)"
    $ConfigUpdated = $true
}

Get-ChildItem -Path $ScriptDir -Filter "*.dict.yaml" -File -ErrorAction SilentlyContinue | ForEach-Object {
    $src = $_.FullName
    $dst = Join-Path $RimeDir $_.Name
    Copy-Item -Path $src -Destination $dst -Force
    Log-Verbose "已同步词典定义: $($_.Name)"
    $ConfigUpdated = $true
}

# 5. 如果是 -ForcePush (强制以本地为准覆盖云端)，跳过远端合并，直接打包推送到云端
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

# 6. 自动解密远端同步的隐私数据包 (vault.enc)
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
            Log-Verbose "调用 OpenSSL 尝试解密 $VaultEnc ..."
            & $OpenSSL enc -d -aes-256-cbc -salt -pbkdf2 -pass env:RIME_VAULT_PASS -in $VaultEnc -out $TempTar 2>$null
            if (-not (Test-Path $TempTar)) {
                Log-Verbose "env: 传参未产出文件，尝试 pass: 传参..."
                & $OpenSSL enc -d -aes-256-cbc -salt -pbkdf2 -pass "pass:$VaultPass" -in $VaultEnc -out $TempTar 2>$null
            }
            if (-not (Test-Path $TempTar)) {
                Log-Verbose "pass: 传参未产出文件，尝试 stdin 传参..."
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

            Log-Verbose "OpenSSL 解密完成，正在通过 tar 解压到临时隔离区: $TempUnpackDir"
            tar -xzf $TempTar -C $TempUnpackDir 2>$null
            Remove-Item -Path $TempTar -Force -ErrorAction SilentlyContinue

            $DecCustom = Join-Path $TempUnpackDir "snippets.custom.yaml"
            $DecPhrase = Join-Path $TempUnpackDir "custom_phrase.txt"
            $DecSync = Join-Path $TempUnpackDir "sync"

            Log-Message "✅ 远端数据包解密成功！包含内容:"
            if (Test-Path $DecCustom) {
                Log-Message "  • 个人私密片段: snippets.custom.yaml ($((Get-Item $DecCustom).Length) 字节)"
                if ($VerboseLog) {
                    $triggersFound = (Get-Content $DecCustom -Encoding UTF8 -ErrorAction SilentlyContinue | Select-String '^"?(/\w+)"?:').Matches.Value
                    Log-Verbose "解密出的私密片段前缀列表: $($triggersFound -join ', ')"
                }
            }
            if (Test-Path $DecPhrase) { Log-Message "  • 系统自定义短语: custom_phrase.txt ($((Get-Content $DecPhrase).Count) 行)" }
            if (Test-Path $DecSync) { Log-Message "  • 跨平台词频目录: sync/ ($((Get-ChildItem $DecSync).Name -join ', '))" }

            # 7. 如果是 -PullForce (强制从云端重置覆盖本地)，跳过三路合并直接重置本地
            if ($PullForce) {
                Log-Message "🚨 强制重置模式：正在以云端数据完全重置本地环境..."
                $BaseDir = Join-Path $RimeDir ".vault_base"
                if (-not (Test-Path $BaseDir)) { New-Item -ItemType Directory -Path $BaseDir -Force | Out-Null }

                if (Test-Path $DecCustom) {
                    Copy-Item -Path $DecCustom -Destination (Join-Path $ScriptDir "snippets.custom.yaml") -Force
                    Copy-Item -Path $DecCustom -Destination (Join-Path $RimeDir "snippets.custom.yaml") -Force
                    Copy-Item -Path $DecCustom -Destination (Join-Path $BaseDir "snippets.custom.base.yaml") -Force
                    Log-Verbose "已全量重置 snippets.custom.yaml 到用户目录与仓库"
                }
                if (Test-Path $DecPhrase) {
                    Copy-Item -Path $DecPhrase -Destination (Join-Path $ScriptDir "custom_phrase.txt") -Force
                    Copy-Item -Path $DecPhrase -Destination (Join-Path $RimeDir "custom_phrase.txt") -Force
                    Copy-Item -Path $DecPhrase -Destination (Join-Path $BaseDir "custom_phrase.base.txt") -Force
                    Log-Verbose "已全量重置 custom_phrase.txt 到用户目录与仓库"
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

                # 打印当前生效的 /id 内容供验证
                $CurCustom = Join-Path $RimeDir "snippets.custom.yaml"
                if (Test-Path $CurCustom) {
                    Log-Message "当前用户目录下的 /id 配置如下:"
                    Get-Content $CurCustom -Encoding UTF8 | Select-String -Pattern '/id:' -Context 0,4 | ForEach-Object { Write-Host $_ -ForegroundColor Green }
                }
                return
            }

            # 8. 智能 Git 3-Way Merge 增量合并 snippets.custom.yaml
            $BaseDir = Join-Path $RimeDir ".vault_base"
            if (-not (Test-Path $BaseDir)) { New-Item -ItemType Directory -Path $BaseDir -Force | Out-Null }
            $BaseCustom = Join-Path $BaseDir "snippets.custom.base.yaml"
            $BasePhrase = Join-Path $BaseDir "custom_phrase.base.txt"

            $RepoCustom = Join-Path $ScriptDir "snippets.custom.yaml"
            $RimeCustom = Join-Path $RimeDir "snippets.custom.yaml"

            $ActionLogs = Invoke-ThreeWaySnippetMerge -BasePath $BaseCustom -LocalPath $RimeCustom -RemotePath $DecCustom -OutPaths @($RepoCustom, $RimeCustom, $BaseCustom)
            $Summary = if ($ActionLogs.Count -gt 0) { $ActionLogs -join ', ' } else { '两端内容完全一致' }
            Log-Message "  🧩 [Git 3-Way Merge] 私密片段合并完成: $Summary"

            # 9. 直接应用从云端 (macOS iCloud 文本替换) 同步过来的系统短语
            $RepoPhrase = Join-Path $ScriptDir "custom_phrase.txt"
            $RimePhrase = Join-Path $RimeDir "custom_phrase.txt"
            $BasePhrase = Join-Path $BaseDir "custom_phrase.base.txt"
            if (Test-Path $DecPhrase) {
                Copy-Item -Path $DecPhrase -Destination $RepoPhrase -Force
                Copy-Item -Path $DecPhrase -Destination $RimePhrase -Force
                Copy-Item -Path $DecPhrase -Destination $BasePhrase -Force
                Log-Message "  • custom_phrase.txt 镜像同步完成 (来自 iCloud 文本替换)，共计 $((Get-Content $DecPhrase).Count) 行短语！"
            }

            # 10. 合并词频目录
            if (Test-Path $DecSync) {
                Copy-Item -Path (Join-Path $DecSync "*") -Destination (Join-Path $ScriptDir "sync") -Recurse -Force -ErrorAction SilentlyContinue
                Copy-Item -Path (Join-Path $DecSync "*") -Destination (Join-Path $RimeDir "sync") -Recurse -Force -ErrorAction SilentlyContinue
            }

            Remove-Item -Recurse -Force $TempUnpackDir -ErrorAction SilentlyContinue
            Log-Message "✅ 远端隐私短语、私密片段与词频已成功解密并完成双向合并！"
            $ConfigUpdated = $true
        } catch {
            Log-Message "解密提取过程异常: $_"
        }
    }
}

# 11. 归档词频文件到仓库
$SourceSync = Join-Path $RimeDir "sync"
$TargetSync = Join-Path $ScriptDir "sync"

# 确保用户目录中的私密片段与短语同步回仓库目录 (以最新修改时间为准)
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

if (Test-Path $SourceSync) {
    Log-Message "正在归档词频文件从 $SourceSync 到 $TargetSync..."
    if (-not (Test-Path $TargetSync)) { New-Item -ItemType Directory -Path $TargetSync -Force | Out-Null }
    
    Copy-Item -Path (Join-Path $SourceSync "*") -Destination $TargetSync -Recurse -Force -ErrorAction SilentlyContinue
    Get-ChildItem -Path $TargetSync -Recurse -File | Where-Object { $_.Extension -ne ".txt" } | Remove-Item -Force -ErrorAction SilentlyContinue
}

# 12. 对 custom_phrase.txt、snippets.custom.yaml 与 sync/ 进行 AES-256 加密打包 (vault.enc)
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

# 13. 提交并推送到 GitHub (仅提交密文包与脱敏模板)
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
            Show-Balloon -Title "Rime 词频同步" -Message "Windows 自造词与短语已安全加密备份到 GitHub！"
        } else {
            Log-Message "❌ Git Push 失败，请检查网络或 GitHub 权限。"
            Show-Balloon -Title "Rime 词频同步" -Message "⚠️ 词频加密包推送失败，请检查网络连接。" -Icon "Warning"
        }
    } else {
        Log-Message "✨ 词频已是最新，无新增改动。"
        Show-Balloon -Title "Rime 词频同步" -Message "✨ 自造词与短语已是最新状态，已同步完成！"
    }
    Pop-Location
}

if ($ConfigUpdated) {
    Log-Message "正在触发小狼毫重新部署以使最新配置与短语生效..."
    Invoke-WeaselCommand "/deploy"
}

# 验证当前最终生效的私密片段文件
$FinalCustom = Join-Path $RimeDir "snippets.custom.yaml"
if (Test-Path $FinalCustom) {
    Log-Verbose "最终小狼毫生效目录下的 snippets.custom.yaml ($((Get-Item $FinalCustom).Length) 字节)"
    if ($VerboseLog) {
        Get-Content $FinalCustom -Encoding UTF8 | Select-String -Pattern '/id:' -Context 0,4 | ForEach-Object { Log-Verbose "当前 /id 状态: $_" }
    }
}

Log-Message "===== 同步流程结束 =====`n"
