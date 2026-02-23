---@type loop.taskTemplate[]
return {
    -- ==================================================================
    -- Lua
    -- ==================================================================
    {
        name = "Debug current Lua file (local-lua-debugger-vscode)",
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
        name = "Attach to remote Lua process",
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
    -- C / C++ / Rust / Objective-C (lldb-dap)
    -- ==================================================================
    {
        name = "Debug executable with LLDB (launch)",
        task = {

            name = "Debug",
            type = "debug",
            command = "${prompt:Select binary,./,file}",
            cwd = "${wsdir}",
            debugger = "lldb",
            request = "launch",
            runInTerminal = true,
            stopOnEntry = false,
            initCommands = {
            }
        }
    },
    {
        name = "Attach to running process LLDB",
        task = {

            name = "Debug",
            type = "debug",
            debugger = "lldb",
            request = "attach",
            pid = "${select-pid}",
            initCommands = {
            }

        }
    },
    -- ==================================================================
    -- GDB
    -- ==================================================================
    {
        name = "Debug executable with GDB (launch)",
        task = {

            name = "Debug",
            type = "debug",
            command = "${prompt:Select binary,./,file}",
            cwd = "${wsdir}",
            debugger = "gdb",
            request = "launch",
            runInTerminal = true,
            stopOnEntry = false,
            initCommands = {
                "source ~/.gdbinit"
            }
        }
    },
    {
        name = "Attach to running process with GDB",
        task = {

            name = "Debug",
            type = "debug",
            debugger = "gdb",
            request = "attach",
            pid = "${select-pid}",
            initCommands = {
                "source ~/.gdbinit"
            }

        }
    },
    -- ==================================================================
    -- C / C++ / Rust / Objective-C (codelldb)
    -- ==================================================================
    {
        name = "Debug executable with codelldb (launch)",
        task = {

            name = "Debug",
            type = "debug",
            program = "${prompt:Select binary,./,file}",
            cwd = "${wsdir}",
            debugger = "codelldb",
            request = "launch",
            runInTerminal = true,
            stopOnEntry = false,
            -- Enable nicer C++/Rust formatting
            sourceLanguages = { "cpp" },
        }
    },
    {
        name = "Attach to running process with CodeLLDB",
        task = {

            name = "Debug",
            type = "debug",
            debugger = "codelldb",
            request = "attach",
            pid = "${select-pid}",
            -- codelldb often requires the program path even for attaching
            -- to resolve symbols correctly
            --program = "${prompt:Select binary,./,file}",
        }
    },
    -- ==================================================================
    -- Node.js / JavaScript / TypeScript
    -- ==================================================================
    {
        name = "Debug Node.js script (js-debug)",
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
        name = "Attach to Node.js process (js-debug)",
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
        name = "Debug Python script (debugpy)",
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
        name = "Attach to Python debug server (debugpy)",
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
        name = "Debug Go program (delve)",
        task = {

            name = "Debug Go program (delve)",
            type = "debug",
            cwd = "${wsdir}",
            debugger = "go",
            request = "launch",
            mode = "debug",
        }
    },
    {
        name = "Attach to Go process (delve)",
        task = {

            name = "Debug",
            type = "debug",
            debugger = "go",
            request = "attach",
            mode = "local",
            processId = "${select-pid}",
        }
    },
    -- ==================================================================
    -- Chrome / Web
    -- ==================================================================
    {
        name = "Launch Chrome and debug",
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
        name = "Attach to running Chrome",
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
        name = "Debug Bash script (bashdb)",
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
    -- PHP (Xdebug)
    -- ==================================================================
    {
        name = "Listen for Xdebug (PHP)",
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
    -- C# / .NET
    -- ==================================================================
    {
        name = "Debug .NET DLL (netcoredbg)",
        task = {

            name = "Debug",
            type = "debug",
            debugger = "netcoredbg",
            request = "launch",
            program = "${prompt:Select binary,./,file}",
        }
    },
    {
        name = "Attach to .NET process",
        task = {

            name = "Debug",
            type = "debug",
            debugger = "netcoredbg",
            request = "attach",
            processId = "${select-pid}",
        }
    },
    -- ==================================================================
    -- Java (jdtls)
    -- ==================================================================
    {
        name = "Attach to Java process (JDWP)",
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
