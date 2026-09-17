# ==============================================================================
# Rime 平台专一化瘦身清理脚本 (Windows 小狼毫)
# 功能：彻底清理非 Windows 系统的配置 (如 macOS squirrel)、无用的双拼/五笔/仓颉/注音方案
# ==============================================================================

param(
    [switch]$Quiet
)

$ErrorActionPreference = "SilentlyContinue"

$RimeDir = Join-Path $env:APPDATA "Rime"
if (-not (Test-Path $RimeDir)) {
    exit 0
}

if (-not $Quiet) {
    Write-Host "🧹 正在扫描并清理 Windows 小狼毫环境下冗余的非本系统与未使用方案文件..." -ForegroundColor Cyan
}

$RedundantPatterns = @(
    # macOS 鼠须管专用配置与属性列表
    "squirrel.*",
    "*.plist",

    # 台湾注音方案
    "bopomofo*",

    # 仓颉五代方案
    "cangjie5*",

    # 各类双拼方案 (小鹤/自然码/微软/搜狗/加加/紫光)
    "double_pinyin*",
    "rime_frost_double_pinyin*",

    # 五笔 86 方案
    "rime_frost_wubi86*",

    # 墨奇音形与大模型
    "rime_frost_moqi*",
    "zh-moqi.gram",

    # 辅助码拆分方案
    "rime_frost_aux*",

    # 笔画与部首反查方案
    "stroke*",
    "radical_pinyin*",

    # 移动端九宫格方案残留
    "t9.*",
    "rime_frost_t9.*",
    "melt_eng_t9.*",

    # 冗余配置与临时目录
    "recipe.yaml",
    "trash"
)

$CleanCount = 0

# 1. 清理主目录中的冗余文件
foreach ($pat in $RedundantPatterns) {
    $matches = Get-ChildItem -Path $RimeDir -Filter $pat -Force
    foreach ($item in $matches) {
        Remove-Item -Path $item.FullName -Recurse -Force
        $CleanCount++
    }
}

# 2. 清理 build/ 缓存目录中的对应二进制产物
$BuildDir = Join-Path $RimeDir "build"
if (Test-Path $BuildDir) {
    foreach ($pat in $RedundantPatterns) {
        $matches = Get-ChildItem -Path $BuildDir -Filter $pat -Force
        foreach ($item in $matches) {
            Remove-Item -Path $item.FullName -Recurse -Force
            $CleanCount++
        }
    }
}

if (-not $Quiet) {
    if ($CleanCount -gt 0) {
        Write-Host "✅ 瘦身完成！共移除了 $CleanCount 个非本系统/未使用的冗余文件。" -ForegroundColor Green
    } else {
        Write-Host "✨ 目录已经是极致纯净状态，无冗余文件。" -ForegroundColor Green
    }
}
