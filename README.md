# ❄️ Rime_Config (个人 Rime 鼠须管配置与字体管理)

基于 [雾凇拼音 (rime-ice)](https://github.com/iDvel/rime-ice) 深度定制的个人输入法配置。

## ✨ 特性

- 🚀 **一键自动化安装**：自动检测系统，自动安装 Squirrel、自动拉取最新 rime-ice 词库、自动安装私有字体。
- 🎨 **Rheatin Solarized 配色**：个性化定制的专属 Solarized 深色主题。
- 🔤 **思源宋体 Heavy 支持**：内置思源宋体 Heavy (简/繁) 字体，雅致端庄。
- ⚡ **精简配置分离**：纯净的 `*.custom.yaml` 补丁，与官方词库解耦，随时平滑升级。

---

## 🚀 新电脑一键安装 (One-Liner)

在任何全新的 Mac 终端中，直接运行以下单行命令即可全自动搞定：

```bash
curl -fsSL https://raw.githubusercontent.com/rheatin/Rime_Config/main/install.sh | bash
```

或者本地克隆后执行：

```bash
git clone https://github.com/rheatin/Rime_Config.git
cd Rime_Config
chmod +x install.sh
./install.sh
```

---

## 📂 仓库结构

```text
.
├── install.sh              # 全自动安装与部署脚本
├── default.custom.yaml     # 候选词数量及中英切换逻辑
├── squirrel.custom.yaml    # 鼠须管样式、应用行为与 Rheatin Solarized 配色
├── rime_ice.custom.yaml    # 雾凇拼音行为定制
├── fonts/                  # 思源宋体 (Heavy) 字体源文件
└── README.md
```
