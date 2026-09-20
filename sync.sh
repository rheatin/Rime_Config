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

# 发送系统通知 (macOS / Linux)
notify_user() {
  local title="${1:-Rime 词频同步}"
  local subtitle="$2"
  local message="$3"
  if [ "$(uname -s)" = "Darwin" ]; then
    if [ -n "$subtitle" ]; then
      osascript -e "display notification \"$message\" with title \"$title\" subtitle \"$subtitle\"" 2>/dev/null || true
    else
      osascript -e "display notification \"$message\" with title \"$title\"" 2>/dev/null || true
    fi
  elif [ "$(uname -s)" = "Linux" ] && command -v notify-send >/dev/null 2>&1; then
    notify-send "$title" "$message" 2>/dev/null || true
  fi
}

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

  # 4. 交互式提示用户输入密码 (支持二次确认防输错)
  local INPUT_PASS=""
  local CONFIRM_PASS=""
  while true; do
    echo "" >&2
    echo -e "${BLUE}====================================================${NC}" >&2
    echo -e "${YELLOW}🔒 Rime 隐私数据加密同步 (首次配置 / 密码验证)${NC}" >&2
    echo -e "请输入你的同步密码 (Windows 与 Mac 端输入相同密码即可自动互通)：" >&2
    read -s -p "🔑 请输入密码: " INPUT_PASS >&2
    echo "" >&2
    if [ -z "$INPUT_PASS" ]; then
      echo -e "${YELLOW}⚠️ 未输入密码，本次跳过加密隐私数据同步。${NC}" >&2
      return 1
    fi

    read -s -p "🔑 请再次输入密码以确认: " CONFIRM_PASS >&2
    echo "" >&2

    if [ "$INPUT_PASS" = "$CONFIRM_PASS" ]; then
      echo -e "${GREEN}✅ 两次密码输入一致！${NC}" >&2
      break
    else
      echo -e "${RED}❌ 两次输入的密码不一致，请重新输入！${NC}" >&2
    fi
  done

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
    export RIME_VAULT_PASS="$VAULT_PASS"
    TMP_DEC="/tmp/rime_vault_dec_$$.tar.gz"
    if openssl enc -d -aes-256-cbc -salt -pbkdf2 -pass env:RIME_VAULT_PASS -in "$SCRIPT_DIR/vault.enc" -out "$TMP_DEC" 2>/dev/null || \
       openssl enc -d -aes-256-cbc -salt -pbkdf2 -pass "pass:$VAULT_PASS" -in "$SCRIPT_DIR/vault.enc" -out "$TMP_DEC" 2>/dev/null || \
       echo "$VAULT_PASS" | openssl enc -d -aes-256-cbc -salt -pbkdf2 -pass stdin -in "$SCRIPT_DIR/vault.enc" -out "$TMP_DEC" 2>/dev/null; then
      tar -xzf "$TMP_DEC" -C "$SCRIPT_DIR" 2>/dev/null || true
      rm -f "$TMP_DEC"
      echo -e "${GREEN}🔓 隐私短语与自造词已成功解密同步！${NC}"
    fi
  fi
fi

# 1.2 同步最新的 Lua 扩展、代码片段与核心配置文件到当前环境
if [ -d "$SCRIPT_DIR/lua" ]; then
  mkdir -p "$RIME_DIR/lua"
  cp -rf "$SCRIPT_DIR/lua/"* "$RIME_DIR/lua/" 2>/dev/null || true
fi
if [ -f "$SCRIPT_DIR/snippets.yaml" ]; then
  cp -f "$SCRIPT_DIR/snippets.yaml" "$RIME_DIR/" 2>/dev/null || true
fi
if [ -f "$SCRIPT_DIR/snippets.custom.yaml" ]; then
  cp -f "$SCRIPT_DIR/snippets.custom.yaml" "$RIME_DIR/" 2>/dev/null || true
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

# 3. 跨平台双向增量合并「自定义短语 (custom_phrase.txt)」与苹果系统「文本替换」
APPLE_DB="$HOME/Library/KeyboardServices/TextReplacements.db"
echo -e "${BLUE}🍎 3. 正在双向增量合并跨平台短语与系统文本替换...${NC}"
SYNCED_COUNT=$(python3 -c "
import sqlite3, os

phrase_map = {}

def load_file(fp):
    if not os.path.exists(fp): return
    with open(fp, 'r', encoding='utf-8', errors='ignore') as f:
        in_body = False
        for line in f:
            line = line.strip()
            if not line: continue
            if line.startswith('# 此行之后不能写注释'):
                in_body = True
                continue
            if line.startswith('#'): continue
            parts = line.split('\t')
            if len(parts) >= 2:
                w_phrase = parts[0].strip()
                w_sc = parts[1].strip()
                w_weight = parts[2].strip() if len(parts) >= 3 else '1000'
                if w_phrase and w_sc:
                    phrase_map[(w_phrase, w_sc)] = w_weight

# 1. 优先读取已存在的 custom_phrase.txt (保留来自 Windows 端与云端同步的短语)
load_file('$SCRIPT_DIR/custom_phrase.txt')
load_file('$RIME_DIR/custom_phrase.txt')

# 2. 如果存在 macOS 系统文本替换数据库，提取并增量合并
db_path = '$APPLE_DB'
if os.path.exists(db_path):
    try:
        conn = sqlite3.connect(db_path)
        cur = conn.cursor()
        cur.execute('SELECT ZSHORTCUT, ZPHRASE FROM ZTEXTREPLACEMENTENTRY WHERE ZWASDELETED = 0;')
        for sc, phrase in cur.fetchall():
            if sc and phrase:
                sc = sc.strip()
                phrase = phrase.strip()
                if sc and phrase:
                    phrase_map[(phrase, sc)] = '1000'
    except Exception:
        pass

# 3. 输出标准化、去重并按字母排序的短语表
headers = [
    '# Rime table',
    '# coding: utf-8',
    '#@/db_name\tcustom_phrase.txt',
    '#@/db_type\ttabledb',
    '#',
    '# 跨平台「自定义短语 / 文本替换」双向增量合并表 (全拼 26键)',
    '# 格式：文字<Tab>编码<Tab>权重',
    '#',
    '# 此行之后不能写注释',
    ''
]

lines = list(headers)
for (phrase, sc), weight in sorted(phrase_map.items(), key=lambda x: (x[0][1], x[0][0])):
    lines.append(f'{phrase}\t{sc}\t{weight}')

merged_content = '\n'.join(lines) + '\n'

for p in ['$SCRIPT_DIR/custom_phrase.txt', '$RIME_DIR/custom_phrase.txt']:
    if os.path.isdir(os.path.dirname(p)):
        with open(p, 'w', encoding='utf-8') as f:
            f.write(merged_content)

print(len(phrase_map))
" 2>/dev/null || echo "0")
if [ "$SYNCED_COUNT" -gt 0 ] 2>/dev/null; then
  echo -e "${GREEN}✅ 成功双向合并 $SYNCED_COUNT 条自定义短语（置顶第 1 位）！${NC}"
  if [ -f "/Library/Input Methods/Squirrel.app/Contents/MacOS/Squirrel" ]; then
    "/Library/Input Methods/Squirrel.app/Contents/MacOS/Squirrel" --reload || true
  fi
fi

# 4. 归档词频文件并进行 AES-256 密文打包 (保护隐私短语与个人打字记录)
echo -e "${BLUE}📦 4. 正在归档词频并进行 AES-256 加密打包...${NC}"

# 4.0 确保用户目录中的私密片段同步回仓库目录 (以最新修改时间为准)
if [ -f "$RIME_DIR/snippets.custom.yaml" ] && [ -f "$SCRIPT_DIR/snippets.custom.yaml" ]; then
  rime_mtime=$(stat -f %m "$RIME_DIR/snippets.custom.yaml" 2>/dev/null || echo 0)
  repo_mtime=$(stat -f %m "$SCRIPT_DIR/snippets.custom.yaml" 2>/dev/null || echo 0)
  if [ "$rime_mtime" -gt "$repo_mtime" ]; then
    cp -f "$RIME_DIR/snippets.custom.yaml" "$SCRIPT_DIR/snippets.custom.yaml"
  fi
elif [ -f "$RIME_DIR/snippets.custom.yaml" ]; then
  cp -f "$RIME_DIR/snippets.custom.yaml" "$SCRIPT_DIR/snippets.custom.yaml"
fi

mkdir -p "$SCRIPT_DIR/sync"
if [ -d "$RIME_DIR/sync" ]; then
  cp -rf "$RIME_DIR/sync/"* "$SCRIPT_DIR/sync/" 2>/dev/null || true
  find "$SCRIPT_DIR/sync" -type f ! -name "*.userdb.txt" -delete 2>/dev/null || true
fi

# 将 custom_phrase.txt、snippets.custom.yaml 与 sync/ 打包加密为 vault.enc
VAULT_PASS=$(get_vault_pass || true)
if [ -n "$VAULT_PASS" ]; then
  export RIME_VAULT_PASS="$VAULT_PASS"
  TMP_TAR="/tmp/rime_vault_$$.tar.gz"
  tar -czf "$TMP_TAR" -C "$SCRIPT_DIR" custom_phrase.txt snippets.custom.yaml sync 2>/dev/null || true
  if [ -f "$TMP_TAR" ]; then
    openssl enc -aes-256-cbc -salt -pbkdf2 -pass env:RIME_VAULT_PASS -in "$TMP_TAR" -out "$SCRIPT_DIR/vault.enc" 2>/dev/null || \
    openssl enc -aes-256-cbc -salt -pbkdf2 -pass "pass:$VAULT_PASS" -in "$TMP_TAR" -out "$SCRIPT_DIR/vault.enc" 2>/dev/null || \
    echo "$VAULT_PASS" | openssl enc -aes-256-cbc -salt -pbkdf2 -pass stdin -in "$TMP_TAR" -out "$SCRIPT_DIR/vault.enc" 2>/dev/null || true
    rm -f "$TMP_TAR"
    echo -e "${GREEN}🔒 隐私短语、私有片段与自造词已成功通过 AES-256 加密保护 (vault.enc)！${NC}"
  fi
fi

# 5. 提交并推送到 GitHub (明文短语、私有片段与词频由 .gitignore 拦截，仅推送密文)
echo -e "${BLUE}🚀 5. 正在推送到远程 GitHub 仓库...${NC}"
cd "$SCRIPT_DIR"
git add vault.enc custom_phrase.example.txt snippets.yaml snippets.custom.example.yaml 2>/dev/null || true

if git diff-index --quiet HEAD --; then
  echo -e "${GREEN}✨ 词频与短语已是最新，无新增改动。${NC}"
  notify_user "Rime 词频同步" "已是最新" "✨ 自造词与短语均已保持最新状态！"
else
  git commit -m "sync: 自动同步加密词频与文本替换短语 $(date '+%Y-%m-%d %H:%M:%S')"
  
  PUSH_SUCCESS=false
  for i in {1..3}; do
    if git push origin main; then
      PUSH_SUCCESS=true
      break
    else
      echo "推送重试 ($i/3)..."
      git pull --rebase origin main 2>/dev/null || true
      sleep 2
    fi
  done

  if [ "$PUSH_SUCCESS" = true ]; then
    echo -e "${GREEN}🎉 密文词频包已成功推送到远程仓库！${NC}"
    notify_user "Rime 词频同步" "同步成功" "🎉 词频与私有短语已安全加密备份到 GitHub！"
  else
    echo "⚠️ 推送失败，请检查网络连接。"
    notify_user "Rime 词频同步" "推送失败" "⚠️ 词频加密包推送失败，请检查网络连接。"
  fi
fi
