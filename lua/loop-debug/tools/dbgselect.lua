local M = {}
local selector = require("loop.tools.selector")
local jsontools = require("loop.json.jsontools")
local debuggers = require("loop-debug.debuggers")

function M.select(callback, data, path)
    local cur_debugger
    if type(path) == "string" then
        local current = jsontools.get_at_path(data, path)
        if type(current) == "string" then
            cur_debugger = current
        end
    end
    local summary = debuggers.debuggers_summary()
    ---@type loop.SelectorItem
    local choices = {}
    local initial
    for _, debugger_id in ipairs(vim.fn.sort(vim.tbl_keys(summary))) do
        local language = summary[debugger_id]
        local annotation = (language and language ~= debugger_id) and ("(%s)"):format(language) or nil
        table.insert(choices,
            {
                label_chunks = annotation and  {{debugger_id}, {" "}, {annotation, "keyword"}} or {{debugger_id}},
                data = debugger_id,
            })
        if cur_debugger == debugger_id then
            initial = #choices
        end
    end
    selector.select({
            prompt = "Select debugger",
            items = choices,
            initial = initial,
        },
        callback
    )
end

return M
