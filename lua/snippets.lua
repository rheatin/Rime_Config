-- ==============================================================================
-- 快速文本与代码片段引擎 (Snippets Engine)
-- 自动加载并合并默认片段库 (snippets.yaml) 与 个人私密片段库 (snippets.custom.yaml)
-- 支持前缀快速展开、原生 | 多行块文本与私密片段高优先覆盖
-- ==============================================================================

local M = {}

local function unescape_str(s)
    if not s then return "" end
    return s:gsub("\\n", "\n"):gsub("\\t", "\t"):gsub("\\r", "\r")
end

local function strip_quotes(s)
    if not s then return "" end
    s = s:gsub("^%s+", ""):gsub("%s+$", "")
    if (#s >= 2 and s:sub(1, 1) == '"' and s:sub(-1, -1) == '"') or
       (#s >= 2 and s:sub(1, 1) == "'" and s:sub(-1, -1) == "'") then
        return s:sub(2, -2)
    end
    return s
end

-- 解析 YAML 片段文件
local function load_yaml_snippets(filepath, default_quality)
    local map = {}
    local file = io.open(filepath, "r")
    if not file then return map end

    local cur_trigger = nil
    local cur_item = nil
    local multiline_active = false
    local multiline_indent = nil
    local multiline_buf = {}

    for line in file:lines() do
        local raw = line:gsub("[\r\n]+$", "")
        local s = raw:gsub("^%s+", ""):gsub("%s+$", "")
        local leading = #(raw:match("^(%s*)") or "")

        if multiline_active then
            if not multiline_indent and s ~= "" then
                multiline_indent = leading
            end
            if multiline_indent and leading >= multiline_indent then
                table.insert(multiline_buf, raw:sub(multiline_indent + 1))
            elseif s == "" then
                table.insert(multiline_buf, "")
            else
                -- 结束当前多行块
                if cur_item then
                    cur_item.text = table.concat(multiline_buf, "\n")
                end
                multiline_active = false
                multiline_indent = nil
                multiline_buf = {}
            end
        end

        if not multiline_active then
            if s ~= "" and not s:match("^#") then
                -- 1. 匹配触发前缀，如 /sh: 或 "/176":
                local trigger_match = raw:match("^([/%w_%-]+):%s*$") or raw:match('^"([/%w_%-]+)":%s*$')
                if trigger_match then
                    cur_trigger = trigger_match
                    map[cur_trigger] = map[cur_trigger] or {}
                    cur_item = nil
                elseif cur_trigger and s:match("^%-%s*") then
                    -- 2. 列表项开始，如 - text: | 或 - text: ...
                    cur_item = { text = "", comment = "", quality = default_quality or 1000 }
                    table.insert(map[cur_trigger], cur_item)
                    local rest = s:gsub("^%-%s*", "")
                    if rest:match("^text:%s*|") then
                        multiline_active = true
                        multiline_indent = nil
                        multiline_buf = {}
                    elseif rest:match("^text:%s*") then
                        local v = rest:gsub("^text:%s*", "")
                        cur_item.text = unescape_str(strip_quotes(v))
                    end
                elseif cur_item then
                    -- 3. 列表项属性
                    if s:match("^text:%s*|") then
                        multiline_active = true
                        multiline_indent = nil
                        multiline_buf = {}
                    elseif s:match("^text:%s*") then
                        local v = s:gsub("^text:%s*", "")
                        cur_item.text = unescape_str(strip_quotes(v))
                    elseif s:match("^desc:%s*") or s:match("^comment:%s*") then
                        local v = s:gsub("^[a-z]+:%s*", "")
                        cur_item.comment = strip_quotes(v)
                    end
                end
            end
        end
    end

    if multiline_active and cur_item then
        cur_item.text = table.concat(multiline_buf, "\n")
    end

    file:close()
    return map
end

-- 合并 base 片段与 custom 私密片段 (custom 项拥有最高优先级并置顶)
local function merge_snippets(base_map, custom_map)
    local merged = {}
    for k, v in pairs(base_map) do
        merged[k] = {}
        for _, item in ipairs(v) do
            table.insert(merged[k], item)
        end
    end

    for k, v in pairs(custom_map) do
        if not merged[k] then
            merged[k] = {}
            for _, item in ipairs(v) do
                table.insert(merged[k], item)
            end
        else
            -- 个人私密片段置于同名前置首位
            local combined = {}
            for _, item in ipairs(v) do
                table.insert(combined, item)
            end
            for _, item in ipairs(merged[k]) do
                table.insert(combined, item)
            end
            merged[k] = combined
        end
    end
    return merged
end

function M.init(env)
    local user_dir = rime_api and rime_api.get_user_data_dir and rime_api.get_user_data_dir() or ""
    local base_path = (user_dir ~= "" and (user_dir .. "/snippets.yaml")) or "snippets.yaml"
    local custom_path = (user_dir ~= "" and (user_dir .. "/snippets.custom.yaml")) or "snippets.custom.yaml"

    local base_map = load_yaml_snippets(base_path, 1000)
    local custom_map = load_yaml_snippets(custom_path, 1100)

    env.snippets_map = merge_snippets(base_map, custom_map)
end

function M.func(input, seg, env)
    if not env.snippets_map then return end

    local entries = env.snippets_map[input]
    if entries then
        for _, item in ipairs(entries) do
            local cand = Candidate("snippet", seg.start, seg._end, item.text, item.comment)
            cand.quality = item.quality or 1000
            yield(cand)
        end
    end
end

return M
