#!/usr/bin/env python3
# -*- coding: utf-8 -*-
# ==============================================================================
# Rime 核心配置动态组装与渲染引擎 (rime_generator.py)
# 职责：
#   1. 根据用户画像 (.rime_profile) 动态渲染词库聚合表 (rime_frost.extended.dict.yaml)
#   2. 动态生成目标方案补丁 (<schema>.custom.yaml)，解决双拼/五笔方案白板与万象按需挂载
#   3. 动态融合用户个性化覆盖文件 (*.user.yaml)，保证字体与主题个人定制不污染 Git 仓库
#   4. 动态更新 default.custom.yaml 指向当前活跃主方案
# ==============================================================================

import os
import sys
import re

def load_profile(profile_path):
    profile = {
        'RIME_FRAMEWORK': 'rime-frost',
        'RIME_CUSTOM_REPO': '',
        'RIME_SCHEMA': 'rime_frost',
        'RIME_MODEL': 'wanxiang_lts',
        'RIME_CUSTOM_MODEL_URL': '',
        'RIME_ENABLE_MOE': 'true',
        'RIME_ENABLE_CELLS': 'true',
        'RIME_ENABLE_TENCENT': 'false',
        'RIME_CUSTOM_DICT_URL': ''
    }
    if os.path.exists(profile_path):
        try:
            with open(profile_path, 'r', encoding='utf-8') as f:
                for line in f:
                    line = line.strip()
                    if line and not line.startswith('#') and '=' in line:
                        k, v = line.split('=', 1)
                        k = k.strip()
                        v = v.strip().strip('"\'')
                        profile[k] = v
        except Exception as e:
            print(f"⚠️ 读取画像配置失败: {e}", file=sys.stderr)
    return profile

def render_extended_dict(profile, out_path):
    enable_moe = profile.get('RIME_ENABLE_MOE', 'true').lower() == 'true'
    enable_cells = profile.get('RIME_ENABLE_CELLS', 'true').lower() == 'true'
    enable_tencent = profile.get('RIME_ENABLE_TENCENT', 'false').lower() == 'true'

    tables = [
        'cn_dicts/8105',
        'cn_dicts/41448',
        'cn_dicts/GB18030-2022',
        'cn_dicts/base',
        'cn_dicts/ext',
        'cn_dicts/others',
        'cn_dicts/corrections'
    ]
    if enable_tencent:
        tables.append('cn_dicts/tencent')
    if enable_cells:
        tables.extend([
            'cn_dicts_cell/medication',
            'cn_dicts_cell/industry_product',
            'cn_dicts_cell/exthot',
            'cn_dicts_cell/chess',
            'cn_dicts_cell/chess2',
            'cn_dicts_cell/animal',
            'cn_dicts_cell/game',
            'cn_dicts_cell/idiom',
            'cn_dicts_cell/sport',
            'cn_dicts_cell/media',
            'cn_dicts_cell/shulihua',
            'cn_dicts_cell/food',
            'cn_dicts_cell/inputmethod',
            'cn_dicts_cell/history',
            'cn_dicts_cell/place',
            'cn_dicts_cell/geography',
            'cn_dicts_cell/name2',
            'cn_dicts_cell/literature',
            'cn_dicts_cell/music',
            'cn_dicts_cell/computer',
            'cn_dicts_cell/composite',
            'cn_dicts_cell/luna',
            'cn_dicts_cell/name'
        ])
    if enable_moe:
        tables.append('moe')

    content = [
        '# Rime Extended Dictionary',
        '# 动态生成：根据 .rime_profile 自选词库精准挂载（杜绝缺失依赖引发编译崩溃）',
        '',
        '---',
        'name: rime_frost.extended',
        'version: "2026.11.05"',
        'sort: by_weight',
        'use_preset_vocabulary: false',
        'import_tables:'
    ]
    for t in tables:
        content.append(f'  - {t}')
    content.append('...\n')

    text = '\n'.join(content)
    os.makedirs(os.path.dirname(os.path.abspath(out_path)), exist_ok=True)
    with open(out_path, 'w', encoding='utf-8') as f:
        f.write(text)

def render_schema_custom(profile, schema_id, out_path):
    model_choice = profile.get('RIME_MODEL', 'wanxiang_lts').lower()
    enable_wanxiang = (model_choice == 'wanxiang_lts')

    grammar_section = ""
    if enable_wanxiang:
        grammar_section = """
  # 挂载万象 (Wanxiang) LTS 语言模型提升长句整句命中率
  "grammar/language": wanxiang-lts-zh-hans
  "grammar/collocation_max_length": 5
  "grammar/collocation_min_length": 2
  "grammar/non_collocation_penalty": -4
  "translator/grammar_penalty": -4
"""

    content = f"""# ==============================================================================
# Rime 方案补丁: {schema_id}.custom.yaml
# 动态生成：为全拼/双拼/五笔自动满血注入 Snippets、UUID、盘古空格、退格防丢词等全部特性
# ==============================================================================
patch:
  # 初始状态设为英文 (reset: 1，全局默认英文，仅少数浏览器/聊天软件自动切中文)
  "switches/@0/reset": 1

  # 默认开启 Emoji 候选项直接输出 (💀 关 / 😄 开)
  "switches/@4/reset": 1

  # 彻底关闭候选词后的拼音注释与多余提示
  "translator/always_show_comments": false
  "translator/spelling_hints": 0

  # 挂载聚合词库 (包含细胞词库与可选 MoeType)
  "translator/dictionary": rime_frost.extended

  # 自定义短语 (系统文本替换)：设置超高权重确保永远排在首选第 1 位
  "custom_phrase/initial_quality": 999
  "custom_phrase/enable_sentence": false
{grammar_section}
  # 符号系统：导入正统 symbols_v.yaml
  "punctuator/symbols":
    __include: symbols_v:/symbols

  # 标点符号定制：中文模式下单双引号直接输出标准英文半角直引号 ' 与 "
  "punctuator/half_shape/'": "'"
  'punctuator/half_shape/"': '"'

  # 正则识别器：
  # 1. 严格限制计算器仅由大写 C+数字 引导 (如 C1+1)
  # 2. 释放 v 给 symbols 符号系统 (如 vfh 符号, vjt 箭头, vsz 数字)
  # 3. 赋予 / 给 Snippets 代码片段引擎 (支持短横线 -，如 /sh, /git, /todo-1)
  "recognizer/patterns/calculator": "^C[0-9].*$"
  "recognizer/patterns/punct": "^v([0-9]|10|[A-Za-z]+)$"
  "recognizer/patterns/snippets": "^/([a-zA-Z0-9_-]+)?$"

  # 快捷键：分号 ; 快捷选第 2 项，减号 - 向上翻页，等号 = 向下翻页
  "key_binder/bindings":
    - {{ when: has_menu, accept: semicolon, send: 2 }}
    - {{ when: has_menu, accept: minus, send: Page_Up }}
    - {{ when: has_menu, accept: equal, send: Page_Down }}

  # 扩展翻译器：追加 UUID 随机生成与 Snippets 片段展开功能
  "engine/translators/@after_11": lua_translator@*uuid
  "engine/translators/@after_12": lua_translator@*snippets

  # 优化滤镜列表：加入盘古之白中英微距排版滤镜
  "engine/filters":
    - reverse_lookup_filter@radical_reverse_lookup
    - lua_filter@*autocap_filter
    - lua_filter@*v_filter
    - lua_filter@*pin_cand_filter
    - lua_filter@*reduce_english_filter
    - lua_filter@*aux_lookup_filter
    - lua_filter@*cn_en_spacer
    - simplifier@emoji
    - simplifier@chaifen
    - simplifier@chaifen_all
    - simplifier@chinese_english
    - simplifier@traditionalize
    - simplifier@mars
    - uniquifier

  # 英文词典权重 (退格时不丢词)
  "melt_eng/initial_quality": 2

  # 空码（无候选词）时不自动整段清空，保留输入码，允许用户按退格键逐步回退修改
  "speller/auto_clear": manual
"""
    os.makedirs(os.path.dirname(os.path.abspath(out_path)), exist_ok=True)
    with open(out_path, 'w', encoding='utf-8') as f:
        f.write(content)

def render_default_custom(schema_id, out_path):
    content = f"""# ==============================================================================
# Rime 全局默认配置补丁: default.custom.yaml
# 动态生成：锁定当前用户自选的主输入方案为 {schema_id}
# ==============================================================================
patch:
  # 输入方案列表：仅保留当前用户自选方案
  schema_list:
    - schema: {schema_id}

  # 候选词数量
  menu/page_size: 5

  # 分应用中西文切换隔离保护 (将 ascii_mode 移出 save_options)
  switcher/save_options:
    - full_shape
    - ascii_punct
    - traditionalization
    - emoji
    - chinese_english
    - chaifen
    - mars
    - pin_cand

  # 中文模式下单双引号直接输出标准英文半角直引号 ' 与 "
  "punctuator/half_shape/'": "'"
  'punctuator/half_shape/"': '"'

  # 中西文切换快捷键
  ascii_composer:
    good_old_caps_lock: true
    switch_key:
      Caps_Lock: clear
      Shift_L: inline_ascii
      Shift_R: clear
      Control_L: noop
      Control_R: noop
"""
    os.makedirs(os.path.dirname(os.path.abspath(out_path)), exist_ok=True)
    with open(out_path, 'w', encoding='utf-8') as f:
        f.write(content)

def merge_user_yaml(base_path, user_path, out_path):
    if not os.path.exists(base_path):
        return
    if not os.path.exists(user_path):
        if base_path != out_path:
            with open(base_path, 'r', encoding='utf-8') as f:
                content = f.read()
            with open(out_path, 'w', encoding='utf-8') as f:
                f.write(content)
        return

    with open(base_path, 'r', encoding='utf-8') as f:
        base_content = f.read()
    with open(user_path, 'r', encoding='utf-8') as f:
        user_lines = f.readlines()

    user_patch_lines = []
    in_patch = False
    for line in user_lines:
        s = line.strip()
        if s.startswith('patch:'):
            in_patch = True
            continue
        if in_patch:
            if s and not line.startswith(' ') and not line.startswith('\t') and not s.startswith('#'):
                break
            user_patch_lines.append(line)

    merged = base_content.rstrip() + '\n\n  # ─── 个人用户覆盖 (from *.user.yaml) ───\n' + ''.join(user_patch_lines) + '\n'
    os.makedirs(os.path.dirname(os.path.abspath(out_path)), exist_ok=True)
    with open(out_path, 'w', encoding='utf-8') as f:
        f.write(merged)

def main():
    script_dir = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    profile_path = os.path.join(script_dir, '.rime_profile')
    profile = load_profile(profile_path)
    schema_id = profile.get('RIME_SCHEMA', 'rime_frost')

    # 1. 渲染 rime_frost.extended.dict.yaml
    ext_dict_path = os.path.join(script_dir, 'rime_frost.extended.dict.yaml')
    render_extended_dict(profile, ext_dict_path)
    print(f"✅ 已动态生成词库聚合表: {ext_dict_path}")

    # 2. 渲染当前活跃方案补丁 <schema>.custom.yaml
    schema_custom_path = os.path.join(script_dir, f"{schema_id}.custom.yaml")
    render_schema_custom(profile, schema_id, schema_custom_path)
    print(f"✅ 已动态生成主方案补丁: {schema_custom_path} (方案: {schema_id})")

    # 3. 渲染 default.custom.yaml
    default_custom_path = os.path.join(script_dir, 'default.custom.yaml')
    render_default_custom(schema_id, default_custom_path)
    print(f"✅ 已动态更新主方案列表: {default_custom_path}")

if __name__ == '__main__':
    main()
