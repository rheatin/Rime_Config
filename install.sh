#!/usr/bin/env bash
# ==============================================================================
# Rime 自动配置与安装脚本 (支持 macOS 与 Linux 全发行版)
# Repository: https://github.com/rheatin/Rime_Config.git
# ==============================================================================

set -e

# 终端颜色
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${BLUE}====================================================${NC}"
echo -e "${GREEN}       🚀 开始配置 Rime 雾凇拼音与个性化环境        ${NC}"
echo -e "${BLUE}====================================================${NC}"

REPO_URL="https://github.com/rheatin/Rime_Config.git"
RIME_ICE_URL="https://github.com/iDvel/rime-ice.git"

# 1. 确定脚本所在目录或通过网络拉取
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd || echo "")"
TEMP_DIR=""

if [ -z "$SCRIPT_DIR" ] || [ ! -d "$SCRIPT_DIR/fonts" ]; then
  echo -e "${BLUE}📥 正在拉取 Rime_Config 配置与字体仓库...${NC}"
  TEMP_DIR="$(mktemp -d)"
  git clone --depth=1 "$REPO_URL" "$TEMP_DIR"
  SCRIPT_DIR="$TEMP_DIR"
fi

# 2. 识别操作系统平台与环境路径
OS="$(uname -s)"
if [ "$OS" = "Darwin" ]; then
  PLATFORM="macos"
  RIME_DIR="$HOME/Library/Rime"
  FONTS_DIR="$HOME/Library/Fonts"
  echo -e "${BLUE}💻 检测到系统：macOS (Darwin)${NC}"
elif [ "$OS" = "Linux" ]; then
  PLATFORM="linux"
  RIME_DIR="$HOME/.local/share/rime"
  FONTS_DIR="$HOME/.local/share/fonts"
  echo -e "${BLUE}🐧 检测到系统：Linux${NC}"
else
  echo -e "${RED}❌ 暂不支持的操作系统：$OS (Windows 请使用 install.ps1)${NC}"
  exit 1
fi

# 3. 自动安装/检查输入法前端
if [ "$PLATFORM" = "macos" ]; then
  SQUIRREL_APP="/Library/Input Methods/Squirrel.app"
  if [ ! -d "$SQUIRREL_APP" ]; then
    echo -e "${YELLOW}🔍 未检测到 Squirrel (鼠须管)，准备自动安装...${NC}"
    if command -v brew >/dev/null 2>&1; then
      echo -e "${BLUE}🍺 使用 Homebrew 安装 Squirrel...${NC}"
      brew install --cask squirrel
    else
      echo -e "${BLUE}🌐 正在从 GitHub 下载 Squirrel 最新安装包...${NC}"
      DMG_PATH="/tmp/Squirrel.dmg"
      curl -fsSL -o "$DMG_PATH" "https://github.com/rime/squirrel/releases/latest/download/Squirrel.dmg"
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

elif [ "$PLATFORM" = "linux" ]; then
  if ! command -v fcitx5 >/dev/null 2>&1 && ! command -v ibus >/dev/null 2>&1; then
    echo -e "${YELLOW}🔍 检测到未安装 Fcitx5，尝试通过包管理器安装 fcitx5-rime...${NC}"
    if command -v apt >/dev/null 2>&1; then
      sudo apt update && sudo apt install -y fcitx5 fcitx5-rime fcitx5-config-qt
    elif command -v pacman >/dev/null 2>&1; then
      sudo pacman -Sy --noconfirm fcitx5-im fcitx5-rime fcitx5-configtool
    elif command -v dnf >/dev/null 2>&1; then
      sudo dnf install -y fcitx5 fcitx5-rime fcitx5-configtool
    elif command -v zypper >/dev/null 2>&1; then
      sudo zypper install -y fcitx5 fcitx5-rime
    else
      echo -e "${YELLOW}⚠️ 未能自动安装 fcitx5-rime，请手动安装后继续。${NC}"
    fi
  else
    echo -e "${GREEN}✅ 检测到 Linux 输入法环境已就绪${NC}"
  fi
fi

# 4. 安装/同步 雾凇拼音 (rime-ice) 词库底座
echo -e "${BLUE}❄️  正在同步 雾凇拼音 (rime-ice) 官方词库...${NC}"
mkdir -p "$RIME_DIR"
if [ -d "$RIME_DIR/.git" ]; then
  cd "$RIME_DIR"
  REMOTE_URL="$(git remote get-url origin 2>/dev/null || true)"
  if [[ "$REMOTE_URL" == *"rime-ice"* ]]; then
    echo -e "${BLUE}🔄 正在更新现有 rime-ice...${NC}"
    git pull --ff-only || true
  fi
else
  echo -e "${BLUE}📥 克隆 rime-ice 词库到 $RIME_DIR...${NC}"
  git clone --depth=1 "$RIME_ICE_URL" "$RIME_DIR"
fi

# 5. 同步个人精简配置 (*.custom.yaml)
echo -e "${BLUE}⚙️  正在应用个人自定义配置...${NC}"
cp -f "$SCRIPT_DIR"/*.custom.yaml "$RIME_DIR/" 2>/dev/null || true
if [ -f "$SCRIPT_DIR/custom_phrase.txt" ]; then
  cp -f "$SCRIPT_DIR/custom_phrase.txt" "$RIME_DIR/"
fi
echo -e "${GREEN}✅ 个人配置应用成功！${NC}"

# 6. 安装思源宋体到系统字体库
echo -e "${BLUE}🔤 正在安装思源宋体到系统字体库...${NC}"
mkdir -p "$FONTS_DIR"
if [ -d "$SCRIPT_DIR/fonts" ]; then
  cp -f "$SCRIPT_DIR/fonts/"* "$FONTS_DIR/"
  if [ "$PLATFORM" = "linux" ] && command -v fc-cache >/dev/null 2>&1; then
    fc-cache -f "$FONTS_DIR" >/dev/null 2>&1 || true
  fi
  echo -e "${GREEN}✅ 字体安装完成！${NC}"
fi

# 7. 导入个人自造词与历史词频记忆
if [ -d "$SCRIPT_DIR/sync" ]; then
  echo -e "${BLUE}🧠 正在导入历史词频与自造词记忆...${NC}"
  mkdir -p "$RIME_DIR/sync"
  cp -rf "$SCRIPT_DIR/sync/"* "$RIME_DIR/sync/" 2>/dev/null || true
  echo -e "${GREEN}✅ 词频快照就绪！${NC}"
fi

# 8. 配置 macOS 状态栏「Sync user data」点击自动 Push 到 GitHub 的监听服务
if [ "$PLATFORM" = "macos" ]; then
  echo -e "${BLUE}⚡ 配置「Sync user data」自动推送 GitHub 守护进程...${NC}"
  LAUNCH_AGENT_DIR="$HOME/Library/LaunchAgents"
  PLIST_FILE="$LAUNCH_AGENT_DIR/com.rheatin.rime.sync.plist"
  mkdir -p "$LAUNCH_AGENT_DIR"
  
  TARGET_REPO_DIR="$HOME/Rime_Config"
  if [ ! -d "$TARGET_REPO_DIR" ]; then
    git clone "$REPO_URL" "$TARGET_REPO_DIR" 2>/dev/null || true
  fi
  chmod +x "$TARGET_REPO_DIR/sync.sh" 2>/dev/null || true

  sed -e "s|TARGET_SCRIPT_PATH|$TARGET_REPO_DIR/sync.sh|g" \
      -e "s|TARGET_SYNC_PATH|$RIME_DIR/sync|g" \
      "$SCRIPT_DIR/com.rheatin.rime.sync.plist" > "$PLIST_FILE"

  launchctl unload "$PLIST_FILE" 2>/dev/null || true
  launchctl load "$PLIST_FILE" 2>/dev/null || true
  echo -e "${GREEN}✅ 菜单栏同步监听已激活！${NC}"
fi

# 9. 重新部署与合并词频生效
echo -e "${BLUE}🔄 触发 Rime 重新部署与词频合并...${NC}"
if [ "$PLATFORM" = "macos" ]; then
  if [ -f "$SQUIRREL_APP/Contents/MacOS/Squirrel" ]; then
    "$SQUIRREL_APP/Contents/MacOS/Squirrel" --reload || true
    "$SQUIRREL_APP/Contents/MacOS/Squirrel" --sync || true
  fi
elif [ "$PLATFORM" = "linux" ]; then
  if command -v fcitx5-remote >/dev/null 2>&1; then
    fcitx5-remote -r >/dev/null 2>&1 || true
  fi
  if [ -d "$HOME/.config/ibus/rime" ] && [ "$RIME_DIR" != "$HOME/.config/ibus/rime" ]; then
    cp -rf "$RIME_DIR/"* "$HOME/.config/ibus/rime/" 2>/dev/null || true
  fi
fi

# 清理临时文件
if [ -n "$TEMP_DIR" ] && [ -d "$TEMP_DIR" ]; then
  rm -rf "$TEMP_DIR"
fi

echo -e "${BLUE}====================================================${NC}"
echo -e "${GREEN}🎉 恭喜！Rime 与 Rheatin Solarized 配置已全自动部署完毕！${NC}"
echo -e "${GREEN}🧠 个人自造词与词频记忆已完成合并恢复！${NC}"
if [ "$PLATFORM" = "macos" ]; then
  echo -e "${YELLOW}提示：今后点击输入法菜单的「Sync user data」将自动备份推送到 GitHub！${NC}"
fi
echo -e "${BLUE}====================================================${NC}"
