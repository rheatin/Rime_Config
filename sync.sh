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

# 1. 先拉取远程最新变更 (避免冲突)
cd "$SCRIPT_DIR"
if [ -d "$SCRIPT_DIR/.git" ]; then
  git pull --rebase origin main 2>/dev/null || true
fi

# 2. 如果是手动运行，先触发 Squirrel 导出
if [ "$IS_AUTO" = false ]; then
  echo -e "${BLUE}🔄 2. 正在触发 Rime 导出最新自造词与词频记忆...${NC}"
  if [ -f "/Library/Input Methods/Squirrel.app/Contents/MacOS/Squirrel" ]; then
    "/Library/Input Methods/Squirrel.app/Contents/MacOS/Squirrel" --sync || true
    sleep 1
  elif command -v rime_dict_manager >/dev/null 2>&1; then
    rime_dict_manager -s || true
  fi
fi

# 3. 在 macOS 上自动提取苹果系统键盘「文本替换 (自定义短语)」
APPLE_DB="$HOME/Library/KeyboardServices/TextReplacements.db"
if [ "$(uname -s)" = "Darwin" ] && [ -f "$APPLE_DB" ]; then
  echo -e "${BLUE}🍎 3. 检测到系统文本替换数据库，正在拉取最新系统短语...${NC}"
  SYNCED_COUNT=$(python3 -c "
import sqlite3, os

db_path = '$APPLE_DB'
try:
    conn = sqlite3.connect(db_path)
    cur = conn.cursor()
    cur.execute('SELECT ZSHORTCUT, ZPHRASE FROM ZTEXTREPLACEMENTENTRY WHERE ZWASDELETED = 0;')
    rows = cur.fetchall()

    qwert_lines = [
        '# Rime table',
        '# coding: utf-8',
        '#@/db_name\tcustom_phrase.txt',
        '#@/db_type\ttabledb',
        '#',
        '# 苹果系统「文本替换」短语自动同步 (全拼 26键)',
        '# 格式：文字<Tab>编码<Tab>权重',
        '#',
        '# 此行之后不能写注释',
        ''
    ]

    count = 0
    for sc, phrase in rows:
        sc = sc.strip()
        phrase = phrase.strip()
        if not sc or not phrase:
            continue
        qwert_lines.append(f'{phrase}\t{sc}\t1000')
        count += 1

    content_qwert = '\n'.join(qwert_lines) + '\n'

    for p in ['$SCRIPT_DIR/custom_phrase.txt', '$RIME_DIR/custom_phrase.txt']:
        if os.path.isdir(os.path.dirname(p)):
            with open(p, 'w', encoding='utf-8') as f:
                f.write(content_qwert)

    print(count)
except Exception as e:
    print('0')
" 2>/dev/null || echo "0")
  if [ "$SYNCED_COUNT" -gt 0 ] 2>/dev/null; then
    echo -e "${GREEN}✅ 成功同步 $SYNCED_COUNT 条系统短语（置顶第 1 位）！${NC}"
    if [ -f "/Library/Input Methods/Squirrel.app/Contents/MacOS/Squirrel" ]; then
      "/Library/Input Methods/Squirrel.app/Contents/MacOS/Squirrel" --reload || true
    fi
  fi
fi

# 4. 归档词频文件到仓库
echo -e "${BLUE}📦 4. 正在归档词频文件到仓库...${NC}"
mkdir -p "$SCRIPT_DIR/sync"
if [ -d "$RIME_DIR/sync" ]; then
  cp -rf "$RIME_DIR/sync/"* "$SCRIPT_DIR/sync/" 2>/dev/null || true
  # 避免包含无关的大体积 yaml 缓存
  find "$SCRIPT_DIR/sync" -type f ! -name "*.userdb.txt" -delete 2>/dev/null || true
  echo -e "${GREEN}✅ 词频快照归档完成！${NC}"
fi

# 5. 提交并推送到 GitHub
echo -e "${BLUE}🚀 5. 正在推送到远程 GitHub 仓库...${NC}"
cd "$SCRIPT_DIR"
git add sync/ custom_phrase.txt 2>/dev/null || true

if git diff-index --quiet HEAD --; then
  echo -e "${GREEN}✨ 词频与短语已是最新，无新增改动。${NC}"
else
  git commit -m "sync: 自动同步用户词频与系统文本替换短语 $(date '+%Y-%m-%d %H:%M:%S')"
  
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
