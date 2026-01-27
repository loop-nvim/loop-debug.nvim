local M = {}

local manager = require("loop-debug.manager")
local debugui = require("loop-debug.ui")
local strtools = require("loop.tools.strtools")

local function _debug_commands(args)
    if #args == 0 then
        return {
            -- UI
            "ui",
            -- Breakpoints
            "breakpoint",
            -- Execution control
            "continue",
            "continue_all",
            "pause",
            -- Stepping
            "step_over",
            "step_in",
            "step_out",
            "step_back",
            -- Navigation
            "session",
            "thread",
            "frame",
            -- Inspection
            "inspect",
            -- Termination
            "terminate",
            "terminate_all",
        }
    end
    if #args == 1 and args[1] == "breakpoint" then
        return { "list", "toggle", "logpoint", "conditional",
            "enable", "disable","toggle_enabled", "disable_all", "enable_all",
            "clear_file", "clear_all" }
    end
    return {}
end

--------------------------------------------
-- Dispatcher
-----------------------------------------------------------

---@param args string[]
---@param opts vim.api.keyset.create_user_command.command_args
local function _do_command(args, opts)
    local cmd = args[1]
    if cmd == "ui" then
        debugui.toggle()
        return
    end
    manager.debug_command(cmd, args, opts)
end

---@type loop.UserCommandProvider
return {
    get_subcommands = function(args)
        return _debug_commands(args)
    end,
    dispatch = function(args, opts)
        return _do_command(args, opts)
    end,
}
