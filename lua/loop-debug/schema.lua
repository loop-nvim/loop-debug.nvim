local schema = {
    type = "object",
    required = { "debugger", "request" },
    additionalProperties = true,

    ["x-order"] = {
        "command",
        "cwd",
        "debugger",
        "request",
        "terminate_on_disconnect",
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
            description = "Working directory for the debug session. Defaults to `${wsdir}` if not specified",
        },

        ----------------------------------------------------------------------
        -- Execution / lifecycle (top-level)
        ----------------------------------------------------------------------
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

            properties = {
                ------------------------------------------------------------------
                -- Connection
                ------------------------------------------------------------------
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
                ------------------------------------------------------------------
                -- DAP Execution Flags
                ------------------------------------------------------------------
                stopOnEntry = {
                    type = "boolean",
                    description = "Pause execution immediately at program start.",
                },

                runInTerminal = {
                    type = "boolean",
                    description = "Run the program in a terminal (when supported).",
                },
            },
        },
    }
}

return schema