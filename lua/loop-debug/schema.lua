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
            description =
            "Command used to start the debugger or debug adapter. Can be a string or a list of command parts.",
        },

        cwd = {
            type = "string",
            description = "Working directory for the debug session.",
        },

        ----------------------------------------------------------------------
        -- Execution / lifecycle
        ----------------------------------------------------------------------
        stopOnEntry = {
            type = "boolean",
            description = "Pause execution immediately at program start.",
        },

        runInTerminal = {
            type = "boolean",
            description = "Run the program in a terminal instead of a debugger console.",
        },

        terminateOnDisconnect = {
            type = "boolean",
            description = "Terminate the debugged process when the debugger disconnects.",
        },

        restart = {
            type = "boolean",
            description = "Automatically restart the debug session when it ends.",
        },

        justMyCode = {
            type = "boolean",
            description = "Step through user code only, skipping library or system code when supported.",
        },

        ----------------------------------------------------------------------
        -- Attach / remote
        ----------------------------------------------------------------------
        processId = {
            oneOf = {
                { type = "number" },
                { type = "string" },
            },
            description = "Process ID to attach to. Can be a numeric PID or a macro that resolves to one.",
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
            description =
            "Port number of the remote debug target. Can be a numeric value or a macro that resolves to one.",
        },

        address = {
            type = "string",
            description = "Full address of the remote debug target (e.g. host:port).",
        },

        remoteRoot = {
            type = "string",
            description = "Root directory of the project on the remote system.",
        },

        url = {
            type = "string",
            description = "URL of the debug target (commonly used for browser or web debugging).",
        },

        ----------------------------------------------------------------------
        -- Source maps / paths
        ----------------------------------------------------------------------
        sourceMaps = {
            description =
            "Debugger-specific source map configuration. Enables mapping generated code back to original sources.",
        },

        sourceMap = {
            type = "object",
            additionalProperties = { type = "string" },
            description = "Mapping of local paths to remote or generated source paths.",
        },

        pathMappings = {
            oneOf = {
                { type = "string" },
                { type = "object" },
            },
            description = "Path mapping configuration used to translate file paths between environments.",
        },

        sourceLanguages = {
            type = "array",
            items = { type = "string" },
            description = "List of source languages involved in the debug session (e.g. javascript, typescript).",
        },

        ----------------------------------------------------------------------
        -- Environment / runtime
        ----------------------------------------------------------------------
        env = {
            type = "object",
            additionalProperties = { type = "string" },
            description = "Environment variables passed to the debugged process.",
        },

        webRoot = {
            type = "string",
            description = "Local project root that corresponds to the web server root (used for source map resolution)."
        },

        userDataDir = {
            type = "boolean",
            description = "Use a temporary user data directory for the debug session (commonly for browser debugging).",
        },

        ----------------------------------------------------------------------
        -- Debugger commands
        ----------------------------------------------------------------------
        initCommands = {
            type = "array",
            items = { type = "string" },
            description =
            "Debugger commands executed before the debug session starts (e.g. setting breakpoints or options).",
        },
    }
}

return schema
