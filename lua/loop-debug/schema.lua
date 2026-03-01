local schema = {
    type = "object",
    required = { "debugger", "request" },
    additionalProperties = true,

    ["x-order"] = {
        "command",
        "cwd",
        "debugger",
        "request",
        "host",
        "port",
        "processId",
        "debug_options",
    },

    properties = {
        ----------------------------------------------------------------------
        -- Core
        ----------------------------------------------------------------------
        debugger = {
            type = "string",
            description = "Debugger backend to use (e.g. gdb, lldb, node, python).",
            ["x-valueSelector"] = "loop-debug.tools.dbgselect.select",
        },

        request = {
            type = "string",
            enum = { "launch", "attach" },
            description = "How to start debugging: 'launch' starts a new process, 'attach' connects to an existing one.",
        },

        command = {
            oneOf = {
                { type = "string" },
                { type = "array", items = { type = "string" } },
            },
            description = "Command used to start the debugger or debug adapter.",
        },

        cwd = {
            type = "string",
            description = "Working directory for the debug session.",
        },

        ----------------------------------------------------------------------
        -- Essential Connection Fields
        ----------------------------------------------------------------------
        processId = {
            oneOf = {
                { type = "number" },
                { type = "string" },
            },
            description = "Process ID to attach to.",
        },

        host = {
            type = "string",
            description = "Hostname or IP address of the remote debug target.",
        },

        port = {
            oneOf = {
                { type = "number" },
                { type = "string" },
            },
            description = "Port number of the remote debug target.",
        },
        ----------------------------------------------------------------------
        -- Execution / lifecycle
        ----------------------------------------------------------------------
        stop_on_entry = {
            type = "boolean",
            description = "Pause execution immediately at program start.",
        },

        run_in_terminal = {
            type = "boolean",
            description = "Run the program in a terminal instead of a debugger console.",
        },

        terminate_on_disconnect = {
            type = "boolean",
            description = "Terminate the debugged process when the debugger disconnects.",
        },

        ----------------------------------------------------------------------
        -- Environment / runtime
        ----------------------------------------------------------------------
        env = {
            type = "object",
            additionalProperties = { type = "string" },
            description = "Environment variables passed to the debugged process.",
        },

        ----------------------------------------------------------------------
        -- Debugger-Specific Configuration
        ----------------------------------------------------------------------
        debug_options = {
            type = "object",
            additionalProperties = true,
            description = "Arbitrary key-value pairs passed specifically to the debugger backend.",
        },

    }
}

return schema
