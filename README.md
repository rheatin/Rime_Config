# ❄️ Rime_Config (个人跨平台 Rime 鼠须管 / 小狼毫 / Fcitx5 自动化配置)

基于 [雾凇拼音 (rime-ice)](https://github.com/iDvel/rime-ice) 深度定制的个人跨平台输入法配置库，支持自动联网挂载 [MoeType (萌娘百科)](https://github.com/suiginko/moetype) 扩展词库。

---

## ✨ 核心特性

- 🚀 **极致轻量 Repo**：不存放第三方大词库，部署时全自动从官方源下载 MoeType 最新 Release 并**动态去重**生成纯增量词库！
- 🌐 **全平台智能自适应**：
  - **macOS**：自动安装并配置 **Squirrel (鼠须管)**
  - **Windows**：自动安装并配置 **Weasel (小狼毫)**
  - **Linux** (Ubuntu / Debian / Arch / Fedora 等)：自动安装 **Fcitx5-rime**
- 📚 **海量词库矩阵**：
  - **雾凇拼音 (190万词)**：现代汉语、成语、日常互联网高频词；
  - **MoeType 萌娘百科 (16.5万纯增量词)**：二次元角色、动漫番剧、游戏装备与网络热梗。
- 🔄 **双向跨平台自造词与词频实时云同步**：
  - **macOS**：点击状态栏「Sync user data」➔ 自动静默 Push 到 GitHub 并弹窗通知；
  - **Windows**：点击托盘「用户资料同步」➔ 自动静默 Push 到 GitHub 并弹气泡通知；
  - **双向互通合并**：Mac 与 Windows 之间的打字习惯和自造词永远保持双向合并与实时互通。
- 🎨 **Rheatin Solarized 配色**：专属深色毛玻璃/悬浮小胶囊排版。
- 🔤 **思源宋体 Heavy 原生支持**：智能检测系统字体库，按需自动安装。
- ⚡ **配置/词库完全解耦**：采用纯净的 `*.custom.yaml` 补丁机制，可随时平滑跟随官方升级词库。

---

## 🚀 各平台一键安装方法 (新电脑)

### 1. macOS / Linux
在终端中执行单行命令：

```bash
curl -fsSL https://raw.githubusercontent.com/rheatin/Rime_Config/main/install.sh | bash
```

### 2. Windows
在 PowerShell（管理员权限）中运行：

```powershell
irm https://raw.githubusercontent.com/rheatin/Rime_Config/main/install.ps1 | iex
```

---

## 📂 仓库结构

```text
.
├── install.sh                  # macOS & Linux 全自动安装部署脚本 (含 MoeType 动态下载去重)
├── install.ps1                 # Windows (小狼毫) 全自动安装脚本 (含 MoeType 动态下载去重)
├── sync.sh                     # 🔄 macOS/Linux 一键词频同步
├── sync.ps1                    # 🔄 Windows 一键词频同步
├── sync_watcher.ps1            # ⚡ Windows 后台变动监听守护服务
├── default.custom.yaml         # 候选词数量及中英切换快捷键
├── squirrel.custom.yaml        # 鼠须管外观、应用行为与 Rheatin Solarized 配色 (macOS)
├── weasel.custom.yaml          # 小狼毫外观与 Rheatin Solarized 配色 (Windows)
├── rime_ice.custom.yaml        # 雾凇拼音行为定制与扩展词库指向
├── rime_ice.extended.dict.yaml # 聚合词库入口 (雾凇拼音 + 萌娘百科)
├── fonts/                      # 思源宋体 (Heavy) 字体源文件
├── sync/                       # 🧠 个人自造词与跨平台词频快照归档
└── README.md
```
