local M = {}

local config = require('loop-debug.config')
local DebugJob = require('loop-debug.DebugJob')
local SessionList = require('loop-debug.comp.SessionList')
local manager = require('loop-debug.manager')
local breakpoints = require('loop-debug.breakpoints')
local fntools = require('loop.tools.fntools')
local logs = require('loop.logs')

---@type loop.comp.ItemList?
local _sessionlist_comp = nil
---@type loop.PageGroup?
local _repl_page_group = nil
---@type loop.PageGroup?
local _output_page_group = nil

---@param task_name string
---@param page_manager loop.PageManager
---@param on_exit fun(code : number)
---@return loop.job.debugjob.Tracker
local function _create_job_tracker(task_name, page_manager, on_exit)
    assert(type(task_name) == "string")

    if not _sessionlist_comp then
        local page_data = page_manager.add_page_group("Debug Sessions").add_page({
            type = "comp",
            buftype = "loopdebug-sessions",
            label = "Debug Sessions",
            activate = true,
        })
        assert(page_data)
        _sessionlist_comp = SessionList:new()
        _sessionlist_comp:link_to_buffer(page_data.comp_buf)
        _sessionlist_comp:set_page(page_data.page)
        if not _repl_page_group then
            _repl_page_group = page_manager.add_page_group("Debug Console")
        end
        if not _output_page_group then
            _output_page_group = page_manager.add_page_group("Debug Output")
        end
    end
    assert(_repl_page_group)
    assert(_output_page_group)

    ---@type loop.job.debugjob.Tracker
    return {
        on_sess_added = function(id, name, pid, ctrl, prov)
            manager.add_session(id, name, pid, ctrl, prov,
                _repl_page_group, _output_page_group)
        end,
        on_sess_removed = function(id, name)
            manager.remove_session(id, name)
        end,
        on_sess_state = function(id, name, data)
            manager.on_session_state_update(id, name, data)
        end,
        on_output = function(id, name, cat, out)
            manager.on_session_output(id, name, cat, out)
        end,
        on_thread_pause = function(id, name, data)
            manager.on_session_thread_pause(id, name, data)
        end,
        on_thread_continue = function(id, name, data)
            manager.on_session_thread_continue(id, name, data)
        end,
        on_new_term = function(name, args, cb)
            local start_args = { name = name, command = args.args, env = args.env, cwd = args.cwd, on_exit_handler = function() end }
            local pd, err = _output_page_group.add_page({
                type = "term",
                buftype = "loopdebug-term",
                label = name,
                term_args = start_args,
                activate = true
            })
            if pd and pd.term_proc then cb(pd.term_proc:get_pid(), nil) else cb(nil, err) end
        end,
        on_breakpoint_event = function(sess_id, sess_name, event)
            manager.on_breakpoint_event(sess_id, event)
        end,
        on_startup_error = function()
            on_exit(-1)
        end,
        on_exit = function(code)
            on_exit(code)
        end
    }
end


---@param args loop.DebugJob.StartArgs
---@param page_manager loop.PageManager
---@param startup_callback fun(job: loop.job.DebugJob|nil, err: string|nil)
---@param exit_handler fun(code: number)
local function _start_debug_job(args, page_manager, startup_callback, exit_handler)
    -- Final DAP type validation
    if args.debug_args.adapter.type ~= "executable" and args.debug_args.adapter.type ~= "server" then
        return startup_callback(nil,
            ("invalid adapter type '%s' — must be 'executable' or 'server'"):format(tostring(args.debug_args
                .adapter
                .type)))
    end

    logs.log("Starting debug:\n" .. vim.inspect(args))
    local job = DebugJob:new(args.name)

    local bpts_tracker_ref = breakpoints.add_tracker({
        on_set = function(bp) job:update_breakpoint(bp) end,
        on_removed = function(bp) job:remove_breakpoint(bp) end,
        on_enabled = function(bp) job:update_breakpoint(bp) end,
        on_disabled = function(bp) job:update_breakpoint(bp) end,
        on_moved = function(bp) job:update_breakpoint(bp) end,
        on_all_removed = function(bpts) job:remove_all_breakpoints(bpts) end
    })

    -- Add trackers
    job:add_tracker(_create_job_tracker(args.name, page_manager, function(code)
        bpts_tracker_ref:cancel()
        exit_handler(code)
    end))

    -- Start the debug job
    local ok, err = job:start(args)
    if not ok then
        return startup_callback(nil, err or "failed to start debug job")
    end

    require('loop-debug.ui').show()

    -- Success!
    startup_callback(job, nil)
end


---@type fun(ws_dir:string,task:loopdebug.Task,page_manager:loop.PageManager, on_exit:loop.TaskExitHandler):(loop.TaskControl|nil,string|nil)
function M.start_debug_task(ws_dir, task, page_manager, on_exit)
    assert(type(ws_dir) == "string")
    -- Early validation
    if not task or type(task) ~= "table" then
        return nil, "task is required and must be a table"
    end
    if not task.name or type(task.name) ~= "string" or #task.name == 0 then
        return nil, "task.name must be a non-empty string"
    end
    if task.type ~= "debug" then
        return nil, "task.type must be 'debug'"
    end
    if task.request ~= "launch" and task.request ~= "attach" then
        return nil, "task.request must be 'launch' or 'attach'"
    end

    ---@type loopdebug.Config.Debugger
    local debugger = config.current.debuggers[task.debugger]
    if not debugger then
        return nil, ("no debugger config found for task.debugger '%s'"):format(tostring(task.debugger))
    end

    ---- debug adapter config ---
    ---@type loopdebug.AdapterConfig
    local adapter_config
    if type(debugger.adapter_config) == "function" then
        ---@type loopdebug.TaskContext
        local task_context = {
            task = task,
            ws_dir = ws_dir
        }
        ---@type loopdebug.AdapterConfig
        adapter_config = debugger.adapter_config(task_context)
        if type(adapter_config) ~= "table" then
            return nil, "debugger.adapter_config function must return a table"
        end
    else
        -- deep copy because a badly coded hook may change the config
        ---@type loopdebug.AdapterConfig
        ---@diagnostic disable-next-line: assign-type-mismatch, param-type-mismatch
        adapter_config = vim.deepcopy(debugger.adapter_config)
    end

    adapter_config.cwd = adapter_config.cwd or ws_dir
    if not adapter_config.cwd then
        return nil, "'cwd' is missing in task config"
    end

    -- request config
    local request_args
    if task.request == "launch" then
        request_args = debugger.launch_args or {}
    else
        request_args = debugger.attach_args or {}
    end

    if type(request_args) == "function" then
        ---@type loopdebug.TaskContext
        local task_context = {
            task = task,
            ws_dir = ws_dir
        }
        request_args = request_args(task_context)
        if type(request_args) ~= "table" then
            return nil, "debugger.request_args function must return a table"
        end
    else
        -- deep copy because a badly coded hook may change the args
        request_args = vim.deepcopy(request_args)
    end

    -- job args
    ---@type loop.DebugJob.StartArgs
    local start_args = {
        name = task.name,
        debug_args = {
            adapter = adapter_config,
            request = task.request,
            request_args = request_args,
            terminate_debuggee = task.terminateOnDisconnect,
        },
    }

    ---@type loopdebug.Config.Debugger.HookContext
    local hook_context = {
        task = task,
        ws_dir = ws_dir,
        adapter_config = adapter_config,
        page_manager = page_manager,
        user_data = {}
    }

    local task_control_context = {
        job = nil,
        disable_control = false,
        termination_requested = false,
    }

    local start_job = function()
        ---@type fun(job: loop.job.DebugJob|nil, err: string|nil)
        local function on_job_start(job, err)
            if not job then
                task_control_context.disable_control = true
                on_exit(false, err or "initialization error")
            elseif task_control_context.termination_requested then
                if job:is_running() then
                    job:terminate()
                else
                    task_control_context.disable_control = true
                    on_exit(false, "task terminated before startup completed")
                end
            else
                task_control_context.job = job
            end
        end
        local on_job_exit = function(code)
            if debugger.end_hook then
                logs.user_log("calling debugger end_hook", "task")
                hook_context.exit_code = code
                debugger.end_hook(hook_context, fntools.called_once(function()
                    task_control_context.disable_control = true
                    on_exit(code == 0, "Exit code: " .. tostring(code))
                end))
            else
                task_control_context.disable_control = true
                on_exit(code == 0, "Exit code: " .. tostring(code))
            end
        end
        _start_debug_job(start_args, page_manager, on_job_start, on_job_exit)
    end

    if debugger.start_hook then
        logs.user_log("calling debugger start_hook", "task")
        debugger.start_hook(hook_context, fntools.called_once(function(ok, err)
            if ok then
                start_job()
            else
                task_control_context.disable_control = true
                on_exit(false, err or "start_hook error")
            end
        end))
    else
        start_job()
    end

    ---@type loop.TaskControl
    local task_control = {
        terminate = function()
            if task_control_context.disable_control then
                return
            end
            task_control_context.termination_requested = true
            if task_control_context.job then
                task_control_context.job:terminate()
            end
        end
    }
    return task_control
end

return M
