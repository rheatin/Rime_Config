#!/usr/bin/env bash
# ==============================================================================
# Rime 自动配置与安装脚本 (Squirrel + 雾凇拼音 + 个人定制 + 思源字体)
# Repository: https://github.com/rheatin/Rime_Config.git
# ==============================================================================

set -e

# 颜色定义
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${BLUE}====================================================${NC}"
echo -e "${GREEN}       🚀 开始配置 Rime 雾凇拼音与个性化环境        ${NC}"
echo -e "${BLUE}====================================================${NC}"

# 1. 检查操作系统
OS="$(uname -s)"
if [ "$OS" != "Darwin" ]; then
  echo -e "${RED}❌ 本脚本目前专为 macOS (Squirrel 鼠须管) 设计。${NC}"
  exit 1
fi

RIME_DIR="$HOME/Library/Rime"
FONTS_DIR="$HOME/Library/Fonts"
REPO_URL="https://github.com/rheatin/Rime_Config.git"
RIME_ICE_URL="https://github.com/iDvel/rime-ice.git"

# 确定当前脚本工作目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd || echo "")"
TEMP_DIR=""

# 如果是通过 curl 管道直接运行，自动拉取 Rime_Config 仓库
if [ -z "$SCRIPT_DIR" ] || [ ! -d "$SCRIPT_DIR/fonts" ]; then
  echo -e "${BLUE}📥 正在下载个人配置与字体资源...${NC}"
  TEMP_DIR="$(mktemp -d)"
  git clone --depth=1 "$REPO_URL" "$TEMP_DIR"
  SCRIPT_DIR="$TEMP_DIR"
fi

# 2. 检查并安装 Squirrel (鼠须管)
SQUIRREL_APP="/Library/Input Methods/Squirrel.app"
if [ ! -d "$SQUIRREL_APP" ]; then
  echo -e "${YELLOW}🔍 未检测到 Squirrel (鼠须管)，准备自动安装...${NC}"
  if command -v brew >/dev/null 2>&1; then
    echo -e "${BLUE}🍺 使用 Homebrew 安装 Squirrel...${NC}"
    brew install --cask squirrel
  else
    echo -e "${BLUE}🌐 正在从 GitHub 下载 Squirrel 最新安装包...${NC}"
    SQUIRREL_RELEASE_URL="https://github.com/rime/squirrel/releases/latest/download/Squirrel.dmg"
    DMG_PATH="/tmp/Squirrel.dmg"
    curl -fsSL -o "$DMG_PATH" "$SQUIRREL_RELEASE_URL"
    
    echo -e "${BLUE}📦 挂载并安装 Squirrel...${NC}"
    MOUNT_DIR="/tmp/squirrel_mount"
    hdiutil attach "$DMG_PATH" -mountpoint "$MOUNT_DIR" -nobrowse -quiet
    
    if [ -f "$MOUNT_DIR/Install Squirrel.pkg" ]; then
      sudo installer -pkg "$MOUNT_DIR/Install Squirrel.pkg" -target /
    elif [ -d "$MOUNT_DIR/Squirrel.app" ]; then
      sudo cp -R "$MOUNT_DIR/Squirrel.app" "/Library/Input Methods/"
    fi
    
    hdiutil detach "$MOUNT_DIR" -quiet || true
    rm -f "$DMG_PATH"
  fi
  echo -e "${GREEN}✅ Squirrel 安装完成！${NC}"
else
  echo -e "${GREEN}✅ 检测到已安装 Squirrel (鼠须管)${NC}"
fi

# 3. 安装/更新 雾凇拼音 (rime-ice) 词库底座
echo -e "${BLUE}❄️  正在同步 雾凇拼音 (rime-ice) 官方词库...${NC}"
mkdir -p "$RIME_DIR"
if [ -d "$RIME_DIR/.git" ]; then
  cd "$RIME_DIR"
  # 如果当前是 rime-ice 仓库则拉取更新
  REMOTE_URL="$(git remote get-url origin 2>/dev/null || true)"
  if [[ "$REMOTE_URL" == *"rime-ice"* ]]; then
    echo -e "${BLUE}🔄 正在更新现有 rime-ice...${NC}"
    git pull --ff-only || true
  fi
else
  echo -e "${BLUE}📥 克隆 rime-ice 词库底座到 $RIME_DIR...${NC}"
  git clone --depth=1 "$RIME_ICE_URL" "$RIME_DIR"
fi

# 4. 同步个人精简配置 (*.custom.yaml)
echo -e "${BLUE}⚙️  正在应用个人自定义配置...${NC}"
cp -f "$SCRIPT_DIR"/*.custom.yaml "$RIME_DIR/" 2>/dev/null || true
if [ -f "$SCRIPT_DIR/custom_phrase.txt" ]; then
  cp -f "$SCRIPT_DIR/custom_phrase.txt" "$RIME_DIR/"
fi
echo -e "${GREEN}✅ 个人配置应用成功！${NC}"

# 5. 安装思源宋体 & 生僻字字体
echo -e "${BLUE}🔤 正在安装思源宋体与生僻字字体到系统字体库...${NC}"
mkdir -p "$FONTS_DIR"
if [ -d "$SCRIPT_DIR/fonts" ]; then
  cp -f "$SCRIPT_DIR/fonts/"* "$FONTS_DIR/"
  echo -e "${GREEN}✅ 字体安装完成！${NC}"
fi

# 6. 重新部署 Squirrel
echo -e "${BLUE}🔄 触发 Squirrel 重新部署与配置编译...${NC}"
if [ -f "$SQUIRREL_APP/Contents/MacOS/Squirrel" ]; then
  "$SQUIRREL_APP/Contents/MacOS/Squirrel" --reload || true
fi

# 清理临时目录
if [ -n "$TEMP_DIR" ] && [ -d "$TEMP_DIR" ]; then
  rm -rf "$TEMP_DIR"
fi

echo -e "${BLUE}====================================================${NC}"
echo -e "${GREEN}🎉 恭喜！全部安装与配置已完成！${NC}"
echo -e "${YELLOW}提示：若首次安装 Squirrel，请在「系统设置 -> 键盘 -> 输入法」中添加「鼠须管 (Squirrel)」。${NC}"
echo -e "${BLUE}====================================================${NC}"
