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
    ---@type loop.SelectorItem
    local choices = {}
    local initial
    for _, name in ipairs(debuggers.debugger_names()) do
        table.insert(choices,
            {
                label = name,
                data = name,
            })
        if cur_debugger == name then
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
