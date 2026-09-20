# ❄️ Rime_Config

<p align="center">
  <b>白霜拼音 (rime-frost) + 万象语言模型 (Wanxiang LTS) + MoeType 萌娘百科 + Rheatin Solarized 昼夜双主题</b><br>
  <i>全自动跨平台 Rime 方案 · AES-256 私密端到端云同步 · 拆字反查 · 盘古之白 · Snippets 片段引擎</i>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/Platform-macOS%20%7C%20Windows%20%7C%20Linux-brightgreen?style=flat-square" alt="Platform">
  <img src="https://img.shields.io/badge/Engine-Rime%20Frost-blue?style=flat-square" alt="Rime Frost">
  <img src="https://img.shields.io/badge/Model-Wanxiang%20LTS%20400MB-purple?style=flat-square" alt="Wanxiang LTS">
  <img src="https://img.shields.io/badge/Security-AES--256--CBC%20PBKDF2-red?style=flat-square" alt="AES-256 Encryption">
  <img src="https://img.shields.io/badge/Theme-Rheatin%20Solarized-orange?style=flat-square" alt="Solarized">
</p>

---

## ⚠️ 强烈建议：使用前请先 Fork 本仓库 / Please Fork First!

> **中文**：本配置库内置了 **AES-256 双向私密云同步** 与 **GitHub Actions 自动化追更**。同步脚本会自动将您的个人词频与敏感自定义短语（手机、邮箱、住址等）加密并执行 `git push origin main`。
> 若您直接克隆原仓库，因没有写权限会导致同步报错中断。**请务必点击右上角 `Fork` 到您自己的 GitHub 账号下**，并将安装命令中的用户名替换为您自己的账号！
>
> **English**: This repository features **AES-256 end-to-end encrypted cloud sync** and **automated CI updates**. The sync script automatically encrypts your personal typing habits and custom phrases and pushes to `origin main`.
> To have push permissions and protect your privacy, **please Fork this repository to your own GitHub account** before installation, and replace the username in the install command with your own!

---

## ✨ 核心特性 / Key Features

- 🧠 **万象语言模型 (Wanxiang LTS 400MB)**：
  - 内置 400MB N-gram 语法语言模型，整句拼音输入长句命中率大幅跃升！
  - Built-in 400MB N-gram grammar model drastically improving long-sentence accuracy.
- ❄️ **白霜拼音 (rime-frost) + MoeType 萌娘百科**：
  - 整合计算机、历史、地理、成语等 20+ 专业细胞词库，挂载 16.5 万萌娘百科二次元纯增量词库。
  - Integrated 20+ professional cellular vocabularies and 165k MoeType ACGN dictionaries.
- 🧩 **`u` 模式部件拆字反查 (Radical Dismantle Lookup)**：
  - 遇到生僻字直接拆解部件输入！如输入 `uhuohuohuo` 秒出 `焱`，`uriri` 出 `晶`，`uriumu` 出 `森`，`uniunian` 出 `犇`。
  - Reverse lookup unfamiliar Chinese characters by typing sub-components prefixed with `u`.
- 🔣 **正统 `v` 模式 + Symbols Nerd Font 符号回退**：
  - 支持 `vfh`(符号)、`vjt`(箭头)、`vdw`(单位)、`vsz`(数字) 以及 `vhelp` 符号总表；内置 Nerd Font Mono 字体回退链，彻底杜绝特殊符号与开发者图标乱码。
  - Authentic `v` mode with Symbols Nerd Font fallback, eliminating Unicode font rendering issues.
- 📋 **全新 Snippets YAML 片段引擎**：
  - 敲 `/` 触发代码与文本模板（`/sh`、`/git`、`/curl`、`/mail` 等）；采用优雅的 `snippets.yaml`，原生支持 `|` 多行块文本，告别脆弱的 Tab 制表符与繁琐的 `\n`。
  - Code & text expansion engine with clean `snippets.yaml` supporting true multi-line blocks.
- 🔒 **AES-256-CBC 端到端加密云同步**：
  - 个人词频（`sync/`）与真实短语（`custom_phrase.txt`）通过 OpenSSL AES-256 (PBKDF2) 加密为密文包 `vault.enc`，公开仓库绝无明文泄漏风险。
  - Mac / Windows 本地凭密钥静默解密，兼顾开源分享与极致个人隐私。
- 🎨 **Rheatin Solarized 昼夜双主题自适应**：
  - 浅色模式自适应暖象牙白（Solarized Light），深色模式自适应毛玻璃深青墨底（Solarized Dark）。
  - Adaptive day & night Solarized themes matching macOS and Windows system appearance.
- 📐 **盘古之白优雅排版 (Pangu Spacing)**：
  - 中英文/数字混输时（如 `使用 iPhone 16 打字`）自动优雅插入微间距空格，排版赏心悦目。
- 🪟 **分应用中英文智能隔离**：
  - 聊天软件与浏览器聚焦时自动切为中文；终端与代码编辑器强制锁定英文，终端自动关闭 inline 光标嵌入。
  - Intelligent per-application ASCII switching: terminals/IDEs in English, chat/browsers in Chinese.

---

## 🚀 一键快速安装 / One-Line Installation

> 💡 提示：请将命令中的 `<YOUR_GITHUB_USERNAME>` 替换为您 Fork 后的 GitHub 用户名。

### 1. macOS (鼠须管 Squirrel) & Linux (Fcitx5-rime)
在终端中执行：

```bash
curl -fsSL https://raw.githubusercontent.com/<YOUR_GITHUB_USERNAME>/Rime_Config/main/install.sh | bash
```

### 2. Windows (小狼毫 Weasel)
在 PowerShell（管理员权限）中运行：

```powershell
irm https://raw.githubusercontent.com/<YOUR_GITHUB_USERNAME>/Rime_Config/main/install.ps1 | iex
```

---

## ⌨️ 效率打字模式速查 / Typing Cheat Sheet

| 引导前缀 | 功能说明 | 输入示例 | 输出结果 |
| :--- | :--- | :--- | :--- |
| `u` | **部件拆字反查** | `uhuohuohuo`<br>`uriri`<br>`uriumu` | 焱<br>晶<br>森 |
| `v` | **特殊符号系统** | `vfh`<br>`vjt`<br>`vdw`<br>`vhelp` | ❖, ✿, ★<br>➔, ➜, ⇄<br>℃, ㎡, ㎏<br>打开符号总表 |
| `/` | **Snippets 片段展开** | `/sh`<br>`/git`<br>`/curl`<br>`/mail` | 展开严谨 Bash 头部模板<br>Commit 前缀选项<br>cURL POST 请求模板<br>邮箱签名 |
| `date` / `rq` | **日期快速输入** | `date` | `2026-09-20`, `2026年9月20日` |
| `time` / `sj` | **当前时间** | `time` | `19:20:30`, `晚上 07:20` |
| `ts` / `now` | **Unix 时间戳** | `ts` | `1789903230` (10位/13位) |
| `uuid` | **随机 UUID v4** | `uuid` | `4f3c7e8a-2b1d-4f6e-9a0b-...` |
| `R` | **金额与数字大写** | `R1234.56` | 壹仟贰佰叁拾肆元伍角陆分 |

---

## 🔄 双向词频同步与日常维护 / Sync & Maintenance

### 1. 词频与短语一键同步
- **macOS**：在终端运行 `./sync.sh`，或点击状态栏鼠须管菜单的「同步用户数据」；
- **Windows**：在 PowerShell 运行 `.\sync.ps1`，或右键小狼毫托盘图标选择「用户资料同步」。
- 同步脚本会自动完成：Git Pull ➔ AES-256 解密 ➔ 合并词频 ➔ 加密打包 ➔ Git Push ➔ 重新部署。

### 2. 新增软件分应用中英文适配
由于全局兜底（fallback）默认即为英文，未列出的应用无需配置；仅当您需要将某个应用设为**默认中文**或**终端防冲突模式**时运行：
- **macOS**：运行 `./tools/New-AppOptions.sh -r`（仅扫描运行中），或使用 `-a` 一键安全合并进 `squirrel.custom.yaml` 并自动重载；
- **Windows**：运行 `pwsh -File tools\New-AppOptions.ps1 -RunningOnly`。

### 3. 自定义代码片段 (Snippets)
编辑根目录下的 `snippets.yaml`，保存后执行 `./sync.sh` 即可同步生效：

```yaml
/demo:
  - text: |
      function helloWorld() {
        console.log("Hello Rime!");
      }
    desc: JavaScript 示例模板
```

---

## 📂 仓库结构 / Repository Structure

```text
.
├── install.sh                   # macOS & Linux 全自动装机部署脚本
├── install.ps1                  # Windows (小狼毫) 全自动装机脚本
├── clean.sh                    # 🧹 macOS/Linux 方案瘦身维护脚本 (初次安装时调用)
├── clean.ps1                   # 🧹 Windows 小狼毫方案瘦身维护脚本
├── sync.sh                      # 🔄 macOS/Linux 一键极速词频加密同步
├── sync.ps1                     # 🔄 Windows 一键极速词频加密同步
├── sync_watcher.ps1             # ⚡ Windows 后台变动监听守护服务
├── custom_phrase.example.txt    # 📋 系统短语公开模板 (个人明文由 AES-256 vault.enc 加密)
├── snippets.yaml                # 📋 Snippets 片段配置文件 (支持多行块文本)
├── vault.enc                    # 🔒 AES-256 密文同步包 (包含私密短语与用户打字词频)
├── default.custom.yaml          # 默认方案 (rime_frost) 与中英切换设定
├── squirrel.custom.yaml         # 鼠须管外观、分应用中英与 Rheatin Solarized 配色 (macOS)
├── weasel.custom.yaml           # 小狼毫外观、分应用中英与 Rheatin Solarized 配色 (Windows)
├── rime_frost.custom.yaml       # 白霜拼音行为定制、符号映射与万象语言模型挂载
├── rime_frost.extended.dict.yaml# 聚合词库入口 (白霜核心 + 萌娘百科)
├── symbols_v.yaml               # 正统 v 模式符号映射表
├── fonts/                       # 思源宋体 Heavy & Symbols Nerd Font 字体库
├── tools/
│   ├── New-AppOptions.ps1       # 🪟 Windows: 扫描程序并生成 weasel app_options 片段
│   └── New-AppOptions.sh        # 🍎 macOS: 扫描程序并生成/智能合并 squirrel app_options 片段
├── docs/
│   └── 分应用中英文切换.md       # 🪟 Weasel 与 Squirrel 分应用中英切换原理解析与自检
├── sync/                        # 🧠 个人自造词与跨平台词频快照归档 (加密保护)
└── README.md
```

---

## 📄 开源许可证 / License

基于 [MIT License](LICENSE) 开源发布。词库与模型版权归各自原项目所有（白霜拼音、万象语言模型、MoeType）。
