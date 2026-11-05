#!/usr/bin/env bash
# ==============================================================================
# Rime 自动配置与安装脚本 (白霜拼音 rime-frost + 万象语言模型 + MoeType + 个人定制)
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
echo -e "${GREEN} 🚀 开始配置 Rime 白霜拼音 + 万象语言模型 + MoeType  ${NC}"
echo -e "${BLUE}====================================================${NC}"

REPO_URL="${RIME_REPO_URL:-https://github.com/rheatin/Rime_Config.git}"
RIME_FROST_URL="https://github.com/gaboolic/rime-frost.git"

WANXIANG_API_URL="https://api.github.com/repos/amzxyz/rime-wanxiang-data/releases/tags/LTS"
WANXIANG_MODEL_URL="https://github.com/amzxyz/rime-wanxiang-data/releases/download/LTS/wanxiang-lts-zh-hans.gram"
FALLBACK_WANXIANG_SHA256="1635588006d79cc6955fbcf3d8de12822a36856eb5408735a8b4a2952b16cadf"

MOETYPE_API_URL="https://api.github.com/repos/suiginko/moetype/releases/latest"
MOETYPE_RELEASE_URL="https://github.com/suiginko/moetype/releases/latest/download/toneless_moe.dict.yaml"
FALLBACK_MOE_SHA256="bbf8fb188a88d84310457f65f3c2ebcec692c5371087a1f6589eab8b923c08af"

# 1. 确定脚本所在目录或通过网络拉取
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd || echo "")"
TEMP_DIR=""

# 1.0 自更新自愈机制：若本地已有 Git 仓库，先拉取最新版本并重新载入最新脚本执行
if [ -d "$SCRIPT_DIR/.git" ] && [ "${RIME_ALREADY_UPDATED:-false}" != "true" ]; then
  echo -e "${BLUE}📡 检测到本地已有 Git 仓库，正在拉取最新代码...${NC}"
  if git -C "$SCRIPT_DIR" pull --no-rebase origin main 2>/dev/null; then
    export RIME_ALREADY_UPDATED=true
    exec bash "$SCRIPT_DIR/$(basename "$0")" "$@"
  fi
fi

if [ -z "$RIME_REPO_URL" ] && [ -d "$SCRIPT_DIR/.git" ]; then
  DETECTED_URL="$(git -C "$SCRIPT_DIR" remote get-url origin 2>/dev/null || true)"
  [ -n "$DETECTED_URL" ] && REPO_URL="$DETECTED_URL"
fi

if [ -z "$SCRIPT_DIR" ] || [ ! -d "$SCRIPT_DIR/fonts" ]; then
  echo -e "${BLUE}📥 正在拉取 Rime_Config 配置与字体仓库...${NC}"
  TEMP_DIR="$(mktemp -d)"
  git clone --depth=1 "$REPO_URL" "$TEMP_DIR"
  SCRIPT_DIR="$TEMP_DIR"
fi

# 1.1 交互式初始化向导 (自选底座方案 / 输入模式 / 大模型 / 词库)
run_wizard() {
  local IS_AUTO=false
  for arg in "$@"; do
    if [ "$arg" = "--auto" ] || [ "$arg" = "-y" ] || [ "$arg" = "--non-interactive" ]; then IS_AUTO=true; break; fi
  done

  # 默认推荐值
  RIME_FRAMEWORK="rime-frost"
  RIME_CUSTOM_REPO=""
  RIME_SCHEMA="rime_frost"
  RIME_MODEL="wanxiang_lts"
  RIME_CUSTOM_MODEL_URL=""
  RIME_ENABLE_MOE=true
  RIME_ENABLE_CELLS=true
  RIME_ENABLE_TENCENT=false
  RIME_CUSTOM_DICT_URL=""

  if [ "$IS_AUTO" = true ] || [ ! -e /dev/tty ]; then
    echo -e "${GREEN}ℹ️ 自动模式：使用官方推荐配置 (白霜全拼 + 万象 LTS 400MB + 萌娘百科 + 细胞词库)${NC}"
  else
    echo ""
    echo -e "${BLUE}====================================================${NC}"
    echo -e "${YELLOW}🛠️  Rime 个性化配置向导 (直接回车默认采用推荐项)${NC}"
    echo -e "${BLUE}====================================================${NC}"

    # 阶段 1: 底座框架
    echo -e "\n${BLUE}【第 1 步】请选择输入法方案底座 (Base Framework):${NC}"
    echo -e "  ${GREEN}1. 白霜拼音 (rime-frost) [推荐]${NC} - 词库聚合全面、内置拆字反查、多模式支持"
    echo -e "  2. 雾凇拼音 (rime-ice) - 自然语言语料切分、极简清爽经典方案"
    echo -e "  3. 自定义外部方案 (输入 GitHub 用户名/仓库名，自动校验并拉取)"
    read -r -p "👉 请选择 [1-3, 默认 1]: " FW_CHOICE < /dev/tty
    FW_CHOICE="${FW_CHOICE:-1}"

    case "$FW_CHOICE" in
      2)
        RIME_FRAMEWORK="rime-ice"
        RIME_SCHEMA="rime_ice"
        ;;
      3)
        while true; do
          read -r -p "👉 请输入 GitHub 方案仓库 (格式 owner/repo，例如 iDvel/rime-ice): " USER_REPO < /dev/tty
          if [ -n "$USER_REPO" ]; then
            echo -e "   🔍 正在验证 GitHub 仓库有效性..."
            if curl -fsSL -I "https://api.github.com/repos/$USER_REPO" 2>/dev/null | grep -q "HTTP/.* 200" || \
               git ls-remote "https://github.com/$USER_REPO.git" >/dev/null 2>&1; then
              echo -e "   ${GREEN}✅ 验证通过！成功连接到该 GitHub 方案库。${NC}"
              RIME_FRAMEWORK="custom"
              RIME_CUSTOM_REPO="https://github.com/$USER_REPO.git"
              break
            else
              echo -e "   ${RED}❌ 未能找到该仓库或无权限，请核对后重新输入！${NC}"
            fi
          fi
        done
        ;;
      *)
        RIME_FRAMEWORK="rime-frost"
        ;;
    esac

    # 阶段 2: 输入模式
    if [ "$RIME_FRAMEWORK" = "rime-frost" ]; then
      echo -e "\n${BLUE}【第 2 步】请选择主输入模式 (Input Mode):${NC}"
      echo -e "  ${GREEN}1. 经典全拼 (Standard Pinyin) [推荐]${NC}"
      echo -e "  2. 小鹤双拼 (Double Pinyin - Flypy)"
      echo -e "  3. 自然码双拼 (Double Pinyin - Zrm)"
      echo -e "  4. 微软双拼 (Double Pinyin - MSPY)"
      echo -e "  5. 五笔 86 (Wubi 86)"
      read -r -p "👉 请选择 [1-5, 默认 1]: " SCHEMA_CHOICE < /dev/tty
      SCHEMA_CHOICE="${SCHEMA_CHOICE:-1}"
      case "$SCHEMA_CHOICE" in
        2) RIME_SCHEMA="rime_frost_double_pinyin_flypy" ;;
        3) RIME_SCHEMA="rime_frost_double_pinyin" ;;
        4) RIME_SCHEMA="rime_frost_double_pinyin_mspy" ;;
        5) RIME_SCHEMA="rime_frost_wubi86" ;;
        *) RIME_SCHEMA="rime_frost" ;;
      esac
    fi

    # 阶段 3: 语言模型
    echo -e "\n${BLUE}【第 3 步】请选择 AI 语法语言模型 (Grammar Model):${NC}"
    echo -e "  ${GREEN}1. 万象 LTS 400MB 语法模型 [推荐]${NC} - 大幅跃升长句整句命中率"
    echo -e "  2. 跳过安装 (轻量纯净模式) - 零额外下载，极度节省 400MB 内存"
    read -r -p "👉 请选择 [1-2, 默认 1]: " MODEL_CHOICE < /dev/tty
    MODEL_CHOICE="${MODEL_CHOICE:-1}"
    if [ "$MODEL_CHOICE" = "2" ]; then
      RIME_MODEL="none"
    else
      RIME_MODEL="wanxiang_lts"
    fi

    # 阶段 4: 扩展词库
    echo -e "\n${BLUE}【第 4 步】请选择要挂载的扩展词库 (支持多选，输入编号如 1 2):${NC}"
    echo -e "  1. MoeType 萌娘百科 (17.5 万二次元、ACG 与流行热词)"
    echo -e "  2. 专业细胞词库 (涵盖计算机、医学、理化、地理历史等 20+ 领域)"
    echo -e "  3. 腾讯社交网络高频语料词库"
    echo -e "  4. 全部跳过 (仅保留基础核心字词库)"
    read -r -p "👉 请输入编号 [例如 1 2，直接回车默认 1 2]: " DICT_CHOICES < /dev/tty
    DICT_CHOICES="${DICT_CHOICES:-1 2}"
    if [[ "$DICT_CHOICES" == *"4"* ]]; then
      RIME_ENABLE_MOE=false
      RIME_ENABLE_CELLS=false
      RIME_ENABLE_TENCENT=false
    else
      [[ "$DICT_CHOICES" == *"1"* ]] && RIME_ENABLE_MOE=true || RIME_ENABLE_MOE=false
      [[ "$DICT_CHOICES" == *"2"* ]] && RIME_ENABLE_CELLS=true || RIME_ENABLE_CELLS=false
      [[ "$DICT_CHOICES" == *"3"* ]] && RIME_ENABLE_TENCENT=true || RIME_ENABLE_TENCENT=false
    fi

    echo -e "\n${GREEN}✅ 向导完成！正在为您自动组装方案与词库...${NC}"
    echo -e "${BLUE}====================================================${NC}\n"
  fi

  # 持久化偏好画像到 .rime_profile
  cat << EOF > "$SCRIPT_DIR/.rime_profile"
# ==============================================================================
# Rime 用户个性化偏好画像 (.rime_profile)
# ==============================================================================
RIME_FRAMEWORK="$RIME_FRAMEWORK"
RIME_CUSTOM_REPO="$RIME_CUSTOM_REPO"
RIME_SCHEMA="$RIME_SCHEMA"
RIME_MODEL="$RIME_MODEL"
RIME_CUSTOM_MODEL_URL="$RIME_CUSTOM_MODEL_URL"
RIME_ENABLE_MOE=$RIME_ENABLE_MOE
RIME_ENABLE_CELLS=$RIME_ENABLE_CELLS
RIME_ENABLE_TENCENT=$RIME_ENABLE_TENCENT
RIME_CUSTOM_DICT_URL="$RIME_CUSTOM_DICT_URL"
EOF
  cp -f "$SCRIPT_DIR/.rime_profile" "$RIME_DIR/.rime_profile" 2>/dev/null || true

  # 触发动态配置生成引擎
  if [ -f "$SCRIPT_DIR/tools/rime_generator.py" ] && command -v python3 >/dev/null 2>&1; then
    python3 "$SCRIPT_DIR/tools/rime_generator.py" >/dev/null 2>&1 || true
  fi
}

run_wizard "$@"

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

  # 3.1 注册并启用输入源 (关键！)
  #     macOS 更新或应用异常退出后，输入源注册可能丢失 —— 症状是输入法菜单里
  #     根本选不到"鼠须管"。TISRegisterInputSource 需要重新执行一次。
  #     注意：直接 cp 到 /Library/Input Methods 的方式（dmg 路径）不会自动注册。
  if [ -x "$SQUIRREL_APP/Contents/MacOS/Squirrel" ]; then
    echo -e "${BLUE}🔧 正在注册并启用输入源...${NC}"
    "$SQUIRREL_APP/Contents/MacOS/Squirrel" --register-input-source >/dev/null 2>&1 || true
    "$SQUIRREL_APP/Contents/MacOS/Squirrel" --enable-input-source >/dev/null 2>&1 || true
    echo -e "${GREEN}✅ 输入源已注册并启用${NC}"
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

# 4. 安装/同步 方案底座
TARGET_FRAMEWORK_URL="$RIME_FROST_URL"
if [ "$RIME_FRAMEWORK" = "rime-ice" ]; then
  TARGET_FRAMEWORK_URL="https://github.com/iDvel/rime-ice.git"
  echo -e "${BLUE}❄️  正在同步 雾凇拼音 (rime-ice) 官方底座...${NC}"
elif [ "$RIME_FRAMEWORK" = "custom" ] && [ -n "$RIME_CUSTOM_REPO" ]; then
  TARGET_FRAMEWORK_URL="$RIME_CUSTOM_REPO"
  echo -e "${BLUE}📦 正在同步自定义方案底座 ($RIME_CUSTOM_REPO)...${NC}"
else
  echo -e "${BLUE}❄️  正在同步 白霜拼音 (rime-frost) 官方底座...${NC}"
fi

mkdir -p "$RIME_DIR"
TEMP_FRAMEWORK="$(mktemp -d)"

if git clone --depth=1 "$TARGET_FRAMEWORK_URL" "$TEMP_FRAMEWORK" 2>/dev/null; then
  echo -e "${BLUE}📥 正在应用最新方案词库到 $RIME_DIR...${NC}"
  cp -rf "$TEMP_FRAMEWORK/"* "$RIME_DIR/"
  cp -rf "$TEMP_FRAMEWORK/.git" "$RIME_DIR/" 2>/dev/null || true
  rm -rf "$TEMP_FRAMEWORK"
  echo -e "${GREEN}✅ 方案底座词库同步完成！${NC}"
else
  echo -e "${YELLOW}⚠️ Git 克隆失败，尝试通过 GitHub Zip 压缩包同步...${NC}"
  ZIP_FALLBACK_URL="${TARGET_FRAMEWORK_URL%.git}/archive/refs/heads/main.zip"
  FRAMEWORK_ZIP="$(mktemp "${TMPDIR:-/tmp}/rime_fw_XXXXXX.zip")"
  EXTRACT_DIR="$(mktemp -d "${TMPDIR:-/tmp}/rime_fw_extract_XXXXXX")"
  if curl -fsSL "$ZIP_FALLBACK_URL" -o "$FRAMEWORK_ZIP" 2>/dev/null || \
     curl -fsSL "${TARGET_FRAMEWORK_URL%.git}/archive/refs/heads/master.zip" -o "$FRAMEWORK_ZIP" 2>/dev/null; then
    unzip -qo "$FRAMEWORK_ZIP" -d "$EXTRACT_DIR"
    cp -rf "$EXTRACT_DIR"/*/* "$RIME_DIR/"
    rm -rf "$FRAMEWORK_ZIP" "$EXTRACT_DIR"
    echo -e "${GREEN}✅ 方案底座解压同步完成！${NC}"
  else
    echo -e "${YELLOW}⚠️ 底座网络拉取受阻，跳过官方底座更新，继续执行...${NC}"
  fi
fi

# 5. 校验与下载万象语言模型 (若用户启用)
if [ "$RIME_MODEL" = "wanxiang_lts" ]; then
MODEL_TARGET="$RIME_DIR/wanxiang-lts-zh-hans.gram"
calc_sha256() {
  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$1" | awk '{print $1}'
  elif command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  else
    echo ""
  fi
}

echo -e "${BLUE}🌐 正在查询万象语言模型 GitHub 远程 Digest SHA256...${NC}"
REMOTE_WANXIANG_SHA256=$(python3 -c "
import urllib.request, json
url = '$WANXIANG_API_URL'
req = urllib.request.Request(url, headers={'User-Agent': 'Mozilla/5.0'})
try:
    with urllib.request.urlopen(req, timeout=8) as resp:
        data = json.loads(resp.read().decode())
        for a in data.get('assets', []):
            if a.get('name') == 'wanxiang-lts-zh-hans.gram':
                d = a.get('digest', '')
                if d.startswith('sha256:'):
                    print(d.split('sha256:')[1].strip())
                    break
except Exception:
    pass
" 2>/dev/null || echo "")

if [ -z "$REMOTE_WANXIANG_SHA256" ]; then
  REMOTE_WANXIANG_SHA256="$FALLBACK_WANXIANG_SHA256"
  echo -e "${YELLOW}ℹ️ 使用内置基准 SHA256: ${REMOTE_WANXIANG_SHA256:0:16}...${NC}"
else
  echo -e "${GREEN}✅ 获取到远程万象模型 SHA256: ${REMOTE_WANXIANG_SHA256:0:16}...${NC}"
fi

MODEL_OK=false
if [ -f "$MODEL_TARGET" ]; then
  CURRENT_SHA="$(calc_sha256 "$MODEL_TARGET")"
  if [ "$CURRENT_SHA" = "$REMOTE_WANXIANG_SHA256" ]; then
    echo -e "${GREEN}✅ 本地万象模型与 GitHub 远程 Digest 完全一致，跳过下载！${NC}"
    MODEL_OK=true
  else
    echo -e "${YELLOW}⚠️ 本地万象模型 SHA256 不一致或有更新，准备拉取最新版本...${NC}"
  fi
fi

if [ "$MODEL_OK" = false ]; then
  echo -e "${BLUE}🧠 正在下载万象 (Wanxiang) LTS 语法语言模型 (~400MB)...${NC}"
  DOWNLOAD_SUCCESS=false
  DOWNLOAD_URLS=(
    "$WANXIANG_MODEL_URL"
    "https://ghproxy.net/$WANXIANG_MODEL_URL"
    "https://ghfast.top/$WANXIANG_MODEL_URL"
  )
  for url in "${DOWNLOAD_URLS[@]}"; do
    echo -e "   正在尝试下载源: $url"
    if curl -fL --retry 3 --retry-delay 2 -C - "$url" -o "$MODEL_TARGET.tmp" 2>/dev/null; then
      DOWNLOAD_SHA="$(calc_sha256 "$MODEL_TARGET.tmp")"
      if [ -n "$DOWNLOAD_SHA" ] && [ "$DOWNLOAD_SHA" = "$REMOTE_WANXIANG_SHA256" ]; then
        mv "$MODEL_TARGET.tmp" "$MODEL_TARGET"
        echo -e "${GREEN}✅ 万象语言模型下载且 GitHub 官方 SHA256 校验通过！${NC}"
        DOWNLOAD_SUCCESS=true
        break
      else
        echo -e "${YELLOW}⚠️ 该源下载的文件 SHA256 校验不匹配，尝试备选源...${NC}"
        rm -f "$MODEL_TARGET.tmp"
      fi
    fi
  done

  if [ "$DOWNLOAD_SUCCESS" = false ]; then
    rm -f "$MODEL_TARGET.tmp"
    if [ -f "$MODEL_TARGET" ]; then
      echo -e "${YELLOW}⚠️ 语言模型网络拉取超时，保留本地现存可用模型，继续执行后续配置与部署...${NC}"
    else
      echo -e "${RED}❌ 万象语言模型首次下载失败，请检查网络连接或代理设置。${NC}"
      exit 1
    fi
  fi
fi
else
  echo -e "${GREEN}ℹ️ 用户跳过万象 AI 语法模型 (保持纯本地词典匹配，零额外内存占用)${NC}"
  rm -f "$RIME_DIR/wanxiang-lts-zh-hans.gram" 2>/dev/null || true
fi

# 6. 动态获取 MoeType 远程 Digest 并智能比对跳过/下载去重 (若用户启用)
if [ "$RIME_ENABLE_MOE" = true ]; then
TARGET_MOE="$RIME_DIR/moe.dict.yaml"
MOE_DIGEST_FILE="$RIME_DIR/.moe_digest"
echo -e "${BLUE}🌸 正在查询 MoeType 词库 GitHub 远程 Digest SHA256...${NC}"

REMOTE_MOE_SHA256=$(python3 -c "
import urllib.request, json
url = '$MOETYPE_API_URL'
req = urllib.request.Request(url, headers={'User-Agent': 'Mozilla/5.0'})
try:
    with urllib.request.urlopen(req, timeout=8) as resp:
        data = json.loads(resp.read().decode())
        for a in data.get('assets', []):
            if a.get('name') == 'toneless_moe.dict.yaml':
                d = a.get('digest', '')
                if d.startswith('sha256:'):
                    print(d.split('sha256:')[1].strip())
                    break
except Exception:
    pass
" 2>/dev/null || echo "")

if [ -z "$REMOTE_MOE_SHA256" ]; then
  REMOTE_MOE_SHA256="$FALLBACK_MOE_SHA256"
fi

MOE_NEED_UPDATE=true
if [ -f "$TARGET_MOE" ] && [ -f "$MOE_DIGEST_FILE" ]; then
  SAVED_DIGEST="$(cat "$MOE_DIGEST_FILE" 2>/dev/null | tr -d '[:space:]')"
  if [ "$SAVED_DIGEST" = "$REMOTE_MOE_SHA256" ]; then
    echo -e "${GREEN}✅ 本地 MoeType 词库与 GitHub 远程最新 Digest 一致，跳过下载与去重！${NC}"
    MOE_NEED_UPDATE=false
  fi
fi

if [ "$MOE_NEED_UPDATE" = true ]; then
  echo -e "${BLUE}🌸 正在获取 MoeType 最新官方词库并进行动态去重...${NC}"
  RAW_MOE_TEMP="/tmp/toneless_moe_raw.dict.yaml"
  if curl -fsSL "$MOETYPE_RELEASE_URL" -o "$RAW_MOE_TEMP"; then
    python3 -c "
import os
rime_dir = '$RIME_DIR'
cn_dicts = os.path.join(rime_dir, 'cn_dicts')
rime_words = set()
if os.path.exists(cn_dicts):
    for root, _, files in os.walk(cn_dicts):
        for fn in files:
            if fn.endswith('.dict.yaml') or fn.endswith('.txt'):
                with open(os.path.join(root, fn), 'r', encoding='utf-8', errors='ignore') as f:
                    in_b = False
                    for l in f:
                        if l.strip() == '...': in_b = True; continue
                        if not in_b or not l or l.startswith('#'): continue
                        p = l.split('\t')
                        if p and p[0].strip(): rime_words.add(p[0].strip())

out_file = '$TARGET_MOE'
kept = 0
removed = 0
with open('$RAW_MOE_TEMP', 'r', encoding='utf-8') as fin, open(out_file, 'w', encoding='utf-8') as fout:
    in_b = False
    for line in fin:
        if line.strip() == '...': in_b = True; fout.write(line); continue
        if not in_b: fout.write(line); continue
        if not line.strip() or line.startswith('#'): fout.write(line); continue
        p = line.strip().split('\t')
        w = p[0].strip()
        if w in rime_words:
            removed += 1
        else:
            kept += 1
            fout.write(line)
print(f'   去重完成：保留独有词条 {kept:,}，剔除重复词条 {removed:,}')
"
    rm -f "$RAW_MOE_TEMP"
    echo "$REMOTE_MOE_SHA256" > "$MOE_DIGEST_FILE"
    echo -e "${GREEN}✅ MoeType 动态去重完成！${NC}"
  else
    echo -e "${YELLOW}⚠️ MoeType 下载失败，跳过扩展词库。${NC}"
  fi
fi
else
  echo -e "${GREEN}ℹ️ 用户跳过 MoeType 萌娘百科词库挂载${NC}"
  rm -f "$RIME_DIR/moe.dict.yaml" "$RIME_DIR/.moe_digest" 2>/dev/null || true
fi

# 7. 同步个人精简配置与聚合词库定义
echo -e "${BLUE}⚙️  正在应用个人自定义配置与 Rheatin 配色...${NC}"
cp -f "$SCRIPT_DIR"/*.custom.yaml "$RIME_DIR/" 2>/dev/null || true
cp -f "$SCRIPT_DIR"/*.dict.yaml "$RIME_DIR/" 2>/dev/null || true
cp -f "$SCRIPT_DIR"/symbols_v.yaml "$RIME_DIR/" 2>/dev/null || true
if [ -d "$SCRIPT_DIR/lua" ]; then
  mkdir -p "$RIME_DIR/lua"
  cp -rf "$SCRIPT_DIR/lua/"* "$RIME_DIR/lua/" 2>/dev/null || true
fi
if [ -f "$SCRIPT_DIR/custom_phrase.txt" ]; then
  cp -f "$SCRIPT_DIR/custom_phrase.txt" "$RIME_DIR/"
elif [ -f "$SCRIPT_DIR/custom_phrase.example.txt" ]; then
  cp -f "$SCRIPT_DIR/custom_phrase.example.txt" "$RIME_DIR/custom_phrase.txt"
fi
if [ -f "$SCRIPT_DIR/snippets.yaml" ]; then
  cp -f "$SCRIPT_DIR/snippets.yaml" "$RIME_DIR/"
fi
if [ -f "$SCRIPT_DIR/snippets.custom.yaml" ]; then
  cp -f "$SCRIPT_DIR/snippets.custom.yaml" "$RIME_DIR/"
elif [ -f "$SCRIPT_DIR/snippets.custom.example.yaml" ]; then
  cp -f "$SCRIPT_DIR/snippets.custom.example.yaml" "$RIME_DIR/snippets.custom.yaml"
fi
echo -e "${GREEN}✅ 个人配置应用成功！${NC}"

# 8. 安装思源宋体与 Symbols Nerd Font 字体 (若已安装则跳过)
if [ -d "$SCRIPT_DIR/fonts" ]; then
  FONTS_EXIST=true
  for f in "$SCRIPT_DIR/fonts/"*.*; do
    [ -f "$f" ] || continue
    FONT_NAME="$(basename "$f")"
    if [ ! -f "$FONTS_DIR/$FONT_NAME" ] && [ ! -f "/Library/Fonts/$FONT_NAME" ] && [ ! -f "/usr/share/fonts/$FONT_NAME" ]; then
      FONTS_EXIST=false
      break
    fi
  done

  if [ "$FONTS_EXIST" = true ]; then
    echo -e "${GREEN}✅ 检测到思源宋体与 Symbols Nerd Font 已安装，自动跳过字体安装！${NC}"
  else
    echo -e "${BLUE}🔤 正在安装思源宋体与 Symbols Nerd Font 到系统字体库...${NC}"
    mkdir -p "$FONTS_DIR"
    cp -f "$SCRIPT_DIR/fonts/"* "$FONTS_DIR/"
    if [ "$PLATFORM" = "linux" ] && command -v fc-cache >/dev/null 2>&1; then
      fc-cache -f "$FONTS_DIR" >/dev/null 2>&1 || true
    fi
    echo -e "${GREEN}✅ 字体安装完成！${NC}"
  fi

  # 8.1 刷新 macOS 字体数据库 (关键！)
  #     字体文件拷进 ~/Library/Fonts 后，fontd 不一定立刻收录它们。
  #     实测：拷贝后字体在磁盘上、system_profiler 也能看到，但
  #     CTFontManagerCopyAvailablePostScriptNames() 里查不到，
  #     于是 CoreText 解析 font_face 时静默回落到默认字体 —— 表现为
  #     "配了思源宋体但没生效"，且没有任何报错。
  if [ "$PLATFORM" = "macos" ]; then
    echo -e "${BLUE}🔄 正在刷新 macOS 字体数据库...${NC}"
    # touch 一下能触发 fontd 重新扫描该目录
    touch "$FONTS_DIR"/*.otf "$FONTS_DIR"/*.ttf 2>/dev/null || true
    sleep 2
    # 兜底：重启 fontd 强制全量重扫（fontd 会自动被 launchd 拉起）
    if pgrep -x fontd >/dev/null 2>&1; then
      killall fontd 2>/dev/null || true
      sleep 3
    fi
    echo -e "${GREEN}✅ 字体数据库已刷新${NC}"
  fi
fi

# 9. 导入个人自造词与历史词频记忆
if [ -d "$SCRIPT_DIR/sync" ]; then
  echo -e "${BLUE}🧠 正在导入历史词频与自造词记忆...${NC}"
  mkdir -p "$RIME_DIR/sync"
  cp -rf "$SCRIPT_DIR/sync/"* "$RIME_DIR/sync/" 2>/dev/null || true
  echo -e "${GREEN}✅ 词频快照就绪！${NC}"
fi

# 10. 配置 macOS 状态栏「Sync user data」点击自动 Push 到 GitHub 的监听服务
if [ "$PLATFORM" = "macos" ]; then
  echo -e "${BLUE}⚡ 配置「Sync user data」自动推送 GitHub 守护进程...${NC}"
  LAUNCH_AGENT_DIR="$HOME/Library/LaunchAgents"
  PLIST_FILE="$LAUNCH_AGENT_DIR/com.rheatin.rime.sync.plist"
  mkdir -p "$LAUNCH_AGENT_DIR"
  
  TARGET_REPO_DIR="$HOME/Rime_Config"
  if [ -d "$TARGET_REPO_DIR/.git" ]; then
    git -C "$TARGET_REPO_DIR" pull --no-rebase origin main 2>/dev/null || true
  elif [ ! -d "$TARGET_REPO_DIR" ]; then
    git clone "$REPO_URL" "$TARGET_REPO_DIR" 2>/dev/null || true
  fi
  chmod +x "$TARGET_REPO_DIR/sync.sh" 2>/dev/null || true

  INSTALLATION_ID="MBA"
  if [ -f "$RIME_DIR/installation.yaml" ]; then
    FOUND_ID=$(awk -F': ' '/installation_id:/ {gsub(/["'\'' ]/, "", $2); print $2}' "$RIME_DIR/installation.yaml" 2>/dev/null || true)
    if [ -n "$FOUND_ID" ]; then INSTALLATION_ID="$FOUND_ID"; fi
  fi
  DEVICE_SYNC_DIR="$RIME_DIR/sync/$INSTALLATION_ID"
  mkdir -p "$DEVICE_SYNC_DIR"

  sed -e "s|TARGET_SCRIPT_PATH|$TARGET_REPO_DIR/sync.sh|g" \
      -e "s|TARGET_SYNC_PATH|$RIME_DIR/sync|g" \
      -e "s|TARGET_DEVICE_SYNC_PATH|$DEVICE_SYNC_DIR|g" \
      "$SCRIPT_DIR/com.rheatin.rime.sync.plist" > "$PLIST_FILE"

  launchctl unload "$PLIST_FILE" 2>/dev/null || true
  launchctl load "$PLIST_FILE" 2>/dev/null || true
  echo -e "${GREEN}✅ 菜单栏同步监听已激活！${NC}"
fi

# 10.1 调用平台专一化瘦身清理，移除所有冗余与非本系统方案
if [ -f "$SCRIPT_DIR/clean.sh" ]; then
  bash "$SCRIPT_DIR/clean.sh"
fi

# 11. 重新部署与合并词频生效
echo -e "${BLUE}🔄 触发 Rime 重新部署与词频合并...${NC}"
if [ "$PLATFORM" = "macos" ]; then
  # 确定性部署：不依赖 Squirrel 进程当时是否在运行。
  # `Squirrel --reload` 只是给运行中的进程发通知，进程没跑就静默丢失，
  # 会导致 build/ 缺失、build/squirrel.yaml 缺失（分应用切换整体失效）。
  if [ -f "$SCRIPT_DIR/deploy.sh" ]; then
    RIME_DIR="$RIME_DIR" bash "$SCRIPT_DIR/deploy.sh" || true
  fi
  if [ -f "$SQUIRREL_APP/Contents/MacOS/Squirrel" ]; then
    "$SQUIRREL_APP/Contents/MacOS/Squirrel" --sync || true
  fi
elif [ "$PLATFORM" = "linux" ]; then
  if [ -f "$SCRIPT_DIR/deploy.sh" ]; then
    RIME_DIR="$RIME_DIR" bash "$SCRIPT_DIR/deploy.sh" || true
  fi
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
echo -e "${GREEN}🎉 恭喜！Rime 白霜拼音 + 万象语言模型 + MoeType 已全自动部署完毕！${NC}"
echo -e "${GREEN}🧠 个人自造词与词频记忆已完成合并恢复！${NC}"
if [ "$PLATFORM" = "macos" ]; then
  echo -e "${YELLOW}提示：今后点击输入法菜单的「Sync user data」将自动备份推送到 GitHub！${NC}"
fi
echo -e "${BLUE}====================================================${NC}"
