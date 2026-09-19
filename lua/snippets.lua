-- ==============================================================================
-- 快速文本与代码片段引擎 (Snippets Engine)
-- 读取用户目录下的 snippets.txt，支持前缀快速展开与多行模板
-- ==============================================================================

local M = {}

local function unescape_str(s)
    if not s then return "" end
    return s:gsub("\\n", "\n"):gsub("\\t", "\t"):gsub("\\r", "\r")
end

local function load_snippets(filepath)
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
    local filepath = (user_dir ~= "" and (user_dir .. "/snippets.txt")) or "snippets.txt"
    env.snippets_map = load_snippets(filepath)
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
