#!/usr/bin/env bash
# ==============================================================================
# Rime 用户词频与自造词一键同步备份脚本
# ==============================================================================

set -e

GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RIME_DIR="$HOME/Library/Rime"
[ "$(uname -s)" = "Linux" ] && RIME_DIR="$HOME/.local/share/rime"

echo -e "${BLUE}🔄 1. 正在触发 Rime 导出最新自造词与词频记忆...${NC}"
if [ -f "/Library/Input Methods/Squirrel.app/Contents/MacOS/Squirrel" ]; then
  "/Library/Input Methods/Squirrel.app/Contents/MacOS/Squirrel" --sync || true
elif command -v rime_dict_manager >/dev/null 2>&1; then
  rime_dict_manager -s || true
fi

echo -e "${BLUE}📦 2. 正在归档词频文件到仓库...${NC}"
mkdir -p "$SCRIPT_DIR/sync"
if [ -d "$RIME_DIR/sync" ]; then
  cp -rf "$RIME_DIR/sync/"* "$SCRIPT_DIR/sync/" 2>/dev/null || true
  # 避免包含无关的大体积 yaml 缓存
  find "$SCRIPT_DIR/sync" -type f ! -name "*.userdb.txt" -delete 2>/dev/null || true
  echo -e "${GREEN}✅ 词频快照归档完成！${NC}"
fi

echo -e "${BLUE}🚀 3. 正在推送到远程 GitHub 仓库...${NC}"
cd "$SCRIPT_DIR"
git add sync/
if git diff-index --quiet HEAD --; then
  echo -e "${GREEN}✨ 词频已是最新，无新增改动。${NC}"
else
  git commit -m "sync: 自动同步用户词频与自造词记忆 $(date '+%Y-%m-%d %H:%M:%S')"
  git push origin main
  echo -e "${GREEN}🎉 词频已成功推送到远程仓库！${NC}"
fi
