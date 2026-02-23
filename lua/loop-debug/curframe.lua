local M           = {}

local debugevents = require('loop-debug.debugevents')
local extmarks    = require('loop.extmarks')
local loopsigns   = require('loop.signs')
local config      = require("loop-debug.config")
local filetools   = require('loop.tools.file')
local uitools     = require('loop.tools.uitools')

---@type loop.signs.Group
local _sign_group

---@type loop.extmarks.GroupFunctions
local _highlight_group

local _sign_name  = "currentframe"

local _init_done  = false
function M.init()
    if _init_done then return end
    _init_done = true

    local reddish_bg = function()
        local normal = vim.api.nvim_get_hl(0, { name = "Normal" })
        local bg = normal.bg or 0x000000

        local reddish = 0xB23434
        return uitools.blind_colors(bg, reddish, 0.12)
    end

    local sign_highlight, line_highlight = "LoopDebugCurrentFrame", "LoopDebugCurrentFrameLine"

    vim.api.nvim_set_hl(0, sign_highlight, { link = "Todo" })
    vim.api.nvim_set_hl(0, line_highlight, { bg = reddish_bg() })

    _sign_group = loopsigns.define_group("CurrentFrame", { priority = config.current.sign_priority.currentframe })
    _sign_group.define_sign(_sign_name, config.current.symbols.debug_frame or ">", sign_highlight)

    _highlight_group = extmarks.define_group("CurrentFrameLine", { priority = config.current.sign_priority.currentframe })

    debugevents.add_tracker({
        on_debug_start = function()

        end,
        on_debug_end = function()

        end,
        on_view_udpate = function(view)
            local frame = view.frame
            if not (frame and frame.source and frame.source.path) then
                _sign_group.remove_signs()
                _highlight_group.remove_extmarks()
                return
            end
            if view.trigger ~= "variable" then
                if not filetools.file_exists(frame.source.path) then return end
                -- Open file and move cursor
                uitools.smart_open_file(frame.source.path, frame.line, frame.column)
                -- Place sign for current frame
                _sign_group.set_file_sign(1, frame.source.path, frame.line, _sign_name)
                -- highlight line
                _highlight_group.set_file_extmark(1, frame.source.path, frame.line, 0, {
                    line_hl_group = line_highlight,
                })
            end
        end
    })
end

return M
