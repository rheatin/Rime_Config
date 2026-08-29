# ❄️ Rime_Config (个人跨平台 Rime 鼠须管 / 小狼毫 / Fcitx5 自动化配置)

基于 [雾凇拼音 (rime-ice)](https://github.com/iDvel/rime-ice) 深度定制的个人跨平台输入法配置库。

---

## ✨ 核心特性

- 🌐 **全平台智能自适应**：
  - **macOS**：自动安装并配置 **Squirrel (鼠须管)**
  - **Linux** (Ubuntu / Debian / Arch / Fedora 等)：自动识别包管理器安装 **Fcitx5-rime**
  - **Windows**：PowerShell 脚本自动安装并配置 **Weasel (小狼毫)**
- 🧠 **自造词与个人词频记忆双向备份**：内置 `sync.sh` 脚本，换机时自动无损合并恢复平时打字积累的高频词和自造词组！
- 🎨 **Rheatin Solarized 配色**：个性化定制的 Solarized 深色主题与微距排版（`candidate_format`）。
- 🔤 **思源宋体 Heavy 原生支持**：自动将思源宋体（简/繁）安装至系统字体库，无需手动操作。
- ⚡ **配置/词库完全解耦**：采用纯净的 `*.custom.yaml` 补丁机制，可随时平滑跟随官方升级词库。

---

## 🚀 各平台一键安装方法 (新电脑)

### 1. macOS / Linux
在终端中执行单行命令（自动检测系统并完成全流程安装与词频合并）：

```bash
curl -fsSL https://raw.githubusercontent.com/rheatin/Rime_Config/main/install.sh | bash
```

### 2. Windows
在 PowerShell（管理员权限）中运行：

```powershell
irm https://raw.githubusercontent.com/rheatin/Rime_Config/main/install.ps1 | iex
```

---

## 🔄 日常：一键备份最新自造词与词频

平时打字积累了新的高频词或习惯后，只需在终端运行一次 `sync.sh`：

```bash
~/Rime_Config/sync.sh
```

**`sync.sh` 会自动完成：**
1. 触发本地 Rime 导出最新的词频快照（`rime_ice.userdb.txt`）；
2. 自动归档并 commit；
3. 自动 push 同步到 GitHub 远程仓库！

---

## 📂 仓库结构

```text
.
├── install.sh              # macOS & Linux 全自动安装部署脚本
├── install.ps1             # Windows (小狼毫) 全自动安装脚本
├── sync.sh                 # 🔄 一键备份词频与自造词到 GitHub
├── default.custom.yaml     # 候选词数量及中英切换快捷键
├── squirrel.custom.yaml    # 鼠须管外观、应用行为与 Rheatin Solarized 配色 (macOS)
├── weasel.custom.yaml      # 小狼毫外观与 Rheatin Solarized 配色 (Windows)
├── rime_ice.custom.yaml    # 雾凇拼音行为定制
├── fonts/                  # 思源宋体 (Heavy) 字体源文件
├── sync/                   # 🧠 个人自造词与高频词快照归档
└── README.md
```
