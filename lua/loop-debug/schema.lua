local schema = {
    type = "object",
    required = { "debugger", "request" },
    additionalProperties = true,

    ["x-order"] = {
        "command",
        "cwd",
        "debugger",
        "request",
        "program",
        "args",
        "host",
        "port",
        "pid",
    },

    properties = {
        ----------------------------------------------------------------------
        -- Core
        ----------------------------------------------------------------------
        debugger = {
            type = "string",
            description = "Debugger type",
        },

        request = {
            type = "string",
            enum = { "launch", "attach" },
            description = "Debug request type",
        },

        command = {
            oneOf = {
                { type = "string" },
                { type = "array", items = { type = "string" } },
            },
            description = "Command to execute",
        },

        cwd = {
            type = "string",
            description = "Working directory",
        },

        program = {
            type = "string",
            description = "Program to debug",
        },

        args = {
            type = "array",
            items = { type = "string" },
            description = "Program arguments",
        },

        ----------------------------------------------------------------------
        -- Execution / lifecycle
        ----------------------------------------------------------------------
        stopOnEntry = {
            type = "boolean",
        },

        runInTerminal = {
            type = "boolean",
        },

        terminateOnDisconnect = {
            type = "boolean",
        },

        restart = {
            type = "boolean",
        },

        justMyCode = {
            type = "boolean",
        },

        ----------------------------------------------------------------------
        -- Attach / remote
        ----------------------------------------------------------------------
        pid = {
            oneOf = {
                { type = "number" },
                { type = "string" },
            },
        },

        processId = {
            oneOf = {
                { type = "number" },
                { type = "string" },
            },
        },

        host = {
            type = "string",
        },

        port = {
            oneOf = {
                { type = "number" },
                { type = "string" },
            },
        },

        address = {
            type = "string",
        },

        remoteRoot = {
            type = "string",
        },

        url = {
            type = "string",
        },

        ----------------------------------------------------------------------
        -- Source maps / paths
        ----------------------------------------------------------------------
        sourceMaps = {
            description = "Debugger-specific source map configuration",
        },

        sourceMap = {
            type = "object",
            additionalProperties = { type = "string" },
        },

        pathMappings = {
            oneOf = {
                { type = "string" },
                { type = "object" },
            },
        },

        sourceLanguages = {
            type = "array",
            items = { type = "string" },
        },

        ----------------------------------------------------------------------
        -- Environment / runtime
        ----------------------------------------------------------------------
        env = {
            type = "object",
            additionalProperties = { type = "string" },
        },

        userDataDir = {
            type = "boolean",
        },

        mode = {
            type = "string",
        },

        ----------------------------------------------------------------------
        -- Debugger commands
        ----------------------------------------------------------------------
        initCommands = {
            type = "array",
            items = { type = "string" },
        },
    },
}

return schema
