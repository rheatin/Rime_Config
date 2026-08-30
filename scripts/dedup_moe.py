#!/usr/bin/env python3
# ==============================================================================
# MoeType 词库自动去重脚本 (只剔除与雾凇拼音重合的词条，保持雾凇拼音纯净)
# ==============================================================================

import os
import sys

def main():
    script_dir = os.path.dirname(os.path.abspath(__file__))
    repo_dir = os.path.dirname(script_dir)
    
    # 获取 Rime 配置目录 (macOS/Linux/Windows)
    home = os.path.expanduser("~")
    rime_dir = os.path.join(home, "Library", "Rime")
    if not os.path.exists(rime_dir):
        rime_dir = os.path.join(home, ".local", "share", "rime")
    if not os.path.exists(rime_dir):
        appdata = os.environ.get("APPDATA", "")
        if appdata:
            rime_dir = os.path.join(appdata, "Rime")

    cn_dicts_dir = os.path.join(rime_dir, "cn_dicts")
    if not os.path.exists(cn_dicts_dir):
        print(f"❌ 未找到雾凇拼音 cn_dicts 目录: {cn_dicts_dir}")
        return

    print("🔍 正在扫描雾凇拼音原生词库...")
    rime_words = set()
    for root, _, files in os.walk(cn_dicts_dir):
        for fn in files:
            if fn.endswith('.dict.yaml') or fn.endswith('.txt'):
                fp = os.path.join(root, fn)
                with open(fp, 'r', encoding='utf-8', errors='ignore') as f:
                    in_body = False
                    for line in f:
                        line = line.strip()
                        if line == '...':
                            in_body = True
                            continue
                        if not in_body or not line or line.startswith('#'):
                            continue
                        parts = line.split('\t')
                        if parts and parts[0].strip():
                            rime_words.add(parts[0].strip())

    print(f"📊 雾凇拼音原生词库总量: {len(rime_words):,} 词")

    moe_file = os.path.join(repo_dir, "moe.dict.yaml")
    if not os.path.exists(moe_file):
        print(f"❌ 未找到 moe.dict.yaml 文件: {moe_file}")
        return

    print("✂️  正在对 MoeType 词库进行精确去重...")
    temp_file = moe_file + ".tmp"
    total_moe = 0
    kept_moe = 0
    removed_moe = 0

    with open(moe_file, 'r', encoding='utf-8') as fin, open(temp_file, 'w', encoding='utf-8') as fout:
        in_body = False
        for line in fin:
            if line.strip() == '...':
                in_body = True
                fout.write(line)
                continue
            if not in_body:
                fout.write(line)
                continue
            if not line.strip() or line.startswith('#'):
                fout.write(line)
                continue
            
            parts = line.strip().split('\t')
            word = parts[0].strip()
            total_moe += 1
            
            if word in rime_words:
                removed_moe += 1
            else:
                kept_moe += 1
                fout.write(line)

    os.replace(temp_file, moe_file)
    print(f"✅ 去重完成！原始: {total_moe:,} | 剔除重叠: {removed_moe:,} | 保留独有: {kept_moe:,}")

if __name__ == "__main__":
    main()
