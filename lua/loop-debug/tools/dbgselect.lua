local M = {}

local config = require("loop-debug.config")
local selector = require("loop.tools.selector")

function M.select(callback)
    ---@type loop.SelectorItem
    local choices = {}
    for name, _ in pairs(config.current.debuggers) do
        table.insert(choices,
            {
                label = name,
                data = name,
            })
    end
    selector.select({
            prompt = "Select debugger",
            items = choices,
        },
        callback
    )
end

return M
