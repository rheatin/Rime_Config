# ❄️ Rime_Config (个人跨平台 Rime 鼠须管 / 小狼毫 / Fcitx5 自动化配置)

基于 [雾凇拼音 (rime-ice)](https://github.com/iDvel/rime-ice) 深度定制的个人跨平台输入法配置库。

---

## ✨ 核心特性

- 🌐 **全平台智能自适应**：
  - **macOS**：自动安装并配置 **Squirrel (鼠须管)**
  - **Linux** (Ubuntu / Debian / Arch / Fedora 等)：自动识别包管理器安装 **Fcitx5-rime**
  - **Windows**：PowerShell 脚本自动安装并配置 **Weasel (小狼毫)**
- 🎨 **Rheatin Solarized 配色**：个性化定制的 Solarized 深色主题与微距排版（`candidate_format`）。
- 🔤 **思源宋体 Heavy 原生支持**：自动将思源宋体（简/繁）安装至系统字体库，无需手动操作。
- ⚡ **配置/词库完全解耦**：采用纯净的 `*.custom.yaml` 补丁机制，可随时平滑跟随官方升级词库。

---

## 🚀 各平台一键安装方法

### 1. macOS / Linux
在终端中执行单行命令（支持自动检测系统并完成全流程安装）：

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
├── install.sh              # macOS & Linux 全自动安装部署脚本
├── install.ps1             # Windows (小狼毫) 全自动安装脚本
├── default.custom.yaml     # 候选词数量及中英切换快捷键
├── squirrel.custom.yaml    # 鼠须管外观、应用行为与 Rheatin Solarized 配色 (macOS)
├── weasel.custom.yaml      # 小狼毫外观与 Rheatin Solarized 配色 (Windows)
├── rime_ice.custom.yaml    # 雾凇拼音行为定制
├── fonts/                  # 思源宋体 (Heavy) 字体源文件
└── README.md
```

---

## 💡 个人自造词与词频同步（进阶）

Rime 支持将你的输入习惯和自造词同步到云盘（如 iCloud / OneDrive / 私有 Git）：

1. 在你的 Rime 配置目录下新建 `installation.yaml`（此文件包含本机标识，建议不上传到公共仓库）：
   ```yaml
   sync_dir: "/Users/your_name/Library/Mobile Documents/com~apple~CloudDocs/RimeSync"
   ```
2. 每次需要同步词频时：
   - **macOS**：在输入法菜单点击「同步用户数据」或执行命令：
     ```bash
     /Library/Input\ Methods/Squirrel.app/Contents/MacOS/Squirrel --sync
     ```
   - **Windows**：点击小狼毫托盘图标 ->「用户词典同步」。
