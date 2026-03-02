local M = {}

local strtools = require('loop.tools.strtools')
local config = require("loop-debug.config")

---@class loopdebug.TaskContext
---@field task loopdebug.Task
---@field ws_dir string

---@class loopdebug.Config.Debugger.HookContext
---@field task loopdebug.Task
---@field ws_dir string
---@field adapter_config loopdebug.AdapterConfig
---@field page_group any
---@field exit_code number|nil
---@field user_data table

---@class loopdebug.Config.Debugger
---@field language string
---@field adapter_config loopdebug.AdapterConfig|(fun(ctx:loopdebug.TaskContext):loopdebug.AdapterConfig?,string?)
---@field launch_args nil|table|fun(ctx:loopdebug.TaskContext):table
---@field attach_args nil|table|fun(ctx:loopdebug.TaskContext):table
---@field early_attach boolean?
---@field start_hook nil|fun(ctx:loopdebug.Config.Debugger.HookContext,cb:fun(ok:boolean,err:string|nil))
---@field end_hook nil|fun(ctx:loopdebug.Config.Debugger.HookContext,cb:fun())
---@field args_postprocess (fun(args:table,request:"launch"|"attach"):boolean,string?)?

--------------------------------------------------------------------------------
-- Internal Helpers
--------------------------------------------------------------------------------

---@param task loopdebug.Task
---@return string|nil
local function get_task_program(task)
    local cmdparts = strtools.cmd_to_string_array(task.command or "")
    return cmdparts[1]
end

---@param task loopdebug.Task
---@return string[]
local function get_task_args(task)
    local cmdparts = strtools.cmd_to_string_array(task.command or "")
    return { unpack(cmdparts, 2) }
end

---@param to_merge table<string, string>?
---@return table<string, string>
local function _merge_env(to_merge)
    local env = {}
    for k, v in pairs(vim.fn.environ() or {}) do
        env[k] = v
    end
    if type(to_merge) == "table" then
        for k, v in pairs(to_merge) do
            env[k] = v
        end
    end
    return env
end

---@param context loopdebug.TaskContext
---@return string
local function _get_task_cwd(context)
    local task = context.task
    return (task and task.cwd) or context.ws_dir
end

---@param name string
---@return string
local function mason_bin(name)
    local ok, mason_registry = pcall(require, "mason-registry")
    if not ok then return name end

    local pkg_ok, pkg = pcall(mason_registry.get_package, name)
    if not (pkg_ok and pkg:is_installed()) then
        return name
    end
    local path = pkg.spec.install_path
    if not path then return name end
    local bin_path = vim.fs.joinpath(path, "bin", name)
    if vim.fn.has("win32") == 1 then
        bin_path = bin_path .. ".exe"
    end
    ---@diagnostic disable-next-line: undefined-field
    if vim.uv.fs_stat(bin_path) then
        return bin_path
    end
    return name
end

--------------------------------------------------------------------------------
-- Debugger Definitions
--------------------------------------------------------------------------------

---@type table<string,loopdebug.Config.Debugger>
local _debuggers = {}

---@type table<string,loopdebug.Config.Debugger>
local _user_debuggers = {}
-- ==================================================================
-- lua
-- ==================================================================
_debuggers["local-lua-debugger"] = {
    language = "lua",
    adapter_config = function(context)
        local adapter_path = vim.fs.joinpath(vim.fn.stdpath("data"), "mason", "packages", "local-lua-debugger-vscode",
            "extension", "extension", "debugAdapter.js")
        ---@diagnostic disable-next-line: undefined-field
        if not vim.uv.fs_stat(adapter_path) then
            return nil, ("local-lua-debugger-vscode debug adapter not found (%s)"):format(adapter_path)
        end
        return {
            adapter_id = "local-lua-debugger-vscode",
            name = "Local Lua Debugger",
            type = "executable",
            command = { "node", adapter_path },
            cwd = _get_task_cwd(context),
            env = _merge_env({
                LUA_PATH = vim.fs.joinpath(vim.fn.stdpath("data"), "mason", "packages", "local-lua-debugger-vscode",
                    "extension", "debugger", "?.lua") .. ";;"
            }),
        }
    end,
    launch_args = function(context)
        return {
            type = "lua-local",
            request = "launch",
            name = "Debug",
            cwd = _get_task_cwd(context),
            program = {
                lua = vim.fn.exepath("lua"),
                file = get_task_program(context.task),
                communication = 'stdio',
            },
        }
    end,
}

_debuggers["osv"] = {
    language = "lua",

    adapter_config = function(context)
        local dbg = context.task.debug_options or {}
        return {
            adapter_id = "lua-remote-debugger",
            name = "Lua Remote Debugger",
            type = "server",
            host = dbg.host or "127.0.0.1",
            port = dbg.port and tonumber(dbg.port),
        }
    end,

    attach_args = function(context)
        return {
            request = "attach",
            type = "lua",
            host = "127.0.0.1",
            cwd = _get_task_cwd(context),
        }
    end,
    args_postprocess = function(args, request)
        if request == "launch" then return true end
        args.port = args.port and tonumber(args.port) or nil
        return true
    end
}

-- ==================================================================
-- c, cpp, rust (lldb)
-- ==================================================================
_debuggers.lldb = {
    language = "c, cpp, rust",
    adapter_config = function(context)
        return {
            adapter_id = "lldb-dap",
            name = "LLDB (via lldb-dap)",
            type = "executable",
            command = { mason_bin("lldb-dap") },
            cwd = _get_task_cwd(context),
        }
    end,
    launch_args = function(context)
        local task = context.task
        return {
            program = get_task_program(task),
            args = get_task_args(task),
            cwd = _get_task_cwd(context),
            env = _merge_env(task.env),
            runInTerminal = true,
        }
    end,
    attach_args = function(context)
        local dbg = context.task.debug_options or {}
        return {
            program = type(context.task.command) == "string" and context.task.command or nil,
        }
    end,
    args_postprocess = function(args, request)
        if request == "launch" then return true end
        args.port = args.port and tonumber(args.port) or nil
        return true
    end

}

-- ==================================================================
-- c, cpp, rust (codelldb)
-- ==================================================================
_debuggers.codelldb = {
    language = "c, cpp, rust",
    adapter_config = function(context)
        return {
            adapter_id = "codelldb",
            name = "codelldb",
            type = "executable",
            command = { mason_bin("codelldb") },
            cwd = _get_task_cwd(context),
        }
    end,
    launch_args = function(context)
        local task = context.task
        return {
            name = "Launch (codelldb)",
            type = "codelldb",
            request = "launch",
            program = get_task_program(task),
            args = get_task_args(task),
            cwd = _get_task_cwd(context),
            env = _merge_env(task.env),
            runInTerminal = true,
        }
    end,
    attach_args = function(context)
        local dbg = context.task.debug_options or {}
        return {
            name = "Attach (codelldb)",
            type = "codelldb",
            request = "attach",
            pid = "${select-pid}",
        }
    end,
    args_postprocess = function(args, request)
        if request == "launch" then return true end
        args.pid = args.pid and tonumber(args.pid) or nil
        return true
    end
}

-- ==================================================================
-- c, cpp, rust (gdb)
-- ==================================================================
---@type loopdebug.Config.Debugger
_debuggers.gdb = {
    language = "c, cpp, rust",
    early_attach = true,
    adapter_config = function(context)
        local home = os.getenv("HOME") or "~"
        local gdbinit_path = vim.fs.joinpath(home, ".gdbinit")
        local command = { "gdb", "--interpreter=dap" }
        ---@diagnostic disable-next-line: undefined-field
        if vim.uv.fs_stat(gdbinit_path) then
            table.insert(command, "-ix")
            table.insert(command, gdbinit_path)
        end
        return {
            adapter_id = "gdb",
            name = "GDB (via DAP)",
            type = "executable",
            command = command,
            cwd = _get_task_cwd(context),
        }
    end,
    launch_args = function(context)
        local task = context.task
        return {
            program = get_task_program(task),
            args = get_task_args(task),
            cwd = _get_task_cwd(context),
            env = _merge_env(task.env),
            runInTerminal = true,
        }
    end,
    attach_args = function(context)
        local dbg = context.task.debug_options or {}
        return {
            request = "attach",
            cwd = _get_task_cwd(context),
            pid = "${select-pid}",
        }
    end,
    args_postprocess = function(args, request)
        if request == "launch" then return true end
        args.pid = args.pid and tonumber(args.pid) or nil
        return true
    end
}

-- ==================================================================
-- javascript, typescript
-- ==================================================================
_debuggers["js-debug"] = {
    language = "javascript, typescript",
    start_hook = function(context, callback)
        local task = context.task
        local dbg = task.debug_options or {}
        local port = (type(dbg.port) == "number" and dbg.port) or 0
        context.user_data.exit_handler = function(_)
            callback(false, "debug server stopped unexpectedly")
        end
        context.user_data.output_handler = function(_, data)
            if data then
                for _, line in ipairs(data) do
                    local srv_port = line:match("Debug server listening at.*:(%d+)%s*$")
                    if srv_port then
                        context.adapter_config.port = tonumber(srv_port)
                        callback(true)
                        context.user_data.output_handler = nil
                        break
                    end
                end
            end
        end
        local args = {
            name = "dapDebugServer.js",
            command = {
                "node",
                vim.fs.joinpath(vim.fn.stdpath("data"), "mason", "packages", "js-debug-adapter", "js-debug", "src",
                    "dapDebugServer.js"),
                tostring(port),
            },
            cwd = context.ws_dir,
            output_handler = function(stream, data)
                if context.user_data.output_handler then
                    context.user_data.output_handler(stream, data)
                end
            end,
            on_exit_handler = function(code)
                if context.user_data.exit_handler then
                    context.user_data.exit_handler(code)
                end
            end
        }
        local page_data, page_err = context.page_group.add_page({
            type = "term",
            label = "Debug Server",
            term_args = args,
            activate = config.current.auto_switch_page,
        })
        if not page_data then
            callback(false, page_err)
            return
        end
        context.user_data.proc = page_data and page_data.term_proc or nil
    end,

    end_hook = function(context, callback)
        local proc = context.user_data.proc
        if proc and proc:is_running() then
            context.user_data.exit_handler = function() callback() end
            proc:terminate()
        else
            callback()
        end
    end,

    adapter_config = function(context)
        local dbg = context.task.debug_options or {}
        return {
            adapter_id = "js-debug-adapter",
            name = "js-debug",
            type = "server",
            host = dbg.host or "::1",
            port = tonumber(dbg.port) or 0,
            cwd = _get_task_cwd(context),
        }
    end,

    launch_args = function(context)
        local task = context.task
        return {
            type = "pwa-node",
            request = "launch",
            runtimeExecutable = "node",
            program = get_task_program(task),
            args = get_task_args(task),
            cwd = _get_task_cwd(context),
            env = _merge_env(task.env),
        }
    end,

    attach_args = function(context)
        local task = context.task
        local dbg = task.debug_options or {}
        return {
            type = "pwa-node",
            request = "attach",
            cwd = _get_task_cwd(context),
        }
    end,
    args_postprocess = function(args, request)
        if request == "launch" then return true end
        args.port = args.port and tonumber(args.port) or nil
        return true
    end
}

-- ==================================================================
-- python
-- ==================================================================
_debuggers.debugpy = {
    language = "python",
    adapter_config = function(context)
        local function python_bin()
            local mason_path = vim.fs.joinpath(vim.fn.stdpath("data"), "mason", "packages", "debugpy", "venv", "bin",
                "python")
            if vim.fn.has("win32") == 1 then
                mason_path = vim.fs.joinpath(vim.fn.stdpath("data"), "mason", "packages", "debugpy", "venv", "Scripts",
                    "python.exe")
            end
            ---@diagnostic disable-next-line: undefined-field
            if vim.uv.fs_stat(mason_path) then return mason_path end
            local sys_py = vim.fn.exepath("python3")
            return sys_py ~= "" and sys_py or "python"
        end

        return {
            adapter_id = "debugpy",
            name = "debugpy",
            type = "executable",
            command = { python_bin(), "-m", "debugpy.adapter" },
            cwd = _get_task_cwd(context),
        }
    end,
    launch_args = function(context)
        local task = context.task
        return {
            program = get_task_program(task),
            args = get_task_args(task),
            cwd = _get_task_cwd(context),
            env = _merge_env(task.env),
            console = "integratedTerminal",
        }
    end,
}

_debuggers["debugpy:remote"] = {
    language = "python",
    adapter_config = function(context)
        local dbg = context.task.debug_options or {}
        return {
            adapter_id = "debugpy",
            name = "debugpy",
            type = "server",
            host = dbg.host or "127.0.0.1",
            port = tonumber(dbg.port),
        }
    end,
    attach_args = function(context)
        local dbg = context.task.debug_options or {}
        return {
            request = "attach",
            connect = {
                host = dbg.host or "127.0.0.1",
            }
        }
    end,
    args_postprocess = function(args, request)
        if request == "launch" then return true end
        args.port = args.port and tonumber(args.port) or nil
        return true
    end
}

-- ==================================================================
-- go
-- ==================================================================
_debuggers["delve"] = {
    language = "go",
    adapter_config = function(context)
        return {
            adapter_id = "delve",
            name = "Delve (dlv)",
            type = "executable",
            command = { mason_bin("delve"), "dap", "-l", "127.0.0.1:0" },
            cwd = _get_task_cwd(context),
        }
    end,
    launch_args = function(context)
        local task = context.task
        return {
            mode = "debug",
            program = task.cwd or _get_task_cwd(context),
            env = _merge_env(task.env),
            dlvToolPath = mason_bin("delve"),
        }
    end,
    attach_args = function(context)
        local dbg = context.task.debug_options or {}
        return {
            mode = "local",
            processId = "${select-pid}",
        }
    end,
    args_postprocess = function(args, request)
        if request == "launch" then return true end
        args.processId = args.processId and tonumber(args.processId) or nil
        return true
    end

}

-- ==================================================================
-- bash
-- ==================================================================
_debuggers["bash-debug-adapter"] = {
    language = "bash",
    adapter_config = function(context)
        return {
            adapter_id = "bash-debug-adapter",
            name = "bashdb",
            type = "executable",
            command = { mason_bin("bash-debug-adapter") },
            cwd = _get_task_cwd(context),
        }
    end,
    launch_args = function(context)
        local task = context.task
        local mason_opt_path = vim.fs.joinpath(vim.fn.stdpath("data"), "mason", "opt", "bashdb")
        local bashdb_exe = vim.fs.joinpath(mason_opt_path, "bashdb")
        local bashdb_lib = vim.fs.joinpath(mason_opt_path)
        local final_args = get_task_args(task) or {}
        local path_to_bashdb = "bashdb"
        ---@diagnostic disable-next-line: undefined-field
        if vim.uv.fs_stat(bashdb_exe) then
            path_to_bashdb = bashdb_exe
        end
        return {
            name = "Launch Bash Script",
            type = "bashdb",
            request = "launch",
            program = get_task_program(task),
            args = final_args,
            cwd = _get_task_cwd(context),
            pathBash = "bash",
            pathBashdb = path_to_bashdb,
            pathBashdbLib = bashdb_lib,
            pathCat = "cat",
            pathMkfifo = "mkfifo",
            pathPkill = "pkill",
            env = _merge_env(task.env),
            terminalKind = "integrated",
        }
    end,
}

-- ==================================================================
-- php
-- ==================================================================
_debuggers["php-debug-adapter"] = {
    language = "php",
    adapter_config = function(context)
        return {
            adapter_id = "php-debug-adapter",
            name = "vscode-php-debug",
            type = "executable",
            command = { mason_bin("php-debug") },
            cwd = _get_task_cwd(context),
        }
    end,
    launch_args = function(context)
        local task = context.task
        local dbg = task.debug_options or {}
        return {
            name = "Listen for Xdebug",
            type = "php",
            request = "launch",
        }
    end,
    args_postprocess = function(args, request)
        if request == "launch" then return true end
        args.port = args.port and tonumber(args.port) or nil
        return true
    end
}

-- ==================================================================
-- java
-- ==================================================================
_debuggers["java-debug-server"] = {
    language = "java",
    adapter_config = function(context)
        local dbg = context.task.debug_options or {}
        return {
            adapter_id = "jds",
            name = "java-debug-server",
            type = "server",
            host = dbg.host or "127.0.0.1",
            port = tonumber(dbg.port),
        }
    end,
    attach_args = function(context)
        local dbg = context.task.debug_options or {}
        return {
            request = "attach",
            host = dbg.host or "127.0.0.1",
        }
    end,
    args_postprocess = function(args, request)
        if request == "launch" then return true end
        args.port = args.port and tonumber(args.port) or nil
        return true
    end
}

-- ==================================================================
-- csharp, fsharp
-- ==================================================================
_debuggers.netcoredbg = {
    language = "csharp, fsharp",
    adapter_config = function(context)
        return {
            adapter_id = "netcoredbg",
            name = "netcoredbg",
            type = "executable",
            command = { mason_bin("netcoredbg"), "--interpreter=vscode" },
            cwd = _get_task_cwd(context),
        }
    end,
    launch_args = function(context)
        return {
            type = "coreclr",
            request = "launch",
            program = type(context.task.command) == "string" and context.task.command or nil,
            env = _merge_env(context.task.env),
        }
    end,
    attach_args = function(context)
        local dbg = context.task.debug_options or {}
        return {
            type = "coreclr",
            request = "attach",
            processId = "${select-pid}",
        }
    end,
    args_postprocess = function(args, request)
        if request == "launch" then return true end
        args.processId = args.processId and tonumber(args.processId) or nil
        return true
    end
}

--------------------------------------------------------------------------------
-- Public API
--------------------------------------------------------------------------------

---@return {string:string}
function M.debuggers_summary()
    local summary = {}
    for id, data in pairs(_user_debuggers) do
        summary[id] = data.language or ""
    end
    for id, data in pairs(_debuggers) do
        summary[id] = data.language or ""
    end
    return summary
end

---@param name string
---@return loopdebug.Config.Debugger?
function M.get_debugger(name)
    return _user_debuggers[name] or _debuggers[name]
end

---@param name string
---@param based_on string
---@param debugger_config loopdebug.Config.Debugger
function M.register_debugger(name, based_on, debugger_config)
    local base_debugger = _debuggers[based_on]
    assert(base_debugger, "Invalid base debugger name: " .. tostring(based_on))
    local new_debugger = vim.fn.deepcopy(base_debugger)
    _user_debuggers[name] = vim.tbl_extend('force', new_debugger, debugger_config)
end

return M
