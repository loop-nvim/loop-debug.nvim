---@type loop.taskTemplate[]
return {
    -- ==================================================================
    -- Lua
    -- ==================================================================
    {
        name = "lua - run",
        task = {
            name = "Debug",
            type = "debug",
            command = "${file:lua}",
            cwd = "${wsdir}",
            debugger = "lua",
            request = "launch",
        }
    },
    {
        name = "lua - attach",
        task = {
            name = "Debug",
            type = "debug",
            debugger = "lua:remote",
            request = "attach",
            host = "127.0.0.1",
            port = 8086,
        }
    },

    -- ==================================================================
    -- LLDB
    -- ==================================================================
    {
        name = "lldb - run",
        task = {
            name = "Debug",
            type = "debug",
            command = "${prompt:Select binary,./,file}",
            cwd = "${wsdir}",
            debugger = "lldb",
            request = "launch",
            runInTerminal = true,
            stopOnEntry = false,
            initCommands = {},
        }
    },
    {
        name = "lldb - attach",
        task = {
            name = "Debug",
            type = "debug",
            debugger = "lldb",
            request = "attach",
            processId = "${select-pid}",
            initCommands = {},
        }
    },

    -- ==================================================================
    -- GDB
    -- ==================================================================
    {
        name = "gdb - run",
        task = {
            name = "Debug",
            type = "debug",
            command = "${prompt:Select binary,./,file}",
            cwd = "${wsdir}",
            debugger = "gdb",
            request = "launch",
            stopOnEntry = false,
        }
    },
    {
        name = "gdb - attach",
        task = {
            name = "Debug",
            type = "debug",
            debugger = "gdb",
            request = "attach",
            processId = "${select-pid}",
        }
    },

    -- ==================================================================
    -- CodeLLDB
    -- ==================================================================
    {
        name = "codelldb - run",
        task = {
            name = "Debug",
            type = "debug",
            program = "${prompt:Select binary,./,file}",
            cwd = "${wsdir}",
            debugger = "codelldb",
            request = "launch",
            runInTerminal = true,
            stopOnEntry = false,
            sourceLanguages = { "cpp" },
        }
    },
    {
        name = "codelldb - attach",
        task = {
            name = "Debug",
            type = "debug",
            debugger = "codelldb",
            request = "attach",
            processId = "${select-pid}",
        }
    },

    -- ==================================================================
    -- Node.js
    -- ==================================================================
    {
        name = "node - run",
        task = {
            name = "Debug",
            type = "debug",
            command = "${file:javascript}",
            cwd = "${wsdir}",
            debugger = "js-debug",
            request = "launch",
            sourceMaps = true,
            stopOnEntry = false,
        }
    },
    {
        name = "node - attach",
        task = {
            name = "Debug",
            type = "debug",
            debugger = "js-debug",
            request = "attach",
            address = "127.0.0.1",
            port = "${prompt:Inspector port}",
            restart = true,
        }
    },

    -- ==================================================================
    -- Python
    -- ==================================================================
    {
        name = "python - run",
        task = {
            name = "Debug",
            type = "debug",
            command = "${file:python}",
            cwd = "${wsdir}",
            debugger = "debugpy",
            request = "launch",
            justMyCode = false,
        }
    },
    {
        name = "python - attach",
        task = {
            name = "Debug",
            type = "debug",
            debugger = "debugpy:remote",
            request = "attach",
            host = "127.0.0.1",
            port = 0,
            justMyCode = false,
        }
    },

    -- ==================================================================
    -- Go
    -- ==================================================================
    {
        name = "go - run",
        task = {
            name = "Debug",
            type = "debug",
            cwd = "${wsdir}",
            debugger = "go",
            request = "launch",
        }
    },
    {
        name = "go - attach",
        task = {
            name = "Debug",
            type = "debug",
            debugger = "go",
            request = "attach",
            processId = "${select-pid}",
        }
    },

    -- ==================================================================
    -- Chrome
    -- ==================================================================
    {
        name = "chrome - run",
        task = {
            name = "Launch",
            type = "debug",
            debugger = "chrome",
            request = "launch",
            url = "http://localhost:3000",
            webRoot = "${wsdir}",
            userDataDir = false,
            sourceMaps = true,
        }
    },
    {
        name = "chrome - attach",
        task = {
            name = "Debug",
            type = "debug",
            debugger = "chrome",
            request = "attach",
            port = 9222,
            webRoot = "${wsdir}",
        }
    },

    -- ==================================================================
    -- Bash
    -- ==================================================================
    {
        name = "bash - run",
        task = {
            name = "Debug",
            type = "debug",
            command = "${file}",
            cwd = "${wsdir}",
            debugger = "bash",
            request = "launch",
        }
    },

    -- ==================================================================
    -- PHP
    -- ==================================================================
    {
        name = "php - listen",
        task = {
            name = "Listen",
            type = "debug",
            debugger = "php",
            request = "launch",
            port = 9003,
            pathMappings = { ["/var/www/html"] = "${wsdir}" },
        }
    },

    -- ==================================================================
    -- .NET
    -- ==================================================================
    {
        name = "netcoredbg - run",
        task = {
            name = "Debug",
            type = "debug",
            debugger = "netcoredbg",
            request = "launch",
            program = "${prompt:Select binary,./,file}",
        }
    },
    {
        name = "netcoredbg - attach",
        task = {
            name = "Debug",
            type = "debug",
            debugger = "netcoredbg",
            request = "attach",
            processId = "${select-pid}",
        }
    },

    -- ==================================================================
    -- Java
    -- ==================================================================
    {
        name = "java - attach",
        task = {
            name = "Debug",
            type = "debug",
            debugger = "java",
            request = "attach",
            host = "127.0.0.1",
            port = 5005,
        }
    },
}
