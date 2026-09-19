-- ==============================================================================
-- 盘古之白 (Pangu Spacer) - 中文与英数之间自动优雅插入半角空格
-- 示例：`使用iPhone16打字` → `使用 iPhone16 打字`
-- ==============================================================================

local function add_pangu_spaces(s)
    -- 中文字符编码区间：[\228-\233][\128-\191][\128-\191] (UTF-8 CJK 范围 U+4E00..U+9FFF)
    -- 在中文字符后与英文字母/数字前插入空格
    s = s:gsub("([\228-\233][\128-\191][\128-\191])([%a%d])", "%1 %2")
    -- 在英文字母/数字后与中文字符前插入空格
    s = s:gsub("([%a%d])([\228-\233][\128-\191][\128-\191])", "%1 %2")
    return s
end

-- 判断文本是否同时包含中文字符与英文字母/数字
local function is_mixed_cn_en_num(s)
    return s:find("[\228-\233][\128-\191][\128-\191]") and s:find("[%a%d]")
end

local function cn_en_spacer(input, env)
    for cand in input:iter() do
        local c = cand
        if is_mixed_cn_en_num(c.text) then
            local spaced_text = add_pangu_spaces(c.text)
            if spaced_text ~= c.text then
                c = c:to_shadow_candidate(c.type, spaced_text, c.comment)
            end
        end
        yield(c)
    end
end

return cn_en_spacer
