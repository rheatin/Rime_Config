#!/usr/bin/env bash
# ==============================================================================
# Rime 用户词频与自造词一键/自动同步备份脚本 (支持交互式密码与 AES-256 隐私加密)
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
RESET_PASS=false

for arg in "$@"; do
  if [ "$arg" = "--auto" ]; then
    IS_AUTO=true
  elif [ "$arg" = "--reset-pass" ]; then
    RESET_PASS=true
  fi
done

# 获取用户同步口令（支持交互输入、系统钥匙串记忆与免输）
get_vault_pass() {
  # 1. 优先从环境变量读取
  if [ -n "$RIME_VAULT_PASS" ]; then
    echo "$RIME_VAULT_PASS"
    return 0
  fi

  # 2. 如果请求重置密码，清除本地缓存
  if [ "$RESET_PASS" = true ]; then
    if [ "$(uname -s)" = "Darwin" ]; then
      security delete-generic-password -s "rime-vault" 2>/dev/null || true
    fi
    rm -f "$RIME_DIR/.vault_pass" 2>/dev/null || true
  else
    # 尝试从 macOS 原生钥匙串读取
    if [ "$(uname -s)" = "Darwin" ]; then
      local KC_PASS
      KC_PASS=$(security find-generic-password -s "rime-vault" -w 2>/dev/null || true)
      if [ -n "$KC_PASS" ]; then
        echo "$KC_PASS"
        return 0
      fi
    fi

    # 尝试从本地受保护文件读取
    if [ -f "$RIME_DIR/.vault_pass" ] && [ -s "$RIME_DIR/.vault_pass" ]; then
      cat "$RIME_DIR/.vault_pass"
      return 0
    fi
  fi

  # 3. 后台无感自动模式下，无法弹出交互输入
  if [ "$IS_AUTO" = true ] || [ ! -t 0 ]; then
    return 1
  fi

  # 4. 交互式提示用户输入密码
  echo "" >&2
  echo -e "${BLUE}====================================================${NC}" >&2
  echo -e "${YELLOW}🔒 Rime 隐私数据加密同步 (首次配置 / 验证)${NC}" >&2
  echo -e "请输入你的同步密码 (Windows 与 Mac 端输入相同密码即可自动互通)：" >&2
  read -s -p "🔑 请输入密码: " INPUT_PASS >&2
  echo "" >&2
  if [ -z "$INPUT_PASS" ]; then
    echo -e "${YELLOW}⚠️ 未输入密码，本次跳过加密隐私数据同步。${NC}" >&2
    return 1
  fi

  # 询问是否记住密码
  read -p "是否记住该密码（下次同步免输入，将安全存入系统钥匙串）[Y/n]? " REMEMBER >&2
  REMEMBER=${REMEMBER:-Y}
  if [[ "$REMEMBER" =~ ^[Yy]$ ]]; then
    if [ "$(uname -s)" = "Darwin" ]; then
      security add-generic-password -s "rime-vault" -a "$USER" -w "$INPUT_PASS" -U 2>/dev/null || true
    fi
    echo "$INPUT_PASS" > "$RIME_DIR/.vault_pass"
    chmod 600 "$RIME_DIR/.vault_pass" 2>/dev/null || true
    echo -e "${GREEN}✅ 密码已安全存储到系统钥匙串，后续同步将全自动免密！${NC}" >&2
  fi
  echo -e "${BLUE}====================================================${NC}" >&2
  echo "" >&2

  echo "$INPUT_PASS"
  return 0
}

# 1. 先拉取远程最新变更
cd "$SCRIPT_DIR"
if [ -d "$SCRIPT_DIR/.git" ]; then
  git pull --no-rebase origin main 2>/dev/null || true
fi

# 1.1 自动解密远端同步的隐私数据 (若存在密文包)
if [ -f "$SCRIPT_DIR/vault.enc" ]; then
  VAULT_PASS=$(get_vault_pass || true)
  if [ -n "$VAULT_PASS" ]; then
    TMP_DEC="/tmp/rime_vault_dec_$$.tar.gz"
    if echo "$VAULT_PASS" | openssl enc -d -aes-256-cbc -salt -pbkdf2 -pass stdin -in "$SCRIPT_DIR/vault.enc" -out "$TMP_DEC" 2>/dev/null; then
      tar -xzf "$TMP_DEC" -C "$SCRIPT_DIR" 2>/dev/null || true
      rm -f "$TMP_DEC"
      echo -e "${GREEN}🔓 隐私短语与自造词已成功解密同步！${NC}"
    fi
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
VAULT_PASS=$(get_vault_pass || true)
if [ -n "$VAULT_PASS" ]; then
  TMP_TAR="/tmp/rime_vault_$$.tar.gz"
  tar -czf "$TMP_TAR" -C "$SCRIPT_DIR" custom_phrase.txt sync 2>/dev/null || true
  if [ -f "$TMP_TAR" ]; then
    echo "$VAULT_PASS" | openssl enc -aes-256-cbc -salt -pbkdf2 -pass stdin -in "$TMP_TAR" -out "$SCRIPT_DIR/vault.enc" 2>/dev/null || true
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
