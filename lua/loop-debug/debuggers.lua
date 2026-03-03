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
---@field enrich_launch_args (fun(args:table, ctx:loopdebug.TaskContext):boolean?,string?)?
---@field enrich_attach_args (fun(args:table, ctx:loopdebug.TaskContext):boolean?,string?)?
---@field start_hook nil|fun(ctx:loopdebug.Config.Debugger.HookContext,cb:fun(ok:boolean,err:string|nil))
---@field end_hook nil|fun(ctx:loopdebug.Config.Debugger.HookContext,cb:fun())

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

local function fill_launch_defaults(args, ctx)
    local task = ctx.task
    args.request = "launch"
    args.program = args.program or get_task_program(task)
    args.args = args.args or get_task_args(task)
    args.cwd = args.cwd or _get_task_cwd(ctx)
    args.env = args.env or _merge_env(task.env)
end

local function fill_attach_defaults(args, ctx)
    args.request = "attach"
end

--------------------------------------------------------------------------------
-- Debugger Definitions
--------------------------------------------------------------------------------

---@type table<string,loopdebug.Config.Debugger>
local _debuggers = {}

---@type table<string,loopdebug.Config.Debugger>
local _user_debuggers = {}

-- ==================================================================
_debuggers["local-lua-debugger"] = {
    language = "lua",

    adapter_config = function(context)
        local adapter_path = vim.fs.joinpath(
            vim.fn.stdpath("data"),
            "mason", "packages", "local-lua-debugger-vscode",
            "extension", "extension", "debugAdapter.js"
        )
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
                LUA_PATH = vim.fs.joinpath(
                    vim.fn.stdpath("data"),
                    "mason", "packages", "local-lua-debugger-vscode",
                    "extension", "debugger", "?.lua"
                ) .. ";;"
            }),
        }
    end,

    enrich_launch_args = function(args, ctx)
        -- We do NOT call fill_launch_defaults here,
        -- because this debugger uses a special `program` structure.

        args.type = args.type or "lua-local"
        args.request = "launch"
        args.name = args.name or "Debug"
        args.cwd = args.cwd or _get_task_cwd(ctx)

        args.program = args.program or {
            lua = vim.fn.exepath("lua"),
            file = get_task_program(ctx.task),
            communication = "stdio",
        }

        return true
    end,
}

_debuggers["osv"] = {
    language = "lua",

    adapter_config = function(context)
        local args = context.task.debug_options or {}

        return {
            adapter_id = "lua-remote-debugger",
            name = "Lua Remote Debugger",
            type = "server",
            host = args.host or "127.0.0.1",
            port = args.port and tonumber(args.port),
        }
    end,

    enrich_attach_args = function(args, ctx)
        fill_attach_defaults(args, ctx)
        args.type = args.type or "lua"
        args.host = args.host or args.host or "127.0.0.1"
        args.port = args.port and tonumber(args.port)
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

    enrich_launch_args = function(args, ctx)
        fill_launch_defaults(args, ctx)
        args.runInTerminal = args.runInTerminal ~= false
        return true
    end,

    enrich_attach_args = function(args, ctx)
        fill_attach_defaults(args, ctx)
        if not args.pid then
            return false, "pid required"
        end
        args.pid = args.pid and tonumber(args.pid)
        if not args.pid then
            return false, "invalid pid"
        end
        return true
    end,
}

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

    enrich_launch_args = function(args, ctx)
        fill_launch_defaults(args, ctx)

        args.name = args.name or "Launch (codelldb)"
        args.type = args.type or "codelldb"
        args.request = "launch"
        args.runInTerminal = args.runInTerminal ~= false
        return true
    end,

    enrich_attach_args = function(args, ctx)
        fill_attach_defaults(args, ctx)

        args.name = args.name or "Attach (codelldb)"
        args.type = args.type or "codelldb"
        args.request = "attach"
        if not args.pid then
            return false, "pid required"
        end
        args.pid = args.pid and tonumber(args.pid)
        if not args.pid then
            return false, "invalid pid"
        end
        return true
    end
}

_debuggers.gdb = {
    language = "c, cpp, rust",
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

    enrich_launch_args = function(args, ctx)
        fill_launch_defaults(args, ctx)
        args.request = "launch"
        args.runInTerminal = args.runInTerminal ~= false
        return true
    end,

    enrich_attach_args = function(args, ctx)
        fill_attach_defaults(args, ctx)
        args.request = "attach"
        if not args.pid then
            return false, "pid required"
        end
        args.pid = args.pid and tonumber(args.pid)
        if not args.pid then
            return false, "invalid pid"
        end
        return true
    end
}

_debuggers["js-debug"] = {
    language = "javascript, typescript",

    start_hook = function(context, callback)
        local task = context.task
        local args = task.debug_options or {}
        local port = (type(args.port) == "number" and args.port) or 0
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
        local args = context.task.debug_options or {}
        return {
            adapter_id = "js-debug-adapter",
            name = "js-debug",
            type = "server",
            host = args.host or "::1",
            port = tonumber(args.port) or 0,
        }
    end,

    enrich_launch_args = function(args, ctx)
        fill_launch_defaults(args, ctx)

        args.type = args.type or "pwa-node"
        args.request = "launch"
        args.runtimeExecutable = args.runtimeExecutable or "node"
        return true
    end,

    enrich_attach_args = function(args, ctx)
        fill_attach_defaults(args, ctx)

        args.type = args.type or "pwa-node"
        args.request = "attach"
        args.port = args.port and tonumber(args.port)
        return true
    end
}

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

    enrich_launch_args = function(args, ctx)
        fill_launch_defaults(args, ctx)
        args.console = args.console or "integratedTerminal"
        return true
    end
}

_debuggers["debugpy:remote"] = {
    language = "python",

    adapter_config = function(context)
        local args = context.task.debug_options or {}
        return {
            adapter_id = "debugpy",
            name = "debugpy",
            type = "server",
            host = args.connect and args.connect.host or "127.0.0.1",
            port = args.connect and args.connect.port and tonumber(args.connect.port),
        }
    end,

    enrich_attach_args = function(args, ctx)
        fill_attach_defaults(args, ctx)
        args.connect = args.connect or {}
        args.connect.host = args.connect.host or "127.0.0.1"
        args.connect.port = args.connect.port and tonumber(args.connect.port)

        return true
    end
}

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

    enrich_launch_args = function(args, ctx)
        fill_launch_defaults(args, ctx)

        args.mode = args.mode or "debug"
        args.program = args.program or (ctx.task.cwd or _get_task_cwd(ctx))
        args.dlvToolPath = args.dlvToolPath or mason_bin("delve")
        return true
    end,

    enrich_attach_args = function(args, ctx)
        fill_attach_defaults(args, ctx)
        args.mode = args.mode or "local"
        if not args.processId then
            return false, "processId required"
        end
        args.processId = args.processId and tonumber(args.processId)
        if not args.processId then
            return false, "invalid processId"
        end
        return true
    end
}

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

    enrich_launch_args = function(args, ctx)
        fill_launch_defaults(args, ctx)

        local mason_opt_path = vim.fs.joinpath(vim.fn.stdpath("data"), "mason", "opt", "bashdb")
        local bashdb_exe = vim.fs.joinpath(mason_opt_path, "bashdb")
        local bashdb_lib = mason_opt_path

        ---@diagnostic disable-next-line: undefined-field
        local path_to_bashdb = vim.uv.fs_stat(bashdb_exe) and bashdb_exe or "bashdb"

        args.name = args.name or "Launch Bash Script"
        args.type = "bashdb"
        args.request = "launch"
        args.pathBash = args.pathBash or "bash"
        args.pathBashdb = args.pathBashdb or path_to_bashdb
        args.pathBashdbLib = args.pathBashdbLib or bashdb_lib
        args.pathCat = args.pathCat or "cat"
        args.pathMkfifo = args.pathMkfifo or "mkfifo"
        args.pathPkill = args.pathPkill or "pkill"
        args.terminalKind = args.terminalKind or "integrated"
        return true
    end
}

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

    enrich_launch_args = function(args, ctx)
        fill_launch_defaults(args, ctx)
        args.name = args.name or "Listen for Xdebug"
        args.type = args.type or "php"
        return true
    end
}

_debuggers["java-debug-server"] = {
    language = "java",

    adapter_config = function(context)
        local args = context.task.debug_options or {}
        return {
            adapter_id = "jds",
            name = "java-debug-server",
            type = "server",
            host = args.host or "127.0.0.1",
            port = tonumber(args.port),
        }
    end,

    enrich_attach_args = function(args, ctx)
        fill_attach_defaults(args, ctx)
        args.request = "attach"
        args.host = args.host or "127.0.0.1"
        args.host = args.host and tonumber(args.host)
        return true
    end
}

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

    enrich_launch_args = function(args, ctx)
        fill_launch_defaults(args, ctx)

        args.type = args.type or "coreclr"
        args.request = "launch"
        args.program = args.program
            or (type(ctx.task.command) == "string" and ctx.task.command or nil)
        return true
    end,

    enrich_attach_args = function(args, ctx)
        fill_attach_defaults(args, ctx)
        args.type = args.type or "coreclr"
        args.request = "attach"
        if not args.processId then
            return false, "processId required"
        end
        args.processId = args.processId and tonumber(args.processId)
        if not args.processId then
            return false, "invalid processId"
        end

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
---@return loopdebug.Config.Debugger?
function M.get_debugger_config(name)
    local existing = _user_debuggers[name] or _debuggers[name]
    return existing and vim.fn.deepcopy(existing) or nil
end

---@param name string
---@param debugger_config loopdebug.Config.Debugger
function M.register_debugger(name, debugger_config)
    assert(
        type(name) == "string" and name:match("[_%a][_%w]*") ~= nil,
        "Invalid debugger name: " .. tostring(name)
    )
    vim.validate('debugger_config', debugger_config, "table")
    vim.validate('debugger_config.adapter_config', debugger_config.adapter_config, "function")
    _user_debuggers[name] = vim.fn.deepcopy(debugger_config)
end

return M
