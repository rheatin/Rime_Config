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
# 3. 校验关键产物
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
  return $ok
}

main() {
  deploy_schemas || true
  deploy_squirrel_yaml || true
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
