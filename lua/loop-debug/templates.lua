---@type loopdebug.taskTemplate[]
return {
    -- ==================================================================
    -- Default
    -- ==================================================================
    {
        name = "Debug (Default)",
        task = {
            name = "Debug",
            if_running = "refuse",
            depends_on = {},
            type = "debug",
            command = "",
            debugger = "",
            request = "launch",
            debug_options = vim.empty_dict(),
        }
    },

    -- ==================================================================
    -- Lua
    -- ==================================================================
    {
        name = "Debug Lua (local debugger)",
        task = {
            name = "Debug Lua",
            if_running = "refuse",
            depends_on = {},
            type = "debug",
            command = "${file:lua}",
            cwd = "${wsdir}",
            debugger = "local-lua-debugger",
            request = "launch",
            debug_options = vim.empty_dict(),

        }
    },
    {
        name = "OSV Attach Process",
        task = {
            name = "Attach Process (OSV)",
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
        name = "LLDB Debug",
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
        name = "LLDB Attach Process",
        task = {
            name = "Attach Process (LLDB)",
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
        name = "GDB Debug",
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
        name = "GDB Attach Process",
        task = {
            name = "Attach Process (GDB)",
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
        name = "CodeLLDB Debug",
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
        name = "CodeLLDB Attach Process",
        task = {
            name = "Attach Process (CodeLLDB)",
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
    -- Node.js / JavaScript / TypeScript
    -- ==================================================================
    {
        name = "Node.js Debug",
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
        name = "js-debug Attach Process",
        task = {
            name = "Attach Process (js-debug)",
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
        name = "Python Debug",
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
        name = "Python Attach Process (debugpy)",
        task = {
            name = "Attach Process (debugpy)",
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
    -- Go (Delve)
    -- ==================================================================
    {
        name = "Go Debug (Delve)",
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
            },
        }
    },
    {
        name = "Delve Attach Process",
        task = {
            name = "Attach Process (Delve)",
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
        name = "Bash Debug",
        task = {
            name = "Debug Bash",
            if_running = "refuse",
            depends_on = {},
            type = "debug",
            command = "${file}",
            cwd = "${wsdir}",
            debugger = "bash-debug-adapter",
            request = "launch",
            debug_options = vim.empty_dict(),
        }
    },

    -- ==================================================================
    -- PHP (Xdebug)
    -- ==================================================================
    {
        name = "Xdebug Listen",
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
    -- .NET (NetCoreDbg)
    -- ==================================================================
    {
        name = "NetCoreDbg Debug",
        task = {
            name = "Debug .NET",
            if_running = "refuse",
            depends_on = {},
            type = "debug",
            command = "${prompt:Select binary,./,file}",
            cwd = "${wsdir}",
            debugger = "netcoredbg",
            request = "launch",
            debug_options = vim.empty_dict(),
        }
    },
    {
        name = "NetCoreDbg Attach Process",
        task = {
            name = "Attach Process (NetCoreDbg)",
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
        name = "JDWP Attach Process",
        task = {
            name = "Attach Process (JDWP)",
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
