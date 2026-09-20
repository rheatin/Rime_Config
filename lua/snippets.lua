-- ==============================================================================
-- 快速文本与代码片段引擎 (Snippets Engine)
-- 优先读取 snippets.yaml (支持优雅的多行 | 块与标准 YAML 格式)，
-- 向下兼容旧版 Tab 分隔的 snippets.txt
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

-- 优雅解析 snippets.yaml
local function load_yaml_snippets(filepath)
    local map = {}
    local file = io.open(filepath, "r")
    if not file then return nil end

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
                -- 1. 匹配触发前缀，如 /sh: 或 "/sh":
                local trigger_match = raw:match("^([/%w_%-]+):%s*$") or raw:match('^"([/%w_%-]+)":%s*$')
                if trigger_match then
                    cur_trigger = trigger_match
                    map[cur_trigger] = map[cur_trigger] or {}
                    cur_item = nil
                elseif cur_trigger and s:match("^%-%s*") then
                    -- 2. 列表项开始，如 - text: | 或 - text: ...
                    cur_item = { text = "", comment = "" }
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

-- 向下兼容解析旧版 snippets.txt (Tab 分隔)
local function load_tsv_snippets(filepath)
    local map = {}
    local file = io.open(filepath, "r")
    if not file then return map end

    for line in file:lines() do
        line = line:gsub("^%s+", ""):gsub("%s+$", "")
        if line ~= "" and not line:match("^#") then
            local trigger, text, comment = line:match("^([^\t]+)\t([^\t]+)\t?(.*)$")
            if trigger and text then
                map[trigger] = map[trigger] or {}
                table.insert(map[trigger], {
                    text = unescape_str(text),
                    comment = comment or ""
                })
            end
        end
    end
    file:close()
    return map
end

function M.init(env)
    local user_dir = rime_api and rime_api.get_user_data_dir and rime_api.get_user_data_dir() or ""
    local yaml_path = (user_dir ~= "" and (user_dir .. "/snippets.yaml")) or "snippets.yaml"
    local txt_path = (user_dir ~= "" and (user_dir .. "/snippets.txt")) or "snippets.txt"

    -- 优先读取 snippets.yaml，若不存在则回退至 snippets.txt
    local yaml_data = load_yaml_snippets(yaml_path)
    if yaml_data then
        env.snippets_map = yaml_data
    else
        env.snippets_map = load_tsv_snippets(txt_path)
    end
end

function M.func(input, seg, env)
    if not env.snippets_map then return end

    local entries = env.snippets_map[input]
    if entries then
        for _, item in ipairs(entries) do
            local cand = Candidate("snippet", seg.start, seg._end, item.text, item.comment)
            cand.quality = 1000
            yield(cand)
        end
    end
end

return M
