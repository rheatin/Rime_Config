#!/usr/bin/env bash
# ==============================================================================
# Rime 词库底座与 AI 语言模型独立升级脚本 (update.sh)
# 职责：
#   1. 读取用户本地画像 (.rime_profile)，仅追更用户选定的方案与组件
#   2. 自动拉取/比对上游词库底座 (rime-frost / rime-ice / 自定义方案)
#   3. 智能比对 GitHub Release Digest SHA256，增量下载万象大模型与 MoeType
#   4. 触发动态配置生成引擎与智能瘦身，重新编译部署生效
# ==============================================================================

set -e

GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${BLUE}====================================================${NC}"
echo -e "${GREEN} 🔄 开始升级 Rime 词库底座、语言模型与扩展组件       ${NC}"
echo -e "${BLUE}====================================================${NC}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROFILE_FILE="$SCRIPT_DIR/.rime_profile"

OS="$(uname -s)"
if [ "$OS" = "Darwin" ]; then
  PLATFORM="macos"
  RIME_DIR="$HOME/Library/Rime"
elif [ "$OS" = "Linux" ]; then
  PLATFORM="linux"
  RIME_DIR="$HOME/.local/share/rime"
else
  echo -e "${RED}❌ 暂不支持的操作系统：$OS (Windows 请使用 update.ps1)${NC}"
  exit 1
fi

[ -f "$PROFILE_FILE" ] || PROFILE_FILE="$RIME_DIR/.rime_profile"
if [ ! -f "$PROFILE_FILE" ]; then
  echo -e "${YELLOW}⚠️ 未检测到 .rime_profile 画像配置，正在初始化默认画像...${NC}"
  cat << EOF > "$SCRIPT_DIR/.rime_profile"
RIME_FRAMEWORK="rime-frost"
RIME_CUSTOM_REPO=""
RIME_SCHEMA="rime_frost"
RIME_MODEL="wanxiang_lts"
RIME_CUSTOM_MODEL_URL=""
RIME_ENABLE_MOE=true
RIME_ENABLE_CELLS=true
RIME_ENABLE_TENCENT=false
RIME_CUSTOM_DICT_URL=""
EOF
  PROFILE_FILE="$SCRIPT_DIR/.rime_profile"
fi

# 读取画像
RIME_FRAMEWORK="$(awk -F'=' '/^RIME_FRAMEWORK=/ {gsub(/["'\'' ]/, "", $2); print $2}' "$PROFILE_FILE" 2>/dev/null || echo "rime-frost")"
RIME_CUSTOM_REPO="$(awk -F'=' '/^RIME_CUSTOM_REPO=/ {gsub(/["'\'' ]/, "", $2); print $2}' "$PROFILE_FILE" 2>/dev/null || echo "")"
RIME_SCHEMA="$(awk -F'=' '/^RIME_SCHEMA=/ {gsub(/["'\'' ]/, "", $2); print $2}' "$PROFILE_FILE" 2>/dev/null || echo "rime_frost")"
RIME_MODEL="$(awk -F'=' '/^RIME_MODEL=/ {gsub(/["'\'' ]/, "", $2); print $2}' "$PROFILE_FILE" 2>/dev/null || echo "wanxiang_lts")"
RIME_ENABLE_MOE="$(awk -F'=' '/^RIME_ENABLE_MOE=/ {gsub(/["'\'' ]/, "", $2); print $2}' "$PROFILE_FILE" 2>/dev/null || echo "true")"

echo -e "📋 当前用户偏好画像:"
echo -e "   • 底座框架: $RIME_FRAMEWORK"
echo -e "   • 当前方案: $RIME_SCHEMA"
echo -e "   • 语言模型: $RIME_MODEL"
echo -e "   • 萌娘百科: $RIME_ENABLE_MOE"

# 1. 尝试同步上游代码与工具脚本更新 (若配置了 upstream)
if [ -d "$SCRIPT_DIR/.git" ]; then
  if git -C "$SCRIPT_DIR" remote | grep -q "^upstream$"; then
    echo -e "${BLUE}📡 正在检查上游主仓库更新...${NC}"
    git -C "$SCRIPT_DIR" fetch upstream main 2>/dev/null || true
    git -C "$SCRIPT_DIR" merge --no-edit upstream/main 2>/dev/null || true
  fi
fi

# 2. 追更底座词库
TARGET_FRAMEWORK_URL="https://github.com/gaboolic/rime-frost.git"
if [ "$RIME_FRAMEWORK" = "rime-ice" ]; then
  TARGET_FRAMEWORK_URL="https://github.com/iDvel/rime-ice.git"
  echo -e "${BLUE}❄️  正在更新 雾凇拼音 (rime-ice) 底座词库...${NC}"
elif [ "$RIME_FRAMEWORK" = "custom" ] && [ -n "$RIME_CUSTOM_REPO" ]; then
  TARGET_FRAMEWORK_URL="$RIME_CUSTOM_REPO"
  echo -e "${BLUE}📦 正在更新 自定义方案底座 ($RIME_CUSTOM_REPO)...${NC}"
else
  echo -e "${BLUE}❄️  正在更新 白霜拼音 (rime-frost) 底座词库...${NC}"
fi

TEMP_FW="$(mktemp -d)"
CLONE_SUCCESS=false
CLONE_URLS=(
  "$TARGET_FRAMEWORK_URL"
  "https://ghproxy.net/$TARGET_FRAMEWORK_URL"
  "https://ghfast.top/$TARGET_FRAMEWORK_URL"
)

for cu in "${CLONE_URLS[@]}"; do
  if git clone --depth=1 "$cu" "$TEMP_FW" 2>/dev/null; then
    cp -rf "$TEMP_FW/"* "$RIME_DIR/"
    cp -rf "$TEMP_FW/.git" "$RIME_DIR/" 2>/dev/null || true
    echo -e "${GREEN}✅ 底座词库更新完成！${NC}"
    CLONE_SUCCESS=true
    break
  fi
done

rm -rf "$TEMP_FW" 2>/dev/null || true
if [ "$CLONE_SUCCESS" = false ]; then
  echo -e "${YELLOW}⚠️ 底座网络同步失败，保留本地现存词库继续检查其余组件...${NC}"
fi

# 3. 追更万象语言模型 (若用户启用)
if [ "$RIME_MODEL" = "wanxiang_lts" ]; then
  MODEL_TARGET="$RIME_DIR/wanxiang-lts-zh-hans.gram"
  WANXIANG_API_URL="https://api.github.com/repos/amzxyz/rime-wanxiang-data/releases/tags/LTS"
  WANXIANG_MODEL_URL="https://github.com/amzxyz/rime-wanxiang-data/releases/download/LTS/wanxiang-lts-zh-hans.gram"
  FALLBACK_WANXIANG_SHA256="1635588006d79cc6955fbcf3d8de12822a36856eb5408735a8b4a2952b16cadf"

  calc_sha256() {
    if command -v shasum >/dev/null 2>&1; then shasum -a 256 "$1" | awk '{print $1}';
    elif command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | awk '{print $1}';
    else echo ""; fi
  }

  echo -e "${BLUE}🌐 正在查询万象语言模型 GitHub 远程 Digest SHA256...${NC}"
  REMOTE_SHA=$(python3 -c "
import urllib.request, json
try:
    req = urllib.request.Request('$WANXIANG_API_URL', headers={'User-Agent': 'Mozilla/5.0'})
    with urllib.request.urlopen(req, timeout=8) as r:
        d = json.loads(r.read())
        for a in d.get('assets', []):
            if a.get('name') == 'wanxiang-lts-zh-hans.gram':
                dg = a.get('digest', '')
                if dg.startswith('sha256:'): print(dg.split('sha256:')[1].strip()); break
except: pass
" 2>/dev/null || echo "")
  REMOTE_SHA="${REMOTE_SHA:-$FALLBACK_WANXIANG_SHA256}"

  if [ -f "$MODEL_TARGET" ] && [ "$(calc_sha256 "$MODEL_TARGET")" = "$REMOTE_SHA" ]; then
    echo -e "${GREEN}✅ 万象语言模型已是最新版本，跳过下载！${NC}"
  else
    echo -e "${BLUE}🧠 正在下载最新万象 (Wanxiang) LTS 语言模型 (~400MB)...${NC}"
    DOWNLOAD_URLS=("$WANXIANG_MODEL_URL" "https://ghproxy.net/$WANXIANG_MODEL_URL" "https://ghfast.top/$WANXIANG_MODEL_URL")
    DOWNLOAD_OK=false
    for u in "${DOWNLOAD_URLS[@]}"; do
      if curl -fL --retry 3 --retry-delay 2 -C - "$u" -o "$MODEL_TARGET.tmp" 2>/dev/null; then
        if [ "$(calc_sha256 "$MODEL_TARGET.tmp")" = "$REMOTE_SHA" ]; then
          mv "$MODEL_TARGET.tmp" "$MODEL_TARGET"
          echo -e "${GREEN}✅ 万象语言模型更新完成！${NC}"
          DOWNLOAD_OK=true
          break
        else
          rm -f "$MODEL_TARGET.tmp"
        fi
      fi
    done
    [ "$DOWNLOAD_OK" = false ] && rm -f "$MODEL_TARGET.tmp" && echo -e "${YELLOW}⚠️ 语言模型拉取受阻，保留本地旧版继续执行。${NC}"
  fi
fi

# 4. 追更 MoeType 萌娘百科词库 (若用户启用)
if [ "$RIME_ENABLE_MOE" = "true" ]; then
  MOETYPE_API_URL="https://api.github.com/repos/suiginko/moetype/releases/latest"
  MOETYPE_RELEASE_URL="https://github.com/suiginko/moetype/releases/latest/download/toneless_moe.dict.yaml"
  TARGET_MOE="$RIME_DIR/moe.dict.yaml"
  MOE_DIGEST_FILE="$RIME_DIR/.moe_digest"

  echo -e "${BLUE}🌸 正在查询 MoeType 词库 GitHub 远程更新...${NC}"
  REMOTE_MOE_SHA=$(python3 -c "
import urllib.request, json
try:
    req = urllib.request.Request('$MOETYPE_API_URL', headers={'User-Agent': 'Mozilla/5.0'})
    with urllib.request.urlopen(req, timeout=8) as r:
        d = json.loads(r.read())
        for a in d.get('assets', []):
            if a.get('name') == 'toneless_moe.dict.yaml':
                dg = a.get('digest', '')
                if dg.startswith('sha256:'): print(dg.split('sha256:')[1].strip()); break
except: pass
" 2>/dev/null || echo "")

  SAVED_MOE_DIGEST=""
  [ -f "$MOE_DIGEST_FILE" ] && SAVED_MOE_DIGEST="$(cat "$MOE_DIGEST_FILE" 2>/dev/null | tr -d '[:space:]')"

  if [ -n "$REMOTE_MOE_SHA" ] && [ "$SAVED_MOE_DIGEST" = "$REMOTE_MOE_SHA" ] && [ -f "$TARGET_MOE" ]; then
    echo -e "${GREEN}✅ MoeType 萌娘百科词库已是最新，跳过下载！${NC}"
  else
    echo -e "${BLUE}🌸 正在拉取 MoeType 最新词库并进行动态去重...${NC}"
    RAW_MOE_DIR="$(mktemp -d)"
    RAW_MOE_TEMP="$RAW_MOE_DIR/moe_raw.dict.yaml"
    if curl -fsSL "$MOETYPE_RELEASE_URL" -o "$RAW_MOE_TEMP" 2>/dev/null; then
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
kept, removed = 0, 0
with open('$RAW_MOE_TEMP', 'r', encoding='utf-8') as fin, open(out_file, 'w', encoding='utf-8') as fout:
    in_b = False
    for line in fin:
        if line.strip() == '...': in_b = True; fout.write(line); continue
        if not in_b or not line.strip() or line.startswith('#'): fout.write(line); continue
        p = line.strip().split('\t')
        w = p[0].strip()
        if w in rime_words: removed += 1
        else: kept += 1; fout.write(line)
print(f'   去重完成：保留独有词条 {kept:,}，剔除重复词条 {removed:,}')
"
      rm -rf "$RAW_MOE_DIR" 2>/dev/null || true
      [ -n "$REMOTE_MOE_SHA" ] && echo "$REMOTE_MOE_SHA" > "$MOE_DIGEST_FILE"
      echo -e "${GREEN}✅ MoeType 动态去重完成！${NC}"
    else
      rm -rf "$RAW_MOE_DIR" 2>/dev/null || true
      echo -e "${YELLOW}⚠️ MoeType 下载受阻，保留本地旧版继续。${NC}"
    fi
  fi
fi

# 5. 重新生成动态配置并触发部署
if [ -f "$SCRIPT_DIR/tools/rime_generator.py" ]; then
  python3 "$SCRIPT_DIR/tools/rime_generator.py" >/dev/null 2>&1 || true
fi

# 6. 执行智能瘦身清理
if [ -f "$SCRIPT_DIR/clean.sh" ]; then
  bash "$SCRIPT_DIR/clean.sh" --quiet
fi

# 7. 触发确定性重新部署
if [ -f "$SCRIPT_DIR/deploy.sh" ]; then
  bash "$SCRIPT_DIR/deploy.sh"
fi

echo -e "\n${BLUE}====================================================${NC}"
echo -e "${GREEN}🎉 恭喜！Rime 方案底座、语言模型与扩展词库已全部升级完毕！${NC}"
echo -e "${BLUE}====================================================${NC}"
