#!/usr/bin/env bash
# ==============================================================================
# Rime 平台专一化瘦身清理脚本 (macOS / Linux)
# 功能：彻底清理非本系统的配置 (如 Windows weasel)、无用的双拼/五笔/仓颉/注音/旧雾凇方案及工程文档
# ==============================================================================

set -e

QUIET=false
if [ "$1" = "--quiet" ] || [ "$1" = "-q" ] || [ "$1" = "--auto" ]; then
  QUIET=true
fi

BLUE='\033[0;34m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

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

# 绝对安全护卫：严禁误清理脚本所在代码仓库
if [ "$(cd "$RIME_DIR" 2>/dev/null && pwd)" = "$SCRIPT_DIR" ]; then
  echo -e "${RED}⚠️ 安全保护触发：目标目录与脚本所在源码仓库相同，已终止清理！${NC}"
  exit 1
fi

if [ "$QUIET" = false ]; then
  echo -e "${BLUE}🧹 正在扫描并清理 [${PLATFORM}] 环境下冗余的非本系统、旧方案与工程文件...${NC}"
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
  # 笔画反查方案 (部件拆字 radical_pinyin 保留给 u 拆字模式)
  "stroke*"
  # 移动端九宫格方案残留
  "t9.*"
  "rime_frost_t9.*"
  "melt_eng_t9.*"
  # 历史旧版雾凇拼音方案与历史数据库
  "rime_ice.*.yaml"
  "rime_ice.userdb"
  # 传统朙月拼音方案与数据库
  "luna_pinyin.*"
  # 未使用的辅助切片词库与键位图
  "cn_dicts_common"
  "cn_dicts_wb"
  "symbols_caps_v.yaml"
  "others"
  # 上游工程文件、文档与系统缓存
  ".git"
  ".github"
  ".vscode"
  ".gitignore"
  "README.md"
  "LICENSE"
  "AGENTS.md"
  ".DS_Store"
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

# 3. 清理主目录中的冗余文件与文件夹
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
    echo -e "${GREEN}✅ 瘦身完成！共移除了 ${CLEAN_COUNT} 个冗余文件/目录，用户目录已达极致纯净。${NC}"
  else
    echo -e "${GREEN}✨ 目录已经是极致纯净状态，无冗余文件。${NC}"
  fi
fi
