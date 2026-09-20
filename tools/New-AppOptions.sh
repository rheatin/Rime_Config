#!/usr/bin/env bash
# ==============================================================================
# New-AppOptions.sh
# 扫描「正在运行」与「已安装」的 macOS 程序，生成可粘贴/直接合并进
# squirrel.custom.yaml 的 app_options 英文/中文条目与终端 no_inline 配置。
#
# 背景：鼠须管 (Squirrel) 的 app_options 依据应用程序的 CFBundleIdentifier 匹配。
# 本脚本自动提取正在运行的 GUI 进程与 /Applications 下已安装 App 的 Bundle ID，
# 自动排除已收录项、系统守护进程与内部 Helper，对终端类工具自动补充 no_inline: true，
# 并支持一键智能合并写回 squirrel.custom.yaml。
#
# 用法：
#   ./tools/New-AppOptions.sh                 # 打印未收录的候选条目
#   ./tools/New-AppOptions.sh -r              # 仅扫描当前正在运行的前台/UI程序
#   ./tools/New-AppOptions.sh -w              # 生成完整片段到 tools/app_options.mac.generated.yaml
#   ./tools/New-AppOptions.sh -a              # 智能追加到 squirrel.custom.yaml 并提示重新部署
#   ./tools/New-AppOptions.sh -c              # 包含聊天与浏览器等建议中文软件
#   ./tools/New-AppOptions.sh -f "term"       # 仅筛选名称或 Bundle ID 包含 term 的应用
# ==============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# 确保在 macOS 环境执行
if [ "$(uname -s)" != "Darwin" ]; then
  echo "❌ 错误：本脚本仅支持 macOS 环境 (Squirrel / 鼠须管)。Windows 请使用 tools/New-AppOptions.ps1" >&2
  exit 1
fi

# 寻找可用的 Python 3
PYTHON_BIN=""
if command -v python3 >/dev/null 2>&1; then
  PYTHON_BIN="$(command -v python3)"
elif [ -x "/usr/bin/python3" ]; then
  PYTHON_BIN="/usr/bin/python3"
else
  echo "❌ 错误：未检测到 python3，请先安装 Python 3 或 Xcode Command Line Tools" >&2
  exit 1
fi

export REPO_ROOT
exec "$PYTHON_BIN" - "$@" << 'EOF'
import os
import sys
import re
import argparse
import subprocess
import plistlib
import shutil

# 终端 ANSI 彩色输出
CYAN = "\033[0;36m"
GREEN = "\033[0;32m"
YELLOW = "\033[1;33m"
GRAY = "\033[0;90m"
MAGENTA = "\033[0;35m"
RED = "\033[0;31m"
BOLD = "\033[1m"
RESET = "\033[0m"

# ── 1. 聊天与浏览器白名单（默认建议中文 ascii_mode: false，除非用户指定 Slack 等） ──────────────
CHINESE_ALLOWLIST = {
    # 聊天与通讯
    "com.tencent.xinWeChat": "微信",
    "com.tencent.xinWeChat.xplayer": "微信内置播放器",
    "com.tencent.qq": "QQ",
    "org.telegram.desktop": "Telegram",
    "ru.keepcoder.Telegram": "Telegram",
    "com.electron.lark": "飞书",
    "com.alibaba.DingTalkMac": "钉钉",
    "com.apple.MobileSMS": "信息",
    "net.whatsapp.WhatsApp": "WhatsApp",
    "jp.naver.line.mac": "LINE",
    "com.hnc.Discord": "Discord",
    "com.microsoft.teams": "Microsoft Teams",
    "com.microsoft.teams2": "Microsoft Teams",
    # 网页浏览器
    "com.google.Chrome": "Google Chrome",
    "com.apple.Safari": "Safari",
    "com.microsoft.edgemac": "Microsoft Edge",
    "company.thebrowser.Browser": "Arc",
    "org.mozilla.firefox": "Firefox",
    "com.brave.Browser": "Brave",
    "com.operasoftware.Opera": "Opera",
    "com.vivaldi.Vivaldi": "Vivaldi",
}

# ── 2. 终端与命令行工具（需要额外补充 no_inline: true 避免嵌入光标冲突） ──────────────
TERMINAL_BUNDLE_IDS = {
    "com.apple.Terminal",
    "com.googlecode.iterm2",
    "co.zeit.hyper",
    "com.stablyai.orca",
    "sh.termio.app",
    "io.alacritty",
    "net.kovidgoyal.kitty",
    "dev.warp.Warp-GDK",
    "com.mitchellh.ghostty",
    "com.github.wez.wezterm",
    "org.vim.MacVim",
    "com.tabby",
    "com.sublimetext.4",
    "com.sublimetext.3",
    "com.panic.Prompt",
}

# ── 3. 系统组件/内部守护进程/输入法自身（严禁或无需加入配置） ──────────────────────────────
SYSTEM_DENYLIST = {
    "im.rime.inputmethod.Squirrel",
    "com.apple.systemevents",
    "com.apple.systemuiserver",
    "com.apple.dock",
    "com.apple.dock.extra",
    "com.apple.loginwindow",
    "com.apple.controlcenter",
    "com.apple.controlcenter.helper",
    "com.apple.notificationcenterui",
    "com.apple.MenuBarAgent",
    "com.apple.TextInputMenuAgent",
    "com.apple.UserNotificationCenter",
    "com.apple.AccessibilityUIServer",
    "com.apple.PowerChime",
    "com.apple.AirPlayUIAgent",
    "com.apple.coreservices.uiagent",
    "com.apple.WindowManager",
    "com.apple.talagent",
    "com.apple.wifi.WiFiAgent",
    "com.apple.FolderActionsDispatcher",
    "com.apple.ViewBridgeAuxiliary",
    "com.apple.UIKitSystemApp",
    "com.apple.universalcontrol",
    "com.apple.LocalAuthentication.UIAgent",
    "com.apple.LocalAuthenticationRemoteService",
    "com.apple.security.Keychain-Circle-Notification",
    "com.apple.accessibility.AXVisualSupportAgent",
    "com.apple.accessibility.universalAccessAuthWarn",
    "com.apple.campo",
    "com.apple.CoreLocationAgent",
    "com.apple.AppSSOAgent",
}

def parse_args():
    parser = argparse.ArgumentParser(
        prog="New-AppOptions.sh",
        description="扫描 macOS 应用程序并生成/追加 squirrel.custom.yaml 的 app_options 配置。"
    )
    parser.add_argument("-r", "--running-only", action="store_true", help="仅扫描当前正在运行的前台/UI程序")
    parser.add_argument("-w", "--write-template", action="store_true", help="生成完整 YAML 片段到 tools/app_options.mac.generated.yaml")
    parser.add_argument("-a", "--apply", action="store_true", help="直接安全合并追加到 squirrel.custom.yaml 并提示部署")
    parser.add_argument("-c", "--include-chinese", action="store_true", help="包含建议中文的聊天与浏览器软件")
    parser.add_argument("-f", "--filter", type=str, default="", help="按名称或 Bundle ID 关键字过滤")
    return parser.parse_args()

def get_existing_app_options(yaml_path):
    existing = {}
    if not os.path.exists(yaml_path):
        return existing
    try:
        with open(yaml_path, "r", encoding="utf-8") as f:
            in_app_options = False
            for line in f:
                if re.match(r"^\s*app_options:\s*$", line):
                    in_app_options = True
                    continue
                if in_app_options:
                    # 如果到达同级或上一级 key (例如 style:)
                    if re.match(r"^ {0,2}[a-zA-Z0-9_]+:\s*$", line):
                        break
                    m = re.match(r"^ {4}([^ #][^:]*):\s*$", line)
                    if m:
                        bid = m.group(1).strip().strip("\"'")
                        existing[bid.lower()] = bid
    except Exception as e:
        print(f"{YELLOW}⚠️ 读取现存配置失败：{e}{RESET}", file=sys.stderr)
    return existing

def get_running_apps():
    apps = {}
    try:
        out = subprocess.check_output(["lsappinfo", "list"], text=True, errors="replace")
        entries = re.split(r"\n(?=\d+\)\s+\")", out)
        for e in entries:
            m_name = re.search(r"^\d+\)\s+\"([^\"]+)\"", e)
            m_bid = re.search(r"bundleID=\"([^\"]+)\"", e)
            m_path = re.search(r"bundle path=\"([^\"]+)\"", e)
            m_type = re.search(r"type=\"([^\"]+)\"", e)
            if m_bid:
                bid = m_bid.group(1).strip()
                bpath = m_path.group(1).strip() if m_path else ""
                name = m_name.group(1).strip() if m_name else ""
                app_type = m_type.group(1).strip() if m_type else ""

                if not bid or bid == "[ NULL ]":
                    continue
                # 排除内部插件、XPC 以及嵌套在 Contents 内部的私有子进程
                if "/Contents/" in bpath or bpath.endswith(".xpc") or bpath.endswith(".appex"):
                    continue
                if app_type in ("Foreground", "UIElement"):
                    apps[bid] = {
                        "name": name or os.path.splitext(os.path.basename(bpath))[0],
                        "path": bpath,
                        "running": True
                    }
    except Exception as e:
        print(f"{YELLOW}⚠️ 提取运行中应用遇到问题：{e}{RESET}", file=sys.stderr)
    return apps

def get_installed_apps():
    search_dirs = [
        "/Applications",
        "/System/Applications",
        "/System/Applications/Utilities",
        os.path.expanduser("~/Applications")
    ]
    apps = {}
    for d in search_dirs:
        if not os.path.exists(d):
            continue
        for root, subdirs, files in os.walk(d):
            # 遇到顶层 .app 包后不再深入其内部扫描
            if root.endswith(".app"):
                subdirs.clear()
                continue
            for item in subdirs[:]:
                if item.endswith(".app"):
                    app_path = os.path.join(root, item)
                    info_plist = os.path.join(app_path, "Contents", "Info.plist")
                    if os.path.exists(info_plist):
                        try:
                            with open(info_plist, "rb") as fp:
                                pl = plistlib.load(fp)
                                bid = pl.get("CFBundleIdentifier")
                                name = pl.get("CFBundleDisplayName") or pl.get("CFBundleName") or item[:-4]
                                if bid and isinstance(bid, str):
                                    bid = bid.strip()
                                    apps[bid] = {
                                        "name": str(name).strip(),
                                        "path": app_path,
                                        "running": False
                                    }
                        except Exception:
                            pass
                    subdirs.remove(item)
    return apps

def is_terminal_app(bid, name, path):
    if bid in TERMINAL_BUNDLE_IDS:
        return True
    lower_str = (bid + " " + name + " " + path).lower()
    if any(k in lower_str for k in ["terminal", "iterm", "alacritty", "kitty", "ghostty", "wezterm", "termio"]):
        return True
    return False

def is_denied(bid, name, path):
    if bid in SYSTEM_DENYLIST:
        return True
    if bid.startswith("com.apple.WebKit."):
        return True
    if bid.startswith("com.apple.chrono."):
        return True
    if re.search(r"(\.xpc|\.appex|\.helper|Updater|CrashReporter|\.tmp)$", bid, re.IGNORECASE):
        return True
    return False

def main():
    args = parse_args()
    repo_root = os.environ.get("REPO_ROOT") or os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    yaml_path = os.path.join(repo_root, "squirrel.custom.yaml")

    existing_map = get_existing_app_options(yaml_path)
    print(f"{CYAN}ℹ️  已收录条目: {len(existing_map)} 个 (来自 squirrel.custom.yaml){RESET}")

    # 收集应用程序
    running_apps = get_running_apps()
    all_apps = dict(running_apps)

    if not args.running_only:
        print(f"{GRAY}🔍 正在扫描系统已安装应用 (/Applications & /System/Applications)...{RESET}")
        installed = get_installed_apps()
        for bid, info in installed.items():
            if bid not in all_apps:
                all_apps[bid] = info
            else:
                # 保留运行中标记与更友好的名称
                all_apps[bid]["running"] = True
                if not all_apps[bid]["name"] and info["name"]:
                    all_apps[bid]["name"] = info["name"]

    # 过滤候选条目
    candidates = []
    for bid, info in all_apps.items():
        name = info["name"]
        path = info["path"]
        is_running = info["running"]

        # 已在配置文件中收录
        if bid.lower() in existing_map:
            continue

        # 系统黑名单拦截
        if is_denied(bid, name, path):
            continue

        # 关键字过滤
        if args.filter:
            kw = args.filter.lower()
            if kw not in bid.lower() and kw not in name.lower() and kw not in path.lower():
                continue

        # 中文白名单判断
        is_chinese = bid in CHINESE_ALLOWLIST
        if is_chinese and not args.include_chinese:
            continue

        is_term = is_terminal_app(bid, name, path)

        candidates.append({
            "bid": bid,
            "name": name,
            "path": path,
            "running": is_running,
            "is_chinese": is_chinese,
            "is_terminal": is_term
        })

    # 排序：运行中的在前，其余按名称字母排序
    candidates.sort(key=lambda x: (not x["running"], x["name"].lower(), x["bid"].lower()))

    if not candidates:
        print(f"{GREEN}✨ 未发现新的候选应用程序（所有检测到的程序均已收录或在过滤规则中）。{RESET}")
        return

    # 生成 YAML 片段
    header = "    # ─── 显式设定 (由 tools/New-AppOptions.sh 生成) ───"
    lines = [header]

    for c in candidates:
        bid = c["bid"]
        name = c["name"]
        running_tag = " (运行中)" if c["running"] else ""
        lines.append(f"    # {name}{running_tag}")

        key = f'"{bid}"' if re.search(r"[\s:]", bid) else bid

        if c["is_chinese"]:
            lines.append(f"    {key}:")
            lines.append("      ascii_mode: false")
        elif c["is_terminal"]:
            lines.append(f"    {key}:")
            lines.append("      ascii_mode: true")
            lines.append("      no_inline: true")
        else:
            lines.append(f"    {key}:")
            lines.append("      ascii_mode: true")

    yaml_content = "\n".join(lines)

    # 写入模板文件
    if args.write_template:
        out_file = os.path.join(repo_root, "tools", "app_options.mac.generated.yaml")
        with open(out_file, "w", encoding="utf-8") as f:
            f.write(yaml_content + "\n")
        print(f"\n{GREEN}✅ 已成功生成 YAML 片段文件: {out_file} ({len(candidates)} 条){RESET}")
        return

    # 直接合并写回 squirrel.custom.yaml
    if args.apply:
        if not os.path.exists(yaml_path):
            print(f"{RED}❌ 找不到目标文件: {yaml_path}{RESET}", file=sys.stderr)
            sys.exit(1)

        # 备份原文件
        bak_path = yaml_path + ".bak"
        shutil.copyfile(yaml_path, bak_path)
        print(f"{GRAY}📦 已备份原配置到: {bak_path}{RESET}")

        with open(yaml_path, "r", encoding="utf-8") as f:
            content = f.read()

        # 找到 style: 节点位置插入，保证在 app_options 区块内部末尾
        style_match = re.search(r"\n( {2}style:\s*\n)", content)
        if style_match:
            insert_pos = style_match.start()
            new_content = content[:insert_pos] + "\n" + yaml_content + "\n\n" + content[insert_pos+1:]
        else:
            # 回退：直接追加到末尾
            new_content = content.rstrip() + "\n\n" + yaml_content + "\n"

        with open(yaml_path, "w", encoding="utf-8") as f:
            f.write(new_content)

        print(f"{GREEN}🎉 成功合并 {len(candidates)} 个应用配置到: {yaml_path}{RESET}")

        # 如果用户本地存在 ~/Library/Rime，同时同步并提示重新部署
        user_rime = os.path.expanduser("~/Library/Rime")
        if os.path.isdir(user_rime):
            dest = os.path.join(user_rime, "squirrel.custom.yaml")
            shutil.copyfile(yaml_path, dest)
            print(f"{GREEN}🚀 已自动同步更新至: {dest}{RESET}")

            # 触发重新部署
            squirrel_bin = "/Library/Input Methods/Squirrel.app/Contents/MacOS/Squirrel"
            if os.path.exists(squirrel_bin):
                print(f"{CYAN}🔄 正在重新加载 Squirrel (鼠须管)...{RESET}")
                try:
                    subprocess.run([squirrel_bin, "--reload"], check=False)
                    print(f"{GREEN}✅ Squirrel 配置重载成功！{RESET}")
                except Exception as e:
                    print(f"{YELLOW}⚠️ 重载命令触发异常：{e}{RESET}")
        return

    # 默认输出到终端屏幕
    print(f"\n{YELLOW}未收录的候选程序 ({len(candidates)} 个)，可直接粘贴到 squirrel.custom.yaml 的 app_options 下:{RESET}")
    print(f"{GRAY}{header}{RESET}")
    for c in candidates:
        bid = c["bid"]
        name = c["name"]
        running_tag = f" {MAGENTA}[运行中]{RESET}" if c["running"] else ""
        type_tag = f" {CYAN}[终端: no_inline]{RESET}" if c["is_terminal"] else (" [建议中文]" if c["is_chinese"] else "")

        print(f"{GRAY}    # {name}{RESET}{running_tag}{type_tag}")
        key = f'"{bid}"' if re.search(r"[\s:]", bid) else bid
        if c["is_chinese"]:
            print(f"    {key}:")
            print("      ascii_mode: false")
        elif c["is_terminal"]:
            print(f"    {key}:")
            print("      ascii_mode: true")
            print("      no_inline: true")
        else:
            print(f"    {key}:")
            print("      ascii_mode: true")

    print(f"\n{GRAY}提示:{RESET}")
    print(f"  • 使用 {BOLD}./tools/New-AppOptions.sh -r{RESET} 可仅扫描当前运行中的应用。")
    print(f"  • 使用 {BOLD}./tools/New-AppOptions.sh -w{RESET} 可直接输出到 tools/app_options.mac.generated.yaml。")
    print(f"  • 使用 {BOLD}./tools/New-AppOptions.sh -a{RESET} 可一键安全合并追加并自动重新部署 Squirrel。")
    print(f"  • 未列出的 App 默认回落到全局英文，因此仅需按需钉死常用工具即可。")

if __name__ == "__main__":
    main()
EOF
