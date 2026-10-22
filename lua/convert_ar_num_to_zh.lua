-- 阿拉伯数字与中文数字互转工具。
--
-- 供 date_translator 等脚本使用（通过 require("convert_ar_num_to_zh")）。
-- 注意：librime-lua 的 package.path 覆盖用户目录下的 lua/，
-- 因此本文件必须与调用方放在同一目录（~/Library/Rime/lua/）。
--
-- 导出：
--   M.digits(number, circle)  逐位转换。circle=true 用「〇」，false 用「零」
--                             例: digits(2026, true)  -> "二〇二六"
--                                 digits(2026, false) -> "二零二六"
--   M.convert(number)          按中文数位读法转换（十、百、千、万、亿）
--                             例: convert(10)   -> "十"
--                                 convert(11)   -> "十一"
--                                 convert(2026) -> "二千零二十六"

local M = {}

-- 用字符表而非字符串下标，避免 UTF-8 多字节被按字节切开
local DIGITS = { "零", "一", "二", "三", "四", "五", "六", "七", "八", "九" }
local CIRCLE_DIGITS = { "〇", "一", "二", "三", "四", "五", "六", "七", "八", "九" }
local UNITS = { "", "十", "百", "千" }
local GROUP_UNITS = { "", "万", "亿", "万亿" }

-- 逐位转换
function M.digits(number, circle)
    local n = tonumber(number)
    if n == nil then return "" end
    local text = tostring(math.floor(math.abs(n)))
    local table_digits = circle and CIRCLE_DIGITS or DIGITS
    local out = {}
    for i = 1, #text do
        out[i] = table_digits[tonumber(text:sub(i, i)) + 1]
    end
    return table.concat(out)
end

-- 把 1~9999 的分组转成中文（不含万/亿单位）
local function group_to_cn(group)
    local group_text = tostring(group)
    local out = {}
    local pending_zero = false
    for i = 1, #group_text do
        local d = tonumber(group_text:sub(i, i))
        if d == 0 then
            pending_zero = true
        else
            if pending_zero and #out > 0 then
                out[#out + 1] = "零"
            end
            pending_zero = false
            out[#out + 1] = DIGITS[d + 1] .. UNITS[#group_text - i + 1]
        end
    end
    return table.concat(out)
end

-- 按中文数位读法转换整个非负整数
function M.convert(number)
    local n = tonumber(number)
    if n == nil then return "" end
    n = math.floor(n)
    if n < 0 then return "负" .. M.convert(-n) end
    if n == 0 then return "零" end

    -- 按四位一组切分，groups[1] 为最低位组
    local text = tostring(n)
    local groups = {}
    while #text > 0 do
        groups[#groups + 1] = tonumber(text:sub(-4))
        text = text:sub(1, -5)
    end

    local out = {}
    -- 从高位组向低位组输出
    for gi = #groups, 1, -1 do
        local value = groups[gi]
        local unit = GROUP_UNITS[gi]
        if value ~= 0 then
            -- 低位组不足一千时，与高位组之间需要补「零」
            if #out > 0 and value < 1000 then
                out[#out + 1] = "零"
            end
            out[#out + 1] = group_to_cn(value) .. unit
        end
    end

    local result = table.concat(out)
    -- 10~19 开头不念「一」：10 -> 十，11 -> 十一
    -- （仅在整串以「一十」开头时生效，110 等不受影响）
    result = result:gsub("^一十", "十")
    if result == "" then result = "零" end
    return result
end

return M
