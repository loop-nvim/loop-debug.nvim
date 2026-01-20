local schema = {
    __name = "Debug",
    type = "object",
    required = { "debugger", "request" },
    additionalProperties = true,
    __order = { "command", "cwd", "debugger", "request", "host", "port" },
    properties = {
        debugger = {
            type = { "string" },
            description = "debugger type"
        },
        request = {
            type = { "string" },
            description = "task.request must be 'launch' or 'attach'"
        },
    }
}

return schema
