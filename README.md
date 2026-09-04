# ❄️ Rime_Config (白霜拼音 + 万象语言模型 + MoeType 个人跨平台自动化配置)

基于 [白霜拼音 (rime-frost)](https://github.com/gaboolic/rime-frost) 与 [万象语言模型 (RIME-LMDG)](https://github.com/amzxyz/RIME-LMDG) 深度定制的个人跨平台高准确率输入法配置库，挂载 [MoeType (萌娘百科)](https://github.com/suiginko/moetype) 扩展词库与 [Symbols Nerd Font](https://www.nerdfonts.com/) 全量符号回退链。

---

## ✨ 核心特性

- 🧠 **万象语言模型 (Wanxiang LTS)**：内置 400MB N-gram 语法语言模型，整句输入首选字词准确率大幅跃升！
- ❄️ **白霜拼音 (rime-frost)**：20+ 专业细胞词库（计算机、历史、地理、成语、医疗等）。
- 🌸 **MoeType 萌娘百科动态去重**：部署时全自动拉取最新 Release 并动态剔除重合词，保留 16.5 万纯增量二次元词库。
- 🔣 **正统 v 模式 + Symbols Nerd Font 符号回退**：
  - 支持 `vfh`(符号)、`vjt`(箭头)、`vdw`(单位)、`vsz`(数字) 以及 `vhelp` 符号总表；
  - 内置 **Symbols Nerd Font Mono** 字体回退链，彻底杜绝特殊符号、开发者图标与 Unicode 字符乱码！
- 🌐 **全平台智能自适应**：
  - **macOS**：自动安装并配置 **Squirrel (鼠须管)**
  - **Windows**：自动安装并配置 **Weasel (小狼毫)**
  - **Linux** (Ubuntu / Debian / Arch / Fedora 等)：自动安装 **Fcitx5-rime**
- 🔄 **双向跨平台自造词与词频实时云同步**：
  - **macOS**：点击状态栏「Sync user data」➔ 自动拉取苹果系统「文本替换」数据库并备份词频 ➔ 静默 Push 到 GitHub 并弹窗通知；
  - **Windows**：点击托盘「用户资料同步」➔ 自动从 GitHub 拉取 Mac 同步的系统短语与词频并重新部署 ➔ 弹气泡通知；
  - **双向互通合并**：Mac 与 Windows 之间的打字习惯和自造词永远保持双向合并与实时互通。
- ⚡ **系统文本替换（自定义短语）跨平台与绝对置顶**：
  - Mac 同步时全自动读取系统 `TextReplacements.db` 导出为 `custom_phrase.txt` 并推送到仓库；
  - Windows 执行同步时自动接收更新并热重载；
  - 锁定 `custom_phrase/initial_quality: 999`，保证快捷短语（邮箱、电话、常用地址等）永远在候选词**第 1 位首选**输出！
- 🎨 **Rheatin Solarized 配色**：专属深色毛玻璃/悬浮小胶囊排版。
- 🔤 **思源宋体 Heavy 原生支持**：智能检测系统字体库，按需自动安装。

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
├── install.sh                   # macOS & Linux 全自动安装部署脚本
├── install.ps1                  # Windows (小狼毫) 全自动安装脚本
├── sync.sh                      # 🔄 macOS/Linux 一键词频同步
├── sync.ps1                     # 🔄 Windows 一键词频同步
├── sync_watcher.ps1             # ⚡ Windows 后台变动监听守护服务
├── custom_phrase.txt            # ⚡ 苹果系统「文本替换」短语自动同步表 (最高优先级置顶)
├── default.custom.yaml          # 默认方案 (rime_frost) 与中英切换快捷键
├── squirrel.custom.yaml         # 鼠须管外观与 Rheatin Solarized 配色 (macOS)
├── weasel.custom.yaml           # 小狼毫外观与 Rheatin Solarized 配色 (Windows)
├── rime_frost.custom.yaml       # 白霜拼音行为定制与万象语言模型挂载
├── rime_frost.extended.dict.yaml# 聚合词库入口 (白霜拼音全量 + 萌娘百科)
├── symbols_v.yaml               # 正统 v 模式符号映射表
├── fonts/                       # 思源宋体 Heavy & Symbols Nerd Font 字体库
├── sync/                        # 🧠 个人自造词与跨平台词频快照归档
└── README.md
```
