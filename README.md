# ❄️ Rime_Config (个人跨平台 Rime 鼠须管 / 小狼毫 / Fcitx5 自动化配置)

基于 [雾凇拼音 (rime-ice)](https://github.com/iDvel/rime-ice) 深度定制的个人跨平台输入法配置库。

---

## ✨ 核心特性

- 🌐 **全平台智能自适应**：
  - **macOS**：自动安装并配置 **Squirrel (鼠须管)**
  - **Windows**：自动安装并配置 **Weasel (小狼毫)**
  - **Linux** (Ubuntu / Debian / Arch / Fedora 等)：自动安装 **Fcitx5-rime**
- 🔄 **双向跨平台自造词与词频实时云同步**：
  - **macOS**：点击状态栏「Sync user data」➔ 自动静默 Push 到 GitHub 并弹窗通知；
  - **Windows**：点击托盘「用户词典同步」➔ 自动静默 Push 到 GitHub 并弹气泡通知；
  - **无损双向合并**：Mac 打出来的生词会自动同步给 Windows，Windows 打出来的生词也会自动同步给 Mac！
- 🎨 **Rheatin Solarized 配色**：专属深色毛玻璃/悬浮胶囊排版。
- 🔤 **思源宋体 Heavy 原生支持**：自动将思源宋体（简/繁）安装至系统字体库。
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

## 🔄 双端词频无缝合并机制

```text
[Mac 端输入自造词] ──点击 Sync──> GitHub 仓库 (sync/MBA/rime_ice.userdb.txt)
                                        │
                                        ▼ 自动合并
[Win 端输入自造词] ──点击 Sync──> GitHub 仓库 (sync/WIN-xxx/rime_ice.userdb.txt)
```

1. **Mac 上**：点击菜单栏「Sync user data」；
2. **Windows 上**：右键托盘小狼毫图标 -> 点击「用户词典同步」；
3. **两端互通**：每次同步都会自动将对方电脑的新词和词频合并到本地！
