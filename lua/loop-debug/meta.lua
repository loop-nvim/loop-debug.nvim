--- @meta

assert(false, "should not require() meta file")

---@class loopdebug.AdapterDebugOptions
---@field host string|nil
---@field port number|string|nil
---@field processId number|string|nil
---@field pid number|string|nil
---@field stopOnEntry boolean|nil
---@field runInTerminal boolean|nil
---@
---@class loopdebug.Task : loop.Task
---@field debugger string
---@field request "launch"|"attach"
---@field command string|string[]|nil
---@field cwd string|nil
---@field env table<string, string>|nil
---@field debug_options loopdebug.AdapterDebugOptions|nil -- Arbitrary debugger-specific arguments
---@field terminate_on_disconnect boolean|nil
