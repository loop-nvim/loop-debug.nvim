local M = {}

require('loop-debug.tools.FSM')

---@enum
M.trigger =
{
    intialize_err = "intialize_err",
    intialize_ok = "intialize_ok",
    startup_ok = "startup_ok",
    startup_err = "startup_err",
    disconnect = "disconnect",
    disconnect_ok = "disconnect_ok",
    disconnect_err = "disconnect_err",
    disconnect_timeout = "disconnect_timeout",
}

---@alias loopdebug.fsmdata.StateHandler fun(trigger:string, triggerdata:any)

---@class loopdebug.fsmdata.StateHandlers
---@field initializing loopdebug.fsmdata.StateHandler
---@field starting loopdebug.fsmdata.StateHandler
---@field running loopdebug.fsmdata.StateHandler
---@field disconnecting loopdebug.fsmdata.StateHandler
---@field ended loopdebug.fsmdata.StateHandler

---@param handlers loopdebug.fsmdata.StateHandlers
---@return loop.tools.FSMData
function M.create_fsm_data(handlers)
    ---@type loop.tools.FSMData
    return {
        initial = "initializing",
        states = {
            initializing = {
                state_handler = handlers.initializing,
                triggers = {
                    [M.trigger.intialize_ok] = "starting",
                    [M.trigger.intialize_err] = "disconnecting",
                    [M.trigger.disconnect] = 'disconnecting',
                }
            },
            starting = {
                state_handler = handlers.starting,
                triggers = {
                    [M.trigger.disconnect] = "disconnecting",
                    [M.trigger.startup_ok] = "running",
                    [M.trigger.startup_err] = "disconnecting",
                }
            },
            running = {
                state_handler = handlers.running,
                triggers = {
                    [M.trigger.disconnect] = "disconnecting",
                }
            },
            disconnecting = {
                state_handler = handlers.disconnecting,
                triggers = {
                    [M.trigger.disconnect_ok] = "ended",
                    [M.trigger.disconnect_err] = "ended",
                    [M.trigger.disconnect_timeout] = "ended",
                }
            },
            ended = {
                state_handler = handlers.ended,
                triggers = {}
            },
        }
    }
end

return M
