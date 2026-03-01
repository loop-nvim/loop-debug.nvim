---@type loop.taskTemplate[]
return {
    {
        name = "Default template",
        task = {
            name = "Debug",
            if_running = "refuse",
            depends_on = {},
            type = "debug",
            command = "",
            debugger = "",
            request = "",
        }
    },
    -- ==================================================================
    -- Lua
    -- ==================================================================
    {
        name = "lua - run",
        task = {
            name = "Debug",
            if_running = "refuse",
            depends_on = {},
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
            if_running = "refuse",
            depends_on = {},
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
            if_running = "refuse",
            depends_on = {},
            type = "debug",
            command = "${prompt:Select binary,./,file}",
            cwd = "${wsdir}",
            debugger = "lldb",
            request = "launch",
            stop_on_entry = false,
            run_in_terminal = true,
            debug_options = {
                initCommands = {},
            },
        }
    },
    {
        name = "lldb - attach",
        task = {
            name = "Debug",
            if_running = "refuse",
            depends_on = {},
            type = "debug",
            debugger = "lldb",
            request = "attach",
            processId = "${select-pid}",
            debug_options = {
                initCommands = {},
            },
        }
    },

    -- ==================================================================
    -- GDB
    -- ==================================================================
    {
        name = "gdb - run",
        task = {
            name = "Debug",
            if_running = "refuse",
            depends_on = {},
            type = "debug",
            command = "${prompt:Select binary,./,file}",
            cwd = "${wsdir}",
            debugger = "gdb",
            request = "launch",
            stop_on_entry = false,
        }
    },
    {
        name = "gdb - attach",
        task = {
            name = "Debug",
            if_running = "refuse",
            depends_on = {},
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
            if_running = "refuse",
            depends_on = {},
            type = "debug",
            command = "${prompt:Select binary,./,file}",
            cwd = "${wsdir}",
            debugger = "codelldb",
            request = "launch",
            stop_on_entry = false,
            run_in_terminal = true,
            debug_options = {
                sourceLanguages = { "cpp" },
            },
        }
    },
    {
        name = "codelldb - attach",
        task = {
            name = "Debug",
            if_running = "refuse",
            depends_on = {},
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
            if_running = "refuse",
            depends_on = {},
            type = "debug",
            command = "${file:javascript}",
            cwd = "${wsdir}",
            debugger = "js-debug",
            request = "launch",
            stop_on_entry = false,
            debug_options = {
                sourceMaps = true,
            },
        }
    },
    {
        name = "node - attach",
        task = {
            name = "Debug",
            if_running = "refuse",
            depends_on = {},
            type = "debug",
            debugger = "js-debug",
            request = "attach",
            port = "${prompt:Inspector port}",
            debug_options = {
                address = "127.0.0.1",
                restart = true,
            },
        }
    },

    -- ==================================================================
    -- Python
    -- ==================================================================
    {
        name = "python - run",
        task = {
            name = "Debug",
            if_running = "refuse",
            depends_on = {},
            type = "debug",
            command = "${file:python}",
            cwd = "${wsdir}",
            debugger = "debugpy",
            request = "launch",
            debug_options = {
                justMyCode = false,
            },
        }
    },
    {
        name = "python - attach",
        task = {
            name = "Debug",
            if_running = "refuse",
            depends_on = {},
            type = "debug",
            debugger = "debugpy:remote",
            request = "attach",
            host = "127.0.0.1",
            port = 0,
            debug_options = {
                justMyCode = false,
            },
        }
    },

    -- ==================================================================
    -- Go
    -- ==================================================================
    {
        name = "go - run",
        task = {
            name = "Debug",
            if_running = "refuse",
            depends_on = {},
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
            if_running = "refuse",
            depends_on = {},
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
            if_running = "refuse",
            depends_on = {},
            type = "debug",
            debugger = "chrome",
            request = "launch",
            debug_options = {
                url = "http://localhost:3000",
                webRoot = "${wsdir}",
                userDataDir = false,
                sourceMaps = true,
            },
        }
    },
    {
        name = "chrome - attach",
        task = {
            name = "Debug",
            if_running = "refuse",
            depends_on = {},
            type = "debug",
            debugger = "chrome",
            request = "attach",
            port = 9222,
            debug_options = {
                webRoot = "${wsdir}",
            },
        }
    },

    -- ==================================================================
    -- Bash
    -- ==================================================================
    {
        name = "bash - run",
        task = {
            name = "Debug",
            if_running = "refuse",
            depends_on = {},
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
            if_running = "refuse",
            depends_on = {},
            type = "debug",
            debugger = "php",
            request = "launch",
            port = 9003,
            debug_options = {
                pathMappings = { ["/var/www/html"] = "${wsdir}" },
            },
        }
    },

    -- ==================================================================
    -- .NET
    -- ==================================================================
    {
        name = "netcoredbg - run",
        task = {
            name = "Debug",
            if_running = "refuse",
            depends_on = {},
            type = "debug",
            command = "${prompt:Select binary,./,file}",
            debugger = "netcoredbg",
            request = "launch",
        }
    },
    {
        name = "netcoredbg - attach",
        task = {
            name = "Debug",
            if_running = "refuse",
            depends_on = {},
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
            if_running = "refuse",
            depends_on = {},
            type = "debug",
            debugger = "java",
            request = "attach",
            host = "127.0.0.1",
            port = 5005,
        }
    },
}