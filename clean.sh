#!/usr/bin/env bash
# ==============================================================================
# Rime 平台专一化瘦身清理脚本 (macOS / Linux)
# 功能：彻底清理非本系统的配置 (如 Windows weasel)、无用的双拼/五笔/仓颉/注音方案
# ==============================================================================

set -e

QUIET=false
if [ "$1" = "--quiet" ] || [ "$1" = "-q" ] || [ "$1" = "--auto" ]; then
  QUIET=true
fi

BLUE='\033[0;34m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

# 1. 确定当前平台及 Rime 用户目录
OS="$(uname -s)"
if [ "$OS" = "Darwin" ]; then
  PLATFORM="macos"
  RIME_DIR="$HOME/Library/Rime"
elif [ "$OS" = "Linux" ]; then
  PLATFORM="linux"
  if [ -d "$HOME/.local/share/rime" ]; then
    RIME_DIR="$HOME/.local/share/rime"
  else
    RIME_DIR="$HOME/.config/ibus/rime"
  fi
else
  exit 0
fi

if [ ! -d "$RIME_DIR" ]; then
  exit 0
fi

if [ "$QUIET" = false ]; then
  echo -e "${BLUE}🧹 正在扫描并清理 [${PLATFORM}] 环境下冗余的非本系统与未使用方案文件...${NC}"
fi

# 2. 定义冗余文件匹配规则
REDUNDANT_PATTERNS=(
  # 台湾注音方案
  "bopomofo*"
  # 仓颉五代方案
  "cangjie5*"
  # 各类双拼方案 (小鹤/自然码/微软/搜狗/加加/紫光)
  "double_pinyin*"
  "rime_frost_double_pinyin*"
  # 五笔 86 方案
  "rime_frost_wubi86*"
  # 墨奇音形与大模型
  "rime_frost_moqi*"
  "zh-moqi.gram"
  # 辅助码拆分方案
  "rime_frost_aux*"
  # 笔画与部首反查方案
  "stroke*"
  "radical_pinyin*"
  # 移动端九宫格方案残留
  "t9.*"
  "rime_frost_t9.*"
  "melt_eng_t9.*"
  # 冗余配置与临时目录
  "recipe.yaml"
  "trash"
)

# 跨系统配置文件隔离：
# 在 macOS 上移除 Windows 小狼毫专用文件
if [ "$PLATFORM" = "macos" ]; then
  REDUNDANT_PATTERNS+=("weasel.*")
# 在 Linux 上移除 macOS 鼠须管与 Windows 小狼毫专用文件
elif [ "$PLATFORM" = "linux" ]; then
  REDUNDANT_PATTERNS+=("weasel.*" "squirrel.*")
fi

CLEAN_COUNT=0

# 3. 清理主目录中的冗余文件
for pat in "${REDUNDANT_PATTERNS[@]}"; do
  for file in "$RIME_DIR"/$pat; do
    if [ -e "$file" ]; then
      rm -rf "$file"
      CLEAN_COUNT=$((CLEAN_COUNT + 1))
    fi
  done
done

# 4. 清理 build/ 缓存目录中的对应二进制产物
BUILD_DIR="$RIME_DIR/build"
if [ -d "$BUILD_DIR" ]; then
  for pat in "${REDUNDANT_PATTERNS[@]}"; do
    for file in "$BUILD_DIR"/$pat; do
      if [ -e "$file" ]; then
        rm -rf "$file"
        CLEAN_COUNT=$((CLEAN_COUNT + 1))
      fi
    done
  done
fi

if [ "$QUIET" = false ]; then
  if [ $CLEAN_COUNT -gt 0 ]; then
    echo -e "${GREEN}✅ 瘦身完成！共移除了 ${CLEAN_COUNT} 个非本系统/未使用的冗余文件。${NC}"
  else
    echo -e "${GREEN}✨ 目录已经是极致纯净状态，无冗余文件。${NC}"
  fi
fi
