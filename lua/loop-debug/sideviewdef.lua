local M               = {}

local CompBuffer      = require('loop.buf.CompBuffer')
local VariablesComp   = require('loop-debug.comp.Variables')
local StackTraceComp  = require('loop-debug.comp.StackTrace')
local SessionListComp = require('loop-debug.comp.SessionList')

local _window_defs    = {
    {
        key                  = "variables",
        label                = "Variables",
        buf_type             = "loopdebug-vars",
        comp_class           = VariablesComp,

        -- layout defaults
        default_width_ratio  = 0.20,
        default_height_ratio = 0.50,
    },
    {
        key = "callstack",
        label = "Call Stack",
        buf_type = "loopdebug-callstack",
        comp_class = StackTraceComp,
        default_height_ratio = 0.30,
    },
    {
        key = "sessions",
        label = "Sessions",
        buf_type = "loopdebug-sessions",
        comp_class = SessionListComp,
        -- last window does not need height ratio
    }
}

---@type loop.SideViewDef
local side_view_def   = {
    get_comp_buffers = function()
        local comp_buffers = {}
        for i, def in ipairs(_window_defs) do
            local compbuf = CompBuffer:new({ filetype = def.buf_type, name = def.label, listed = false })
            local comp = def.comp_class:new()
            comp:link_to_buffer(compbuf:make_controller())
            table.insert(comp_buffers, compbuf)
        end
        return comp_buffers
    end,
    on_hide = function ()
        
    end,
    get_ratio = function()
        return { 0.5, 0.4, 0.1 }
    end
}

function M.get_sideview_def()
    return side_view_def
end

return M
