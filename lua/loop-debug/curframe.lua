local M           = {}

local debugevents = require('loop-debug.debugevents')
local loopsigns   = require('loop.signs')
local config      = require("loop-debug.config")
local filetools   = require('loop.tools.file')
local uitools     = require('loop.tools.uitools')

---@type loop.signs.Group
local _sign_group

local _sign_name  = "currentframe"

local _init_done  = false
function M.init()
    if _init_done then return end
    _init_done = true

    local highlight = "LoopDebugCurrentFrame"
    vim.api.nvim_set_hl(0, highlight, { link = "Todo" })

    _sign_group = loopsigns.define_group("CurrentFrame", { priority = config.current.sign_priority.currentframe })
    _sign_group.define_sign(_sign_name, config.current.symbols.debug_frame or ">", highlight)

    debugevents.add_tracker({
        on_debug_start = function()

        end,
        on_debug_end = function()

        end,
        on_view_udpate = function(view)
            local frame = view.frame
            if not (frame and frame.source and frame.source.path) then
                _sign_group.remove_signs()
                return
            end
            if view.trigger ~= "variable" then
                if not filetools.file_exists(frame.source.path) then return end
                -- Open file and move cursor
                uitools.smart_open_file(frame.source.path, frame.line, frame.column)
                -- Place sign for current frame
                _sign_group.set_file_sign(1, frame.source.path, frame.line, _sign_name)
            end
        end
    })
end

return M
