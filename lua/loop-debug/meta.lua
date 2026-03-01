--- @meta

assert(false, "should not require() meta file")

---@class loopdebug.Task : loop.Task
---@field debugger string
---@field request "launch"|"attach"
---@field command string|string[]|nil
---@field cwd string|nil
---@field host string|nil
---@field port number|string|nil
---@field processId number|string|nil
---@field env table<string, string>|nil
---@field stop_on_entry boolean|nil
---@field run_in_terminal boolean|nil
---@field terminate_on_disconnect boolean|nil
---@field debug_options table|nil -- Arbitrary debugger-specific arguments
