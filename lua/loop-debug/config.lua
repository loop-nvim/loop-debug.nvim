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

local M = {}

---@type loop-debug.Config|nil
M.current = nil

return M
