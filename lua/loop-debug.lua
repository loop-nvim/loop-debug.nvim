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
    sign_priority = {
        breakpoints = 80,
        currentframe = 100,
    },
    symbols = {
        running                  = "▶",
        paused                   = "■",
        success                  = "✓",
        failure                  = "✗",
        active_breakpoint        = "●",
        inactive_breakpoint      = "○",
        logpoint                 = "◆",
        inactive_logpoint        = "◇",
        cond_breakpoint          = "■",
        inactive_cond_breakpoint = "□",
        disabled_breakpoint      = "⊘",
        disabled_logpoint        = "⊗",
        disabled_cond_breakpoint = "⊟",

    },
    debuggers = require("loop-debug.debuggers")
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
    require('loop-debug.breakpointsmonitor').init()
    require('loop-debug.curframe_sign').init()
    require('loop-debug.ui').init()
end

return M
