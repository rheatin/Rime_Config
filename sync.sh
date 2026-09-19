#!/usr/bin/env bash
# ==============================================================================
# Rime 用户词频与自造词一键/自动同步备份脚本 (支持 AES-256 隐私加密保护)
# ==============================================================================

set -e

GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[0;33m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RIME_DIR="$HOME/Library/Rime"
[ "$(uname -s)" = "Linux" ] && RIME_DIR="$HOME/.local/share/rime"

IS_AUTO=false
if [ "$1" = "--auto" ]; then
  IS_AUTO=true
fi

VAULT_KEY_FILE="$RIME_DIR/.vault_key"

# 0. 检查并初始化本地专属 Vault 隐私密钥 (绝不上传 Git)
if [ ! -f "$VAULT_KEY_FILE" ] || [ ! -s "$VAULT_KEY_FILE" ]; then
  python3 -c "
import secrets
with open('$VAULT_KEY_FILE', 'w') as f:
    f.write(secrets.token_hex(16))
" 2>/dev/null || echo "rime_default_vault_key_2026" > "$VAULT_KEY_FILE"
  chmod 600 "$VAULT_KEY_FILE" 2>/dev/null || true
  if [ "$IS_AUTO" = false ]; then
    echo -e "${YELLOW}🔑 已为你生成专属隐私同步密钥：$VAULT_KEY_FILE${NC}"
    echo -e "${YELLOW}💡 提示：在 Windows 电脑上同步时，只需将该文件复制到 %APPDATA%\\Rime\\.vault_key 即可解密！${NC}"
  fi
fi

# 1. 先拉取远程最新变更
cd "$SCRIPT_DIR"
if [ -d "$SCRIPT_DIR/.git" ]; then
  git pull --no-rebase origin main 2>/dev/null || true
fi

# 1.1 自动解密远端同步的隐私数据 (若存在密文包且有本地密钥)
if [ -f "$SCRIPT_DIR/vault.enc" ] && [ -f "$VAULT_KEY_FILE" ]; then
  TMP_DEC="/tmp/rime_vault_dec_$$.tar.gz"
  if openssl enc -d -aes-256-cbc -salt -pbkdf2 -in "$SCRIPT_DIR/vault.enc" -out "$TMP_DEC" -pass file:"$VAULT_KEY_FILE" 2>/dev/null; then
    tar -xzf "$TMP_DEC" -C "$SCRIPT_DIR" 2>/dev/null || true
    rm -f "$TMP_DEC"
  fi
fi

# 1.2 自动执行平台专一化瘦身清理 (移除非本系统配置文件与冗余方案)
if [ -f "$SCRIPT_DIR/clean.sh" ]; then
  bash "$SCRIPT_DIR/clean.sh" --quiet 2>/dev/null || true
fi

# 1.3 同步最新的 Lua 扩展、代码片段与核心配置文件到当前环境
if [ -d "$SCRIPT_DIR/lua" ]; then
  mkdir -p "$RIME_DIR/lua"
  cp -rf "$SCRIPT_DIR/lua/"* "$RIME_DIR/lua/" 2>/dev/null || true
fi
if [ -f "$SCRIPT_DIR/snippets.txt" ]; then
  cp -f "$SCRIPT_DIR/snippets.txt" "$RIME_DIR/" 2>/dev/null || true
fi
cp -f "$SCRIPT_DIR/rime_frost.custom.yaml" "$RIME_DIR/" 2>/dev/null || true
cp -f "$SCRIPT_DIR/default.custom.yaml" "$RIME_DIR/" 2>/dev/null || true
if [ "$(uname -s)" = "Darwin" ]; then
  cp -f "$SCRIPT_DIR/squirrel.custom.yaml" "$RIME_DIR/" 2>/dev/null || true
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

# 4. 归档词频文件并进行 AES-256 密文打包 (保护隐私短语与个人打字记录)
echo -e "${BLUE}📦 4. 正在归档词频并进行 AES-256 加密打包...${NC}"
mkdir -p "$SCRIPT_DIR/sync"
if [ -d "$RIME_DIR/sync" ]; then
  cp -rf "$RIME_DIR/sync/"* "$SCRIPT_DIR/sync/" 2>/dev/null || true
  find "$SCRIPT_DIR/sync" -type f ! -name "*.userdb.txt" -delete 2>/dev/null || true
fi

# 将 custom_phrase.txt 与 sync/ 打包加密为 vault.enc
if [ -f "$VAULT_KEY_FILE" ]; then
  TMP_TAR="/tmp/rime_vault_$$.tar.gz"
  tar -czf "$TMP_TAR" -C "$SCRIPT_DIR" custom_phrase.txt sync 2>/dev/null || true
  if [ -f "$TMP_TAR" ]; then
    openssl enc -aes-256-cbc -salt -pbkdf2 -in "$TMP_TAR" -out "$SCRIPT_DIR/vault.enc" -pass file:"$VAULT_KEY_FILE" 2>/dev/null || true
    rm -f "$TMP_TAR"
    echo -e "${GREEN}🔒 隐私短语与自造词已成功通过 AES-256 加密保护 (vault.enc)！${NC}"
  fi
fi

# 5. 提交并推送到 GitHub (明文短语与词频由 .gitignore 拦截，仅推送密文)
echo -e "${BLUE}🚀 5. 正在推送到远程 GitHub 仓库...${NC}"
cd "$SCRIPT_DIR"
git add vault.enc custom_phrase.example.txt snippets.txt 2>/dev/null || true

if git diff-index --quiet HEAD --; then
  echo -e "${GREEN}✨ 词频与短语已是最新，无新增改动。${NC}"
else
  git commit -m "sync: 自动同步加密词频与文本替换短语 $(date '+%Y-%m-%d %H:%M:%S')"
  
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
    echo -e "${GREEN}🎉 密文词频包已成功推送到远程仓库！${NC}"
    if [ "$(uname -s)" = "Darwin" ]; then
      osascript -e 'display notification "自造词与短语已安全加密备份到 GitHub！" with title "Rime 词频同步"' 2>/dev/null || true
    fi
  else
    echo "⚠️ 推送失败，请检查网络连接。"
  fi
fi
