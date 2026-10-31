#!/usr/bin/env bash
# ==============================================================================
# Rime 确定性重新部署 (macOS / Linux 通用)
#
# 为什么需要这个脚本：
#   `Squirrel --reload` 只是向**正在运行的** Squirrel 进程发送一个分布式通知
#   (SquirrelReloadNotification)。如果 Squirrel 当时没在运行 (例如用户当前选中
#   的输入源是 ABC)，这条通知会静默丢失 —— 部署永远不会发生。
#   结果：~/Library/Rime/build/ 目录缺失或缺少 squirrel.yaml，
#   librime 运行时回落到 SharedSupport/build/ 里的原版 luna_pinyin，
#   用户自己的方案、词库、Lua、snippets 全部"消失"，
#   同时 build/squirrel.yaml 缺失导致 app_options 白名单整体失效，
#   表现为"所有应用都只能输入英文"。
#
# 本脚本不依赖前端进程是否已在运行：
#   1. rime_deployer --build   负责编译 schema / 词典 / build/default.yaml
#   2. 拉起 Squirrel 并 --reload  负责生成 build/squirrel.yaml
#      (squirrel.yaml 是 macOS 前端专有配置，只有前端的 config_file_update
#       任务会编译它，rime_deployer 不产出)
#   3. 校验产物确实存在，缺一不可
# ==============================================================================

set -e

GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 允许外部覆盖
RIME_DIR="${RIME_DIR:-$HOME/Library/Rime}"
SQUIRREL_APP="${SQUIRREL_APP:-/Library/Input Methods/Squirrel.app}"
QUIET="${QUIET:-false}"

OS="$(uname -s)"

if [ "$OS" = "Darwin" ]; then
  SHARED_DATA_DIR="$SQUIRREL_APP/Contents/SharedSupport"
  DEPLOYER="$SQUIRREL_APP/Contents/MacOS/rime_deployer"
  SQUIRREL_BIN="$SQUIRREL_APP/Contents/MacOS/Squirrel"
else
  SHARED_DATA_DIR="${SHARED_DATA_DIR:-/usr/share/rime-data}"
  DEPLOYER="${DEPLOYER:-$(command -v rime_deployer 2>/dev/null || true)}"
  SQUIRREL_BIN=""
fi

log() { [ "$QUIET" = "true" ] || echo -e "$@"; }

# ---------------------------------------------------------------------------
# 0. 同步仓库里的自定义配置到 Rime 用户目录
#    仓库 (Rime_Config) 是配置的权威来源，用户目录 ~/Library/Rime 是运行目录。
#    少了这一步，改了仓库里的 squirrel.custom.yaml 也不会生效 ——
#    部署用的仍是用户目录里的旧副本。
# ---------------------------------------------------------------------------
sync_configs() {
  [ -d "$SCRIPT_DIR" ] || return 0

  local copied=0
  for f in squirrel.custom.yaml default.custom.yaml rime_frost.custom.yaml \
           snippets.custom.yaml snippets.yaml symbols_v.yaml \
           rime_frost_aux.dict.yaml rime_frost_aux.schema.yaml; do
    if [ -f "$SCRIPT_DIR/$f" ]; then
      mkdir -p "$RIME_DIR"
      cp -f "$SCRIPT_DIR/$f" "$RIME_DIR/" 2>/dev/null && copied=$((copied + 1))
    fi
  done

  # Lua 扩展
  if [ -d "$SCRIPT_DIR/lua" ]; then
    mkdir -p "$RIME_DIR/lua"
    cp -rf "$SCRIPT_DIR/lua/"* "$RIME_DIR/lua/" 2>/dev/null || true
    copied=$((copied + 1))
  fi

  if [ "$copied" -gt 0 ]; then
    log "${GREEN}✅ 已同步 $copied 组仓库配置到 $RIME_DIR${NC}"
  fi
}

# ---------------------------------------------------------------------------
# 1. 编译 schema / 词典 / build/default.yaml
# ---------------------------------------------------------------------------
deploy_schemas() {
  if [ ! -x "$DEPLOYER" ]; then
    log "${YELLOW}⚠️ 未找到 rime_deployer，跳过编译${NC}"
    return 1
  fi

  log "${BLUE}🔧 正在编译 Rime 方案与词库 -> $RIME_DIR/build ...${NC}"
  mkdir -p "$RIME_DIR/build"

  # rime_deployer --build <user_data_dir> <shared_data_dir> <staging_dir>
  if "$DEPLOYER" --build "$RIME_DIR" "$SHARED_DATA_DIR" "$RIME_DIR/build" >/dev/null 2>&1; then
    log "${GREEN}✅ 方案与词库编译完成${NC}"
  else
    log "${RED}❌ rime_deployer 编译失败，请检查 $RIME_DIR/build${NC}"
    return 1
  fi
}

# ---------------------------------------------------------------------------
# 2. 生成 build/squirrel.yaml (macOS)
#    librime 的 squirrel 配置由 build/squirrel.yaml 提供。
#    它缺失时 config_open("squirrel") 返回**空配置**，
#    导致 app_options (分应用中英文白名单) 整体失效。
#    squirrel.yaml 只由前端的 config_file_update 任务编译，
#    因此这里必须通过前端的完整 deploy 流程来产出。
# ---------------------------------------------------------------------------
deploy_squirrel_yaml() {
  if [ "$OS" != "Darwin" ]; then return 0; fi

  local target="$RIME_DIR/build/squirrel.yaml"

  if [ ! -x "$SQUIRREL_BIN" ]; then
    log "${YELLOW}⚠️ 未找到 Squirrel，无法生成 build/squirrel.yaml${NC}"
    return 1
  fi

  # 前端不在运行时，--reload 的分布式通知会被丢弃 -> 先确保它在运行
  if ! pgrep -f "Squirrel.app/Contents/MacOS/Squirrel" >/dev/null 2>&1; then
    log "${BLUE}🚀 Squirrel 未在运行，正在拉起 ...${NC}"
    open -a "$SQUIRREL_APP" >/dev/null 2>&1 || true
    # 等待进程起来
    local waited=0
    while ! pgrep -f "Squirrel.app/Contents/MacOS/Squirrel" >/dev/null 2>&1; do
      sleep 1
      waited=$((waited + 1))
      if [ "$waited" -ge 15 ]; then
        log "${RED}❌ Squirrel 启动超时${NC}"
        return 1
      fi
    done
    sleep 2
  fi

  # --reload 触发前端的完整 deploy (startRime(fullCheck: true))，
  # 其中包含 deploy_config_file("squirrel.yaml", "config_version")。
  "$SQUIRREL_BIN" --reload >/dev/null 2>&1 || true

  # 等待产物落盘
  local waited=0
  while [ ! -f "$target" ]; do
    sleep 1
    waited=$((waited + 1))
    if [ "$waited" -ge 30 ]; then break; fi
  done

  if [ -f "$target" ]; then
    log "${GREEN}✅ build/squirrel.yaml 已生成${NC}"
  else
    log "${RED}❌ build/squirrel.yaml 生成失败，分应用中英文切换将失效${NC}"
    return 1
  fi
}

# ---------------------------------------------------------------------------
# 3. 确保输入源在"已启用"列表里 (macOS)
#    TIS 层的 enabled 与 用户启用列表 (com.apple.HIToolbox AppleEnabledInputSources，
#    即输入法菜单的数据源) 是两回事。
#    Squirrel 自带的 --enable-input-source 会误判（TIS 层 IsEnabled=true 就跳过），
#    导致输入法菜单里根本选不到"鼠须管"。
#    典型诱因：macOS 更新会重置第三方输入源的注册与启用状态。
# ---------------------------------------------------------------------------
ensure_enabled_list() {
  if [ "$OS" != "Darwin" ]; then return 0; fi

  if ! defaults read com.apple.HIToolbox AppleEnabledInputSources 2>/dev/null | \
       grep -q "im.rime.inputmethod.Squirrel"; then
    log "${YELLOW}⚠️ 输入源未在用户启用列表中，正在添加（否则输入法菜单选不到）...${NC}"
    defaults write com.apple.HIToolbox AppleEnabledInputSources -array-add \
      '{InputSourceKind = "Input Mode"; "Bundle ID" = "im.rime.inputmethod.Squirrel"; "Input Mode" = "im.rime.inputmethod.Squirrel.Hans";}'
    # 输入法菜单进程重启后重建菜单
    killall TextInputMenuAgent 2>/dev/null || true
    sleep 1
  fi

  if defaults read com.apple.HIToolbox AppleEnabledInputSources 2>/dev/null | \
       grep -q "im.rime.inputmethod.Squirrel"; then
    log "${GREEN}✅ 输入源已在启用列表中${NC}"
  else
    log "${RED}❌ 输入源启用失败，请到 系统设置 → 键盘 → 输入法 手动添加鼠须管${NC}"
    return 1
  fi
}

# ---------------------------------------------------------------------------
# 4. 校验关键产物
# ---------------------------------------------------------------------------
verify() {
  local ok=0
  if [ -f "$RIME_DIR/build/default.yaml" ]; then
    log "${GREEN}✅ build/default.yaml${NC}"
  else
    log "${RED}❌ 缺少 build/default.yaml${NC}"
    ok=1
  fi
  if [ "$OS" = "Darwin" ] && [ ! -f "$RIME_DIR/build/squirrel.yaml" ]; then
    log "${RED}❌ 缺少 build/squirrel.yaml${NC}"
    ok=1
  fi
  # 方案必须真的编译出来了
  if ls "$RIME_DIR"/build/*.schema.yaml >/dev/null 2>&1; then
    log "${GREEN}✅ 方案已编译${NC}"
  else
    log "${RED}❌ 没有编译出任何 schema${NC}"
    ok=1
  fi
  # 依赖词典必须真的编译出来了。
  # rime_frost.schema.yaml 的 dependencies 声明了 rime_frost_aux，
  # 它缺失时部署日志会报 "missing input schema; skipped unsatisfied dependency"，
  # 表现为 `` 反查功能失效 —— 但部署本身仍返回 0，所以必须单独校验。
  if [ -f "$RIME_DIR/rime_frost.schema.yaml" ] \
     && grep -q "rime_frost_aux" "$RIME_DIR/rime_frost.schema.yaml" 2>/dev/null; then
    if [ -f "$RIME_DIR/build/rime_frost_aux.table.bin" ]; then
      log "${GREEN}✅ 依赖词典 rime_frost_aux 已编译${NC}"
    else
      log "${RED}❌ 缺少 build/rime_frost_aux.table.bin（依赖词典未编译，\`\` 反查会失效）${NC}"
      ok=1
    fi
  fi
  return $ok
}

main() {
  sync_configs
  deploy_schemas || true
  deploy_squirrel_yaml || true
  ensure_enabled_list || true
  if verify; then
    log "${GREEN}🎉 Rime 部署完成且校验通过${NC}"
  else
    log "${YELLOW}⚠️ 部署完成但校验有缺失，请查看上方提示${NC}"
    return 1
  fi
}

# 允许被 source 调用时只提供函数
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
  main
fi
