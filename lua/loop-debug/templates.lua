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
            debugger = "",           -- ← empty = user chooses
            request = "",
        }
    },

    -- ==================================================================
    -- Lua
    -- ==================================================================
    {
        name = "lua - run (local-lua-debugger)",
        task = {
            name = "Debug Lua",
            if_running = "refuse",
            depends_on = {},
            type = "debug",
            command = "${file:lua}",
            cwd = "${wsdir}",
            debugger = "local-lua-debugger",
            request = "launch",
        }
    },
    {
        name = "lua - attach (osv / remote)",
        task = {
            name = "Attach to Lua (remote)",
            if_running = "refuse",
            depends_on = {},
            type = "debug",
            debugger = "osv",
            request = "attach",
            debug_options = {
                host = "127.0.0.1",
                port = 8086,
            },
        }
    },

    -- ==================================================================
    -- C/C++/Rust – LLDB
    -- ==================================================================
    {
        name = "lldb - run",
        task = {
            name = "Debug (LLDB)",
            if_running = "refuse",
            depends_on = {},
            type = "debug",
            command = "${prompt:Select binary,./,file}",
            cwd = "${wsdir}",
            debugger = "lldb",
            request = "launch",
            debug_options = {
                stopOnEntry = false,
                runInTerminal = true,
            },
        }
    },
    {
        name = "lldb - attach",
        task = {
            name = "Attach (LLDB)",
            if_running = "refuse",
            depends_on = {},
            type = "debug",
            debugger = "lldb",
            request = "attach",
            debug_options = {
                pid = "${select-pid}",
            },
        }
    },

    -- ==================================================================
    -- C/C++/Rust – GDB
    -- ==================================================================
    {
        name = "gdb - run",
        task = {
            name = "Debug (GDB)",
            if_running = "refuse",
            depends_on = {},
            type = "debug",
            command = "${prompt:Select binary,./,file}",
            cwd = "${wsdir}",
            debugger = "gdb",
            request = "launch",
            debug_options = {
                stopOnEntry = false,
                runInTerminal = true,
            },
        }
    },
    {
        name = "gdb - attach",
        task = {
            name = "Attach (GDB)",
            if_running = "refuse",
            depends_on = {},
            type = "debug",
            debugger = "gdb",
            request = "attach",
            debug_options = {
                processId = "${select-pid}",
            },
        }
    },

    -- ==================================================================
    -- C/C++/Rust – CodeLLDB
    -- ==================================================================
    {
        name = "codelldb - run",
        task = {
            name = "Debug (CodeLLDB)",
            if_running = "refuse",
            depends_on = {},
            type = "debug",
            command = "${prompt:Select binary,./,file}",
            cwd = "${wsdir}",
            debugger = "codelldb",
            request = "launch",
            debug_options = {
                stopOnEntry = false,
                runInTerminal = true,
                sourceLanguages = { "cpp" },
            },
        }
    },
    {
        name = "codelldb - attach",
        task = {
            name = "Attach (CodeLLDB)",
            if_running = "refuse",
            depends_on = {},
            type = "debug",
            debugger = "codelldb",
            request = "attach",
            debug_options = {
                pid = "${select-pid}",
            },
        }
    },

    -- ==================================================================
    -- JavaScript / TypeScript / Node.js
    -- ==================================================================
    {
        name = "node - run",
        task = {
            name = "Debug Node.js",
            if_running = "refuse",
            depends_on = {},
            type = "debug",
            command = "${file:javascript}",
            cwd = "${wsdir}",
            debugger = "js-debug",
            request = "launch",
            debug_options = {
                stopOnEntry = false,
                sourceMaps = true,
            },
        }
    },
    {
        name = "node - attach",
        task = {
            name = "Attach to Node.js",
            if_running = "refuse",
            depends_on = {},
            type = "debug",
            debugger = "js-debug",
            request = "attach",
            debug_options = {
                port = "${prompt:Inspector port,9229}",
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
            name = "Debug Python",
            if_running = "refuse",
            depends_on = {},
            type = "debug",
            command = "${file:python}",
            cwd = "${wsdir}",
            debugger = "debugpy",
            request = "launch",
            debug_options = {
                justMyCode = false,
                console = "integratedTerminal",
            },
        }
    },
    {
        name = "python - attach (remote)",
        task = {
            name = "Attach Python (remote)",
            if_running = "refuse",
            depends_on = {},
            type = "debug",
            debugger = "debugpy:remote",
            request = "attach",
            debug_options = {
                host = "127.0.0.1",
                port = "${prompt:debugpy port,5678}",
                justMyCode = false,
            },
        }
    },

    -- ==================================================================
    -- Go (delve)
    -- ==================================================================
    {
        name = "go - run",
        task = {
            name = "Debug Go",
            if_running = "refuse",
            depends_on = {},
            type = "debug",
            cwd = "${wsdir}",
            debugger = "delve",
            request = "launch",
            debug_options = {
                mode = "debug",
                -- program = can be set automatically from cwd or you can add it
            },
        }
    },
    {
        name = "go - attach",
        task = {
            name = "Attach Go",
            if_running = "refuse",
            depends_on = {},
            type = "debug",
            debugger = "delve",
            request = "attach",
            debug_options = {
                processId = "${select-pid}",
            },
        }
    },

    -- ==================================================================
    -- Bash
    -- ==================================================================
    {
        name = "bash - run",
        task = {
            name = "Debug Bash",
            if_running = "refuse",
            depends_on = {},
            type = "debug",
            command = "${file}",
            cwd = "${wsdir}",
            debugger = "bash-debug-adapter",
            request = "launch",
        }
    },

    -- ==================================================================
    -- PHP (Xdebug)
    -- ==================================================================
    {
        name = "php - listen (xdebug)",
        task = {
            name = "Listen for Xdebug",
            if_running = "refuse",
            depends_on = {},
            type = "debug",
            debugger = "php-debug-adapter",
            request = "launch",
            debug_options = {
                port = 9003,
                pathMappings = {
                    ["/var/www/html"] = "${wsdir}",
                },
            },
        }
    },

    -- ==================================================================
    -- .NET (netcoredbg)
    -- ==================================================================
    {
        name = "netcoredbg - run",
        task = {
            name = "Debug .NET",
            if_running = "refuse",
            depends_on = {},
            type = "debug",
            command = "${prompt:Select binary,./,file}",
            cwd = "${wsdir}",
            debugger = "netcoredbg",
            request = "launch",
        }
    },
    {
        name = "netcoredbg - attach",
        task = {
            name = "Attach .NET",
            if_running = "refuse",
            depends_on = {},
            type = "debug",
            debugger = "netcoredbg",
            request = "attach",
            debug_options = {
                processId = "${select-pid}",
            },
        }
    },

    -- ==================================================================
    -- Java
    -- ==================================================================
    {
        name = "java - attach",
        task = {
            name = "Attach Java (JDWP)",
            if_running = "refuse",
            depends_on = {},
            type = "debug",
            debugger = "java-debug-server",
            request = "attach",
            debug_options = {
                host = "127.0.0.1",
                port = 5005,
            },
        }
    },
}