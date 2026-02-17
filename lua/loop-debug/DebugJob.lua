local class            = require('loop.tools.class')
local Session          = require('loop-debug.dap.Session')

---@alias loop.job.DebugJob.Command
---|"session"
---|"thread"
---|"frame"
---|"continue"
---|"step_in"
---|"step_out"
---|"step_over"
---|"terminate"
---|"pause"
---|"continue_all"
---|"terminate_all"
---|"inspect"
---|"ui"

---@class loop.job.DebugJob.SessionController
---@field pause fun(thread_id: number)
---@field continue fun(thread_id: number, all_threads: boolean)
---@field step_in fun(thread_id: number)
---@field step_over fun(thread_id: number)
---@field step_back fun(thread_id: number)
---@field step_out fun(thread_id: number)
---@field terminate fun()

---@class loop.job.debugjob.Tracker
---@field on_exit fun(code : number)|nil
---@field on_sess_added fun(id:number,name:string, parent_id:number?,ctrl:loop.job.DebugJob.SessionController,data:loopdebug.session.DataProviders)|nil
---@field on_sess_removed fun(id:number, name:string)|nil
---@field on_sess_state fun(id:number, name:string, data:loopdebug.session.notify.StateData)|nil
---@field on_thread_pause fun(sess_id:number, sess_name:string,data:loopdebug.session.notify.ThreadsEventScope)|nil
---@field on_thread_continue fun(sess_id:number, sess_name:string,data:loopdebug.session.notify.ThreadsEventScope)|nil
---@field on_breakpoint_event fun(sess_id:number, sess_name:string, event:loopdebug.session.notify.BreakpointsEvent)|nil
---@field on_variable_change fun(sess_id:number, sess_name:string)|nil

---@class loopdebug.DebugJob.SessionData
---@field session loopdebug.Session
---@field repl_ctrl loop.ReplController?
---@field debuggee_output_ctrl loop.OutputBufferController?

---@class loop.job.DebugJob
---@field new fun(self: loop.job.DebugJob, name:string, page_group:loop.PageGroup) : loop.job.DebugJob
---@field _name string
---@field _page_group loop.PageGroup
---@field _session_data table<number,loopdebug.DebugJob.SessionData>
---@field _breakpoints table<number,loopdebug.SourceBreakpoint>
---@field tracker loop.job.debugjob.Tracker
local DebugJob         = class()

local _last_session_id = 0

---Initializes the DebugJob instance.
---@param name string
---@param page_group loop.PageGroup
function DebugJob:init(name, page_group)
    self._log = require('loop-debug.tools.Logger').create_logger("DebugJob[" .. tostring(name) .. "]")
    self._name = name
    self._page_group = page_group
    self._session_data = {}
    self._breakpoints = {}
end

---@return boolean
function DebugJob:is_running()
    return next(self._session_data) ~= nil
end

function DebugJob:terminate()
    for _, data in pairs(self._session_data) do
        data.session:terminate()
    end
end

---@class loop.DebugJob.StartArgs
---@field name string
---@field debug_args loopdebug.session.DebugArgs

---Starts a new terminal job.
---@param args loop.DebugJob.StartArgs
---@param tracker loop.job.debugjob.Tracker
---@return boolean, string|nil
function DebugJob:start(args, tracker)
    assert(#self._session_data == 0 and not self._tracker, "already started")
    self._tracker = tracker
    local ok, err = self:_add_new_session(args.name, args.debug_args)
    return ok, err
end

---@param name string
---@param debug_args loopdebug.session.DebugArgs
---@param parent_sess_id number|nil
---@return boolean,string|nil
function DebugJob:_add_new_session(name, debug_args, parent_sess_id)
    local session_id               = _last_session_id + 1
    _last_session_id               = session_id

    ---@param session loopdebug.Session
    ---@param event loop.session.TrackerEvent
    ---@param event_data any
    local tracker                  = function(session, event, event_data)
        self:_on_session_event(session_id, session, event, event_data)
    end

    local exit_handler             = function(code)
        -- schedule so that it does not happen before on_sess_added event
        vim.schedule(function()
            self:_session_exit_handler(session_id, code)
        end)
    end

    ---@type loopdebug.session.Args
    local session_args             = {
        debug_args = debug_args,
        tracker = tracker,
        exit_handler = exit_handler,
    }

    -- start new session
    local session                  = Session:new(name)

    self._session_data[session_id] = {
        session = session,
    }

    ---@type loop.job.DebugJob.SessionController
    local controller               = {
        pause = function(thread_id) session:debug_pause(thread_id) end,
        continue = function(thread_id, all_threads) session:debug_continue(thread_id, all_threads) end,
        step_in = function(thread_id) session:debug_stepIn(thread_id) end,
        step_over = function(thread_id) session:debug_stepOver(thread_id) end,
        step_back = function(thread_id) session:debug_stepBack(thread_id) end,
        step_out = function(thread_id) session:debug_stepOut(thread_id) end,
        terminate = function() session:debug_terminate() end,
    }

    local data_providers           = session:get_data_providers()

    for _, bp in pairs(self._breakpoints) do
        session:set_source_breakpoint(bp)
    end

    self._tracker.on_sess_added(session_id, name, parent_sess_id, controller, data_providers)

    local started, start_err = session:start(session_args)
    if not started then
        return false, "Failed to start debug session, " .. start_err
    end

    self:_setup_repl(session_id, name, controller, data_providers)

    return true, nil
end

---@param bp loopdebug.SourceBreakpoint
function DebugJob:update_breakpoint(bp)
    if bp.enabled then
        self._breakpoints[bp.id] = bp
        for _, data in pairs(self._session_data) do
            data.session:set_source_breakpoint(bp)
        end
    else
        self:remove_breakpoint(bp)
    end
end

---@param bp loopdebug.SourceBreakpoint
function DebugJob:remove_breakpoint(bp)
    self._breakpoints[bp.id] = nil
    for _, data in pairs(self._session_data) do
        data.session:remove_breakpoint(bp.id)
    end
end

---@param removed loopdebug.SourceBreakpoint[]
function DebugJob:remove_all_breakpoints(removed)
    self._breakpoints = {}
    for _, data in pairs(self._session_data) do
        data.session:remove_all_breakpoints()
    end
end

function DebugJob:_session_exit_handler(session_id, code)
    vim.schedule(function()
        if self._session_data[session_id] then
            local session = self._session_data[session_id].session
            self:_add_debug_output(session_id, session:name(), "log", "Debug session ended")
            self._tracker.on_sess_removed(session_id, session:name())
            self._session_data[session_id] = nil
            if next(self._session_data) == nil then
                self._tracker.on_exit(code)
            end
        end
    end)
end

---@param sess_id number
---@param session loopdebug.Session
---@param event loop.session.TrackerEvent
---@param event_data any
function DebugJob:_on_session_event(sess_id, session, event, event_data)
    if event == "trace" then
        ---@type loopdebug.session.notify.Trace
        local trace = event_data
        local text = trace.text
        if trace.level then text = trace.level .. ": " .. trace.text end
        self:_add_debug_output(sess_id, session:name(), "log", text)
        return
    end
    if event == "state" then
        ---@type loopdebug.session.notify.StateData
        local state = event_data
        self._tracker.on_sess_state(sess_id, session:name(), state)
        return
    end
    if event == "output" then
        ---@type loopdebug.proto.OutputEvent
        local output = event_data
        if output.category ~= "telemetry" then
            self:_add_debug_output(sess_id, session:name(), tostring(output.category), tostring(output.output))
        end
        return
    end
    if event == "runInTerminal_request" then
        ---@type loopdebug.session.notify.RunInTerminalReq
        local request = event_data
        self:add_debug_term(sess_id, session:name(), request.args, request.on_success, request.on_failure)
        return
    end
    if event == "threads_paused" then
        self:_on_session_threads_pause(sess_id, session:name(), event_data)
        return
    end
    if event == "threads_continued" then
        self._tracker.on_thread_continue(sess_id, session:name(), event_data)
        return
    end
    if event == "variable_change" then
        self._tracker.on_variable_change(sess_id, session:name())
        return
    end
    if event == "breakpoints" then
        ---@type loopdebug.session.notify.BreakpointsEvent
        local data = event_data
        self:_on_session_breakpoints_event(sess_id, session, data)
        return
    end
    if event == "debuggee_exit" then
        self:_on_session_debuggee_exit(sess_id, session)
        return
    end
    if event == "subsession_request" then
        ---@type loopdebug.session.notify.SubsessionRequest
        local request = event_data
        self:_on_subsession_request(sess_id, session, request)
        return
    end
    if event == "thread_added" or event == "thread_removed" then
        -- not needed for now
        return
    end
    vim.notify("LoopDebug: unhandled dap session event: " .. event)
end

---@param sess_id number
---@param name string
---@param args loopdebug.proto.RunInTerminalRequestArguments
---@param on_success fun(pid:number)
---@param on_failure fun(reason:string)
function DebugJob:add_debug_term(sess_id, name, args, on_success, on_failure)
    --vim.notify(vim.inspect{name, args, on_success, on_failure})
    assert(type(name) == "string")
    assert(type(args) == "table")
    assert(type(on_success) == "function")
    assert(type(on_failure) == "function")

    local session_data = self._session_data[sess_id]
    assert(session_data)

    local start_args = { name = name, command = args.args, env = args.env, cwd = args.cwd, on_exit_handler = function() end }
    local pd, err = self._page_group.add_page({
        type = "term",
        buftype = "loopdebug-term",
        label = "Output",
        term_args = start_args,
        activate = true
    })
    if pd and pd.term_proc then on_success(pd.term_proc:get_pid()) else on_failure(err or "term startup error") end
end

---@param sess_id number
---@param sess_name string
---@param event_data loopdebug.session.notify.ThreadsEventScope
function DebugJob:_on_session_threads_pause(sess_id, sess_name, event_data)
    self._tracker.on_thread_pause(sess_id, sess_name, event_data)
end

---@param sess_id number
---@param session loopdebug.Session
---@param event loopdebug.session.notify.BreakpointsEvent
function DebugJob:_on_session_breakpoints_event(sess_id, session, event)
    self._tracker.on_breakpoint_event(sess_id, session:name(), event)
end

---@param sess_id number
---@param session loopdebug.Session
function DebugJob:_on_session_debuggee_exit(sess_id, session)
end

---@param sess_id number
---@param session loopdebug.Session
---@param request loopdebug.session.notify.SubsessionRequest
function DebugJob:_on_subsession_request(sess_id, session, request)
    self._log:debug("Starting subsession via startDebugging: " .. vim.inspect(request))

    local ok, err = self:_add_new_session(request.name, request.debug_args, sess_id)
    if not ok then
        return request.on_failure("failed to startup child session, " .. tostring(err))
    end

    request.on_success({})
end

---@param sesion_id number
---@param session_name string
---@param controller loop.job.DebugJob.SessionController
---@param data_providers loopdebug.session.DataProviders
function DebugJob:_setup_repl(sesion_id, session_name, controller, data_providers)
    local session_data = self._session_data[sesion_id]
    assert(session_data)

    -- Setup REPL
    local page_data = self._page_group.add_page({
        type = "repl",
        buftype = "loopdebug-repl",
        label = "Console",
        activate = false
    })

    if not page_data then
        return
    end

    session_data.repl_ctrl = page_data.repl_buf
    session_data.repl_ctrl.set_input_handler(function(input)
        data_providers.evaluate_provider({
            expression = input,
            context = "repl",
        }, function(eval_err, data)
            if not data then
                local msg = eval_err or "Evaluation error"
                session_data.repl_ctrl.add_output("\27[31m" .. msg .. "\27[0m")
            else
                session_data.repl_ctrl.add_output(tostring(data.result))
            end
        end)
    end)
    session_data.repl_ctrl.set_completion_handler(function(input, callback)
        data_providers.completion_provider({
            text = input,
            column = #input + 1,
            frameId = nil, -- is frameId needed?
        }, function(compl_err, data)
            if data then
                local strs = {}
                for _, item in ipairs(data.targets or {}) do
                    local str = item.text or item.label
                    if str then table.insert(strs, str) end
                end
                callback(strs)
            else
                callback(nil, compl_err)
            end
        end)
    end)
end

---@param sess_id number
---@param sess_name string
---@param category string
---@param output string
function DebugJob:_add_debug_output(sess_id, sess_name, category, output)
    ---@type loopdebug.DebugJob.SessionData?
    local sess_data = self._session_data[sess_id]
    assert(sess_data)

    -- REPL Output
    if category ~= "stdout" and category ~= "stderr" then
        if sess_data.repl_ctrl then
            for line in output:gmatch("([^\r\n]*)\r?\n?") do
                if line ~= "" then sess_data.repl_ctrl.add_output(line) end
            end
        end
        return
    end

    -- Process Output
    if not sess_data.debuggee_output_ctrl then
        local page_data = self._page_group.add_page({ buftype = "loopdebug-output", type = "output", label = "Output" })
        if page_data then
            sess_data.debuggee_output_ctrl = page_data.output_buf
        end
    end

    if sess_data.debuggee_output_ctrl then
        --local highlight = (category == "stderr") and "ErrorMsg" or nil -- TODO
        for line in output:gmatch("([^\r\n]*)\r?\n?") do
            if line ~= "" then
                sess_data.debuggee_output_ctrl.add_lines(line)
            end
        end
    end
end

return DebugJob
