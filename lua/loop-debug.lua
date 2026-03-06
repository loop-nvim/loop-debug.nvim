-- lua/loop/init.lua
local M = {}

---@class loop-debug.Config.SignPriority
---@field breakpoints number
---@field currentframe number

---@class loop-debug.Config.Symbols
---@field running string
---@field paused string
---@field success string
---@field failure string
---@field debug_frame string
---@field active_breakpoint string
---@field inactive_breakpoint string
---@field logpoint string
---@field inactive_logpoint string
---@field cond_breakpoint string
---@field inactive_cond_breakpoint string
---@field disabled_breakpoint string
---@field disabled_logpoint string
---@field disabled_cond_breakpoint string

---@class loop-debug.Config
---@field auto_switch_page? boolean
---@field stack_levels_limit? number
---@field anti_flicker_delay? number
---@field debug_line_blend_color? number
---@field enable_inlay_variables? boolean
---@field sign_priority? loop-debug.Config.SignPriority
---@field symbols? loop-debug.Config.Symbols
---@field enable_dap_log boolean?



local function _get_default_config()
    ---@type loop-debug.Config
    return {
        stack_levels_limit = 100,
        auto_switch_page = true,
        debug_line_blend_color = 0xD65A5A,
        anti_flicker_delay = 500,
        enable_inlay_variables = true,
        sign_priority = {
            breakpoints = 80,
            currentframe = 100,
        },
        symbols = {
            running                  = "●",
            paused                   = "⏸",
            success                  = "✓",
            failure                  = "✗",
            debug_frame              = "▶",
            active_breakpoint        = "●",
            inactive_breakpoint      = "○",
            logpoint                 = "◆",
            inactive_logpoint        = "◇",
            cond_breakpoint          = "■",
            inactive_cond_breakpoint = "□",
            disabled_breakpoint      = "ø",
            disabled_logpoint        = "ø",
            disabled_cond_breakpoint = "ø",
        },
    }
end

---@type loop-debug.Config
M.config = _get_default_config()

-----------------------------------------------------------
-- Setup (user config)
-----------------------------------------------------------

---@param opts loop-debug.Config?
function M.setup(opts)
    if vim.fn.has("nvim-0.10") ~= 1 then
        error("loop.nvim requires Neovim >= 0.10")
    end

    M.config = vim.tbl_deep_extend("force", _get_default_config(), opts or {})
end

---@param name string
---@return loopdebug.Config.Debugger?
function M.get_debugger_config(name)
    return require("loop-debug.debuggers").get_debugger_config(name)
end

---@param name string
---@param debugger_config loopdebug.Config.Debugger
function M.register_debugger(name, debugger_config)
    require("loop-debug.debuggers").register_debugger(name, debugger_config)
end

return M
