-- lua/loop/init.lua
local M = {}

-- Dependencies
local config = require("loop-debug.config")

-----------------------------------------------------------
-- Defaults
-----------------------------------------------------------

---@type loop-debug.Config
local DEFAULT_CONFIG = {
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

-----------------------------------------------------------
-- State
-----------------------------------------------------------

local setup_done = false
local initialized = false

-----------------------------------------------------------
-- Setup (user config only)
-----------------------------------------------------------

---@param opts loop-debug.Config?
function M.setup(opts)
    if vim.fn.has("nvim-0.10") ~= 1 then
        error("loop.nvim requires Neovim >= 0.10")
    end

    config.current = vim.tbl_deep_extend("force", DEFAULT_CONFIG, opts or {})
    setup_done = true

    M.init()
end

-----------------------------------------------------------
-- Initialization (runs once)
-----------------------------------------------------------

function M.init()
    if initialized then
        return
    end
    initialized = true

    -- Apply defaults if setup() was never called
    if not setup_done then
        config.current = DEFAULT_CONFIG
    end

    require('loop-debug.breakpoints').init()
    require('loop-debug.curframe').init()
    require('loop-debug.inlinevars').init()
    require('loop-debug.ui').init()
end

---@param name string
---@return loopdebug.Config.Debugger?
function M.get_debugger_config(name)
    require("loop-debug.debuggers").get_debugger_config(name)
end

---@param name string
---@param debugger_config loopdebug.Config.Debugger
function M.register_debugger(name, debugger_config)
    require("loop-debug.debuggers").register_debugger(name, debugger_config)
end

return M
