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
- 🔒 **AES-256 自动化端到端加密同步 (开源隐私护卫)**：
  - 用户的真实手机号、邮箱、收件地址（`custom_phrase.txt`）以及打字词频（`sync/`）由 `.gitignore` 严格拦截，**绝不以明文形式上传公开 GitHub**；
  - 同步脚本在 Push 前通过 AES-256-CBC (PBKDF2) 自动加密为密文包 `vault.enc`，公开仓库只有密文与安全示例 `custom_phrase.example.txt`；
  - 只有你自己的 Mac / Windows 凭本地密钥（`.vault_key`）静默自动解密生效，兼顾开源分享与极致个人隐私！
- 📋 **Snippets 常用代码与文本片段引擎**：
  - 随手敲 `/` 即可触发片段快捷展开（如 `/sh` 展开严谨 Bash 头部、`/git` 展开标准 Commit 前缀、`/curl`、`/mail` 等）；
  - 支持多行换行 `\n` 与实时候选词描述，可在 `snippets.txt` 中自由增删扩充！
- ⚡ **系统文本替换（自定义短语）跨平台与绝对置顶**：
  - Mac 同步时全自动读取系统 `TextReplacements.db` 导出为 `custom_phrase.txt` 并推送到仓库；
  - Windows 执行同步时自动接收更新并热重载；
  - 锁定 `custom_phrase/initial_quality: 999`，保证快捷短语（邮箱、电话、常用地址等）永远在候选词**第 1 位首选**输出！
- 🎨 **Rheatin Solarized 昼夜双主题自适应**：
  - **浅色模式**：自动启用 **Rheatin Solarized Light**（温润暖象牙白底 + 优雅深墨字 + 经典紫红高亮）；
  - **深色模式**：自动启用 **Rheatin Solarized Dark**（毛玻璃深青墨底色 + 悬浮小胶囊排版）；
  - 完美跟随 macOS 与 Windows 系统的深浅外观无缝自动切换！
- 💡 **Lua 效率百宝箱**：
  - **日期与时间**：输入 `date`（或 `rq`）秒出 `2026-09-18`；输入 `time`（或 `sj`）出 `11:45:30`；输入 `week` 出 `星期五` / `Friday`；
  - **时间戳神器**：输入 `ts` 或 `now` 秒出 10 位 / 13 位 Unix 毫秒时间戳；
  - **金额大写**：输入 `R1234.56` 瞬间转换为财务中文大写 `壹仟贰佰叁拾肆元伍角陆分`；
  - **随机 UUID**：输入 `uuid` 实时生成标准 UUID v4（支持大小写双选）；
- 📐 **盘古之白优雅排版 (Pangu Spacing)**：
  - 内置中英智能空格滤镜，中文与英文字母/数字混输时（如 `使用 iPhone 16 打字`）自动优雅插入微空格，排版赏心悦目！
- 🤖 **GitHub Actions 上游词库自动化追更**：
  - 内置 CI 定时工作流，每周全自动检查 MoeType 萌娘百科最新 Release 并同步更新，永不落伍！
- 🔤 **思源宋体 Heavy 原生支持**：智能检测系统字体库，按需自动安装。
- 🪟 **分应用中英文自动切换**（除聊天软件与浏览器外一律默认英文）：
  Windows 与 macOS 的触发机制完全不同，踩坑点与正确姿势详见
  [docs/分应用中英文切换.md](docs/分应用中英文切换.md)。

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
├── clean.sh                    # 🧹 macOS/Linux 平台专一化极简瘦身脚本
├── clean.ps1                   # 🧹 Windows 小狼毫平台专一化极简瘦身脚本
├── sync.sh                      # 🔄 macOS/Linux 一键词频同步 (自动触发 clean 瘦身)
├── sync.ps1                     # 🔄 Windows 一键词频同步 (自动触发 clean 瘦身)
├── sync_watcher.ps1             # ⚡ Windows 后台变动监听守护服务
├── custom_phrase.example.txt    # 📋 示例系统短语公开模板 (个人明文由 AES-256 vault.enc 加密)
├── snippets.txt                 # 📋 常用代码与文本片段定义表 (/sh, /git, /mail 等)
├── vault.enc                    # 🔒 AES-256 密文同步包 (包含个人私密短语与用户打字词频)
├── default.custom.yaml          # 默认方案 (rime_frost) 与中英切换快捷键
├── squirrel.custom.yaml         # 鼠须管外观与 Rheatin Solarized 配色 (macOS)
├── weasel.custom.yaml           # 小狼毫外观与 Rheatin Solarized 配色 (Windows)
├── rime_frost.custom.yaml       # 白霜拼音行为定制与万象语言模型挂载
├── rime_frost.extended.dict.yaml# 聚合词库入口 (白霜拼音全量 + 萌娘百科)
├── symbols_v.yaml               # 正统 v 模式符号映射表
├── fonts/                       # 思源宋体 Heavy & Symbols Nerd Font 字体库
├── tools/
│   ├── New-AppOptions.ps1       # 🪟 Windows: 扫描运行中/已安装程序，生成 weasel app_options 片段
│   └── New-AppOptions.sh        # 🍎 macOS: 扫描运行中/已安装程序，生成/智能合并 squirrel app_options 片段
├── docs/
│   └── 分应用中英文切换.md       # 🪟 Weasel 分应用中英切换原理、修复与自检清单
├── sync/                        # 🧠 个人自造词与跨平台词频快照归档
└── README.md
```
