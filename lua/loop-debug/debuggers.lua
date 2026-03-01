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
---@field adapter_config loopdebug.AdapterConfig|(fun(ctx:loopdebug.TaskContext):loopdebug.AdapterConfig?,string?)
---@field launch_args nil|table|fun(ctx:loopdebug.TaskContext):table
---@field attach_args nil|table|fun(ctx:loopdebug.TaskContext):table
---@field terminate_debuggee nil|boolean|fun(ctx:loopdebug.TaskContext):boolean
---@field start_hook nil|fun(ctx:loopdebug.Config.Debugger.HookContext,cb:fun(ok:boolean,err:string|nil))
---@field end_hook nil|fun(ctx:loopdebug.Config.Debugger.HookContext,cb:fun())

--------------------------------------------------------------------------------
-- Internal Helpers
--------------------------------------------------------------------------------

-- Keys that the user should NOT be able to override because they are
-- derived from the task's top-level fields or internal adapter logic.
local _protected_keys = {
    request = true,
    type = true,
    program = true,
    args = true,
    cwd = true,
    processId = true,
    host = true,
    port = true,
}

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

---Merges user debug_options into the base config.
---Allows overrides for most fields, but protects core DAP structural keys.
---@param base table The internal/calculated DAP args
---@param task loopdebug.Task The task containing user-defined debug_options
---@return table
local function _merge_debug_options(base, task)
    local opts = vim.deepcopy(base)
    if task.debug_options and type(task.debug_options) == "table" then
        for k, v in pairs(task.debug_options) do
            if not _protected_keys[k] then
                opts[k] = v
            end
        end
    end
    return opts
end

--------------------------------------------------------------------------------
-- Debugger Definitions
--------------------------------------------------------------------------------

---@type table<string,loopdebug.Config.Debugger>
local _debuggers = {}

---@type table<string,loopdebug.Config.Debugger>
local _user_debuggers = {}

-- ==================================================================
-- Lua
-- ==================================================================
_debuggers.lua = {
    adapter_config = function(ctx)
        local adapter_path = vim.fs.joinpath(vim.fn.stdpath("data"), "mason", "packages", "local-lua-debugger-vscode",
            "extension", "extension", "debugAdapter.js")
        ---@diagnostic disable-next-line: undefined-field
        if not vim.uv.fs_stat(adapter_path) then
            return nil, ("local-lua-debugger-vscode debug adapter not found (%s)"):format(adapter_path)
        end
        return {
            adapter_id = "lua",
            name = "Local Lua Debugger",
            type = "executable",
            command = { "node", adapter_path },
            env = _merge_env({
                LUA_PATH = vim.fs.joinpath(vim.fn.stdpath("data"), "mason", "packages", "local-lua-debugger-vscode",
                    "extension", "debugger", "?.lua") .. ";;"
            }),
        }
    end,
    launch_args = function(context)
        return _merge_debug_options({
            type = "lua-local",
            request = "launch",
            name = "Debug",
            cwd = _get_task_cwd(context),
            program = {
                lua = vim.fn.exepath("lua"),
                file = get_task_program(context.task),
                communication = 'stdio',
            },
        }, context.task)
    end,
}

_debuggers["lua:remote"] = {
    adapter_config = function(context)
        return {
            adapter_id = "lua",
            name = "Lua Remote Debugger",
            type = "server",
            host = context.task.host or "127.0.0.1",
            port = tonumber(context.task.port),
        }
    end,
    attach_args = function(context)
        return _merge_debug_options({
            request = "attach",
            type = "lua",
            host = context.task.host or "127.0.0.1",
            port = tonumber(context.task.port),
            cwd = _get_task_cwd(context),
        }, context.task)
    end,
}

-- ==================================================================
-- LLDB (lldb-dap)
-- ==================================================================
_debuggers.lldb = {
    adapter_config = function()
        return {
            adapter_id = "lldb",
            name = "LLDB (via lldb-dap)",
            type = "executable",
            command = { mason_bin("lldb-dap") },
        }
    end,
    launch_args = function(context)
        local task = context.task
        return _merge_debug_options({
            program = get_task_program(task),
            args = get_task_args(task),
            cwd = _get_task_cwd(context),
            env = _merge_env(task.env),
            stopOnEntry = task.stop_on_entry or false,
            runInTerminal = task.run_in_terminal ~= false,
        }, task)
    end,
    attach_args = function(context)
        return _merge_debug_options({
            pid = tonumber(context.task.processId),
            program = type(context.task.command) == "string" and context.task.command or nil,
        }, context.task)
    end,
}

-- ==================================================================
-- codelldb
-- ==================================================================
_debuggers.codelldb = {
    adapter_config = function()
        return {
            adapter_id = "codelldb",
            name = "codelldb",
            type = "executable",
            command = { mason_bin("codelldb") },
        }
    end,
    launch_args = function(context)
        local task = context.task
        return _merge_debug_options({
            name = "Launch (codelldb)",
            type = "codelldb",
            request = "launch",
            program = get_task_program(task),
            args = get_task_args(task),
            cwd = _get_task_cwd(context),
            env = _merge_env(task.env),
            stopOnEntry = task.stop_on_entry or false,
            runInTerminal = task.run_in_terminal ~= false,
        }, task)
    end,
    attach_args = function(context)
        return _merge_debug_options({
            name = "Attach (codelldb)",
            type = "codelldb",
            request = "attach",
            pid = tonumber(context.task.processId),
        }, context.task)
    end,
}

-- ==================================================================
-- GDB
-- ==================================================================
_debuggers.gdb = {
    adapter_config = function()
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
        }
    end,
    launch_args = function(context)
        local task = context.task
        return _merge_debug_options({
            program = get_task_program(task),
            args = get_task_args(task),
            cwd = _get_task_cwd(context),
            env = _merge_env(task.env),
            stopAtBeginningOfMainSubprogram = task.stop_on_entry or false,
            runInTerminal = task.run_in_terminal ~= false,
        }, task)
    end,
    attach_args = function(context)
        return _merge_debug_options({
            request = "attach",
            pid = tonumber(context.task.processId),
            cwd = _get_task_cwd(context),
        }, context.task)
    end,
}

-- ==================================================================
-- JavaScript / TypeScript (js-debug)
-- ==================================================================
_debuggers["js-debug"] = {
    start_hook = function(context, callback)
        local task = context.task
        local port = (type(task.port) == "number" and task.port) or 0
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
        return {
            adapter_id = "js-debug",
            name = "js-debug",
            type = "server",
            host = context.task.host or "::1",
            port = tonumber(context.task.port) or 0,
            cwd = _get_task_cwd(context),
        }
    end,

    launch_args = function(context)
        local task = context.task
        return _merge_debug_options({
            type = "pwa-node",
            request = "launch",
            runtimeExecutable = "node",
            program = get_task_program(task),
            args = get_task_args(task),
            cwd = _get_task_cwd(context),
            env = _merge_env(task.env),
            stopOnEntry = task.stop_on_entry or false,
        }, task)
    end,

    attach_args = function(context)
        local task = context.task
        return _merge_debug_options({
            type = "pwa-node",
            request = "attach",
            port = tonumber(task.port) or 0,
            cwd = _get_task_cwd(context),
        }, task)
    end,
}

-- ==================================================================
-- Python (debugpy)
-- ==================================================================
_debuggers.debugpy = {
    adapter_config = function()
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
        }
    end,
    launch_args = function(context)
        local task = context.task
        return _merge_debug_options({
            program = get_task_program(task),
            args = get_task_args(task),
            cwd = _get_task_cwd(context),
            env = _merge_env(task.env),
            console = "integratedTerminal",
        }, task)
    end,
}

_debuggers["debugpy:remote"] = {
    adapter_config = function(context)
        return {
            adapter_id = "debugpy",
            name = "debugpy",
            type = "server",
            host = context.task.host or "127.0.0.1",
            port = tonumber(context.task.port),
        }
    end,
    attach_args = function(context)
        local task = context.task
        return _merge_debug_options({
            request = "attach",
            connect = {
                host = context.task.host or "127.0.0.1",
                port = tonumber(context.task.port),
            }
        }, task)
    end,
}

-- ==================================================================
-- Go (delve)
-- ==================================================================
_debuggers.go = {
    adapter_config = function()
        return {
            adapter_id = "go",
            name = "Delve (dlv)",
            type = "executable",
            command = { mason_bin("delve"), "dap", "-l", "127.0.0.1:0" },
        }
    end,
    launch_args = function(context)
        local task = context.task
        return _merge_debug_options({
            mode = "debug",
            program = task.cwd or _get_task_cwd(context),
            env = _merge_env(task.env),
            dlvToolPath = mason_bin("delve"),
        }, task)
    end,
    attach_args = function(context)
        return _merge_debug_options({
            mode = "local",
            processId = context.task.processId,
        }, context.task)
    end,
}

-- ==================================================================
-- Other (Chrome, Bash, PHP, Java, NetCore)
-- ==================================================================
_debuggers.chrome = {
    adapter_config = function()
        return {
            adapter_id = "chrome",
            name = "Chrome",
            type = "executable",
            command = { mason_bin("chrome-debug-adapter") },
        }
    end,
    launch_args = function(context)
        return _merge_debug_options({
            type = "chrome",
            request = "launch",
            webRoot = context.task.cwd or _get_task_cwd(context),
        }, context.task)
    end,
    attach_args = function(context)
        return _merge_debug_options({
            type = "chrome",
            request = "attach",
            port = tonumber(context.task.port) or 9222,
            webRoot = context.task.cwd or _get_task_cwd(context),
        }, context.task)
    end,
}

_debuggers.bash = {
    adapter_config = function()
        return {
            adapter_id = "bash",
            name = "bashdb",
            type = "executable",
            command = { mason_bin("bash-debug-adapter") },
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
        return _merge_debug_options({
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
        }, task)
    end,
}

_debuggers.php = {
    adapter_config = function()
        return {
            adapter_id = "php",
            name = "PHP Debug (vscode-php-debug)",
            type = "executable",
            command = { mason_bin("php-debug") },
        }
    end,
    launch_args = function(context)
        local task = context.task
        return _merge_debug_options({
            name = "Listen for Xdebug",
            type = "php",
            request = "launch",
            port = tonumber(task.port) or 9003,
        }, task)
    end,
}

_debuggers.java = {
    adapter_config = function(context)
        return {
            adapter_id = "java",
            name = "Java (jdtls)",
            type = "server",
            host = context.task.host or "127.0.0.1",
            port = tonumber(context.task.port),
        }
    end,
    attach_args = function(context)
        return _merge_debug_options({
            request = "attach",
            host = context.task.host or "127.0.0.1",
            port = tonumber(context.task.port),
        }, context.task)
    end,
}

_debuggers.netcoredbg = {
    adapter_config = function()
        return {
            adapter_id = "netcoredbg",
            name = "netcoredbg",
            type = "executable",
            command = { mason_bin("netcoredbg") },
            args = { "--interpreter=vscode" },
        }
    end,
    launch_args = function(context)
        return _merge_debug_options({
            type = "coreclr",
            request = "launch",
            program = type(context.task.command) == "string" and context.task.command or nil,
            env = _merge_env(context.task.env),
        }, context.task)
    end,
    attach_args = function(context)
        return _merge_debug_options({
            type = "coreclr",
            request = "attach",
            processId = tonumber(context.task.processId),
        }, context.task)
    end,
}

--------------------------------------------------------------------------------
-- Public API
--------------------------------------------------------------------------------

---@return string[]
function M.debugger_names()
    local names = {}
    for name, _ in pairs(_user_debuggers) do names[name] = true end
    for name, _ in pairs(_debuggers) do names[name] = true end
    return vim.fn.sort(vim.tbl_keys(names))
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
