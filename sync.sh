#!/usr/bin/env bash
# ==============================================================================
# Rime 用户词频与自造词一键/自动同步备份脚本
# ==============================================================================

set -e

GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RIME_DIR="$HOME/Library/Rime"
[ "$(uname -s)" = "Linux" ] && RIME_DIR="$HOME/.local/share/rime"

IS_AUTO=false
if [ "$1" = "--auto" ]; then
  IS_AUTO=true
fi

# 1. 如果是手动运行，先触发 Squirrel 导出
if [ "$IS_AUTO" = false ]; then
  echo -e "${BLUE}🔄 1. 正在触发 Rime 导出最新自造词与词频记忆...${NC}"
  if [ -f "/Library/Input Methods/Squirrel.app/Contents/MacOS/Squirrel" ]; then
    "/Library/Input Methods/Squirrel.app/Contents/MacOS/Squirrel" --sync || true
    sleep 1
  elif command -v rime_dict_manager >/dev/null 2>&1; then
    rime_dict_manager -s || true
  fi
fi

# 2. 归档词频文件到仓库
echo -e "${BLUE}📦 2. 正在归档词频文件到仓库...${NC}"
mkdir -p "$SCRIPT_DIR/sync"
if [ -d "$RIME_DIR/sync" ]; then
  cp -rf "$RIME_DIR/sync/"* "$SCRIPT_DIR/sync/" 2>/dev/null || true
  # 避免包含无关的大体积 yaml 缓存
  find "$SCRIPT_DIR/sync" -type f ! -name "*.userdb.txt" -delete 2>/dev/null || true
  echo -e "${GREEN}✅ 词频快照归档完成！${NC}"
fi

# 3. 提交并推送到 GitHub
echo -e "${BLUE}🚀 3. 正在推送到远程 GitHub 仓库...${NC}"
cd "$SCRIPT_DIR"
git add sync/

if git diff-index --quiet HEAD --; then
  echo -e "${GREEN}✨ 词频已是最新，无新增改动。${NC}"
else
  git commit -m "sync: 自动同步用户词频与自造词记忆 $(date '+%Y-%m-%d %H:%M:%S')"
  
  # 尝试推送（网络失败时重试最多 3 次）
  PUSH_SUCCESS=false
  for i in {1..3}; do
    if git push origin main; then
      PUSH_SUCCESS=true
      break
    else
      echo "推送重试 ($i/3)..."
      sleep 2
    fi
  done

  if [ "$PUSH_SUCCESS" = true ]; then
    echo -e "${GREEN}🎉 词频已成功推送到远程仓库！${NC}"
    # macOS 原生系统通知
    if [ "$(uname -s)" = "Darwin" ]; then
      osascript -e 'display notification "自造词与词频已成功备份到 GitHub！" with title "Rime 词频同步"' 2>/dev/null || true
    fi
  else
    echo "⚠️ 推送失败，请检查网络连接。"
  fi
fi
