local breakpoints   = require('loop-debug.breakpoints')
local daptools      = require('loop-debug.dap.daptools')
local debugevents   = require('loop-debug.debugevents')
local selector      = require('loop.tools.selector')
local floatwin      = require('loop.tools.floatwin')
local strtools      = require('loop.tools.strtools')

local M             = {}

-- =============================================================================
-- Type Definitions
-- =============================================================================

---@class loopdebug.mgr.ContextData
---@field session_ctx number The global session context counter
---@field pause_ctx number   The pause state context counter for the current session
---@field thread_ctx number  The thread selection context counter
---@field frame_ctx number   The stack frame selection context counter
---@
---@class loopdebug.mgr.SessionData
---@field sess_name string|nil
---@field state string|nil
---@field controller loop.job.DebugJob.SessionController
---@field data_providers loopdebug.session.DataProviders
---@field all_threads_paused boolean
---@field spurious_pause boolean
---@field paused_threads table<number, boolean> Set of paused thread IDs
---@field cur_thread_id number|nil Currently selected thread
---@field cur_frame loopdebug.proto.StackFrame|nil Currently selected stack frame
---@field debuggee_output_ctrl loop.OutputBufferController|nil

---@alias loopdebug.mgr.JobCommandFn fun(cmd:loop.job.DebugJob.Command):boolean,(string|nil)

---@class loopdebug.mgr.ManagerData
---@field context_data loopdebug.mgr.ContextData
---@field view_update_seq number
---@field current_session_id number|nil
---@field session_data table<number, loopdebug.mgr.SessionData>

---@type loopdebug.mgr.ManagerData
local _manager_data = {
    context_data = {
        session_ctx = 1,
        thread_ctx = 1,
        frame_ctx = 1,
        pause_ctx = 1,
    },
    view_update_seq = 0,
    session_data = {}
}

-- =============================================================================
-- Context Management
-- =============================================================================

---@return loopdebug.mgr.ContextData
local function _get_context()
    return vim.fn.deepcopy(_manager_data.context_data)
end
---Increments the context counter for a specific level, invalidating previous async requests.
---@param level "session"|"pause"|"thread"|"frame"
local function _increment_context(level)
    local ctx = _manager_data.context_data
    if level == "session" then
        ctx.session_ctx = ctx.session_ctx + 1
    elseif level == "pause" then
        ctx.pause_ctx = ctx.pause_ctx + 1
    elseif level == "thread" then
        ctx.thread_ctx = ctx.thread_ctx + 1
    elseif level == "frame" then
        ctx.frame_ctx = ctx.frame_ctx + 1
    end
end

---Checks if the context snapshot matches the current state.
---@param ctx loopdebug.mgr.ContextData The snapshot to check
---@param level "session"|"pause"|"thread"|"frame" The level of granularity to check
---@return boolean
local function _is_current_context(ctx, level)
    local cur_ctx = _manager_data.context_data

    if level == "session" then
        return ctx.session_ctx == cur_ctx.session_ctx
    elseif level == "pause" then
        return ctx.session_ctx == cur_ctx.session_ctx
            and ctx.pause_ctx == cur_ctx.pause_ctx
    elseif level == "thread" then
        return ctx.session_ctx == cur_ctx.session_ctx
            and ctx.pause_ctx == cur_ctx.pause_ctx
            and ctx.thread_ctx == cur_ctx.thread_ctx
    elseif level == "frame" then
        return ctx.session_ctx == cur_ctx.session_ctx
            and ctx.pause_ctx == cur_ctx.pause_ctx
            and ctx.thread_ctx == cur_ctx.thread_ctx
            and ctx.frame_ctx == cur_ctx.frame_ctx
    end
    return false
end

-- =============================================================================
-- Reporting & Internal State Setters
-- =============================================================================

---Reports the full view state to the UI (debugevents).
---@param trigger loopdebug.events.ViewUpdateTrigger
local function _report_current_view(trigger)
    local mgr_data = _manager_data
    local sess_id = mgr_data.current_session_id
    local sess_data = sess_id and mgr_data.session_data[sess_id] or nil

    mgr_data.view_update_seq = mgr_data.view_update_seq + 1
    local seq = mgr_data.view_update_seq

    if not sess_data then
        debugevents.report_view_update({
            sequence = seq,
            trigger = trigger,
        })
        return
    end

    debugevents.report_view_update({
        sequence = seq,
        trigger = trigger,
        session_id = sess_id,
        session_name = sess_data.sess_name,
        data_providers = sess_data.data_providers,
        thread_id = sess_data.cur_thread_id,
        frame = sess_data.cur_frame,
        spurious_pause = sess_data.spurious_pause,
    })
end

---Reports a session status update (e.g., paused/running state).
---@param sess_id number
local function _report_session_update(sess_id)
    local mgr_data = _manager_data
    local sess_data = sess_id and mgr_data.session_data[sess_id] or nil
    if not sess_data then return end

    local state = sess_data.state or "starting"
    local is_paused = sess_data.all_threads_paused or next(sess_data.paused_threads) ~= nil
    local nb_paused_threads
    if is_paused and not sess_data.all_threads_paused then
        vim.tbl_count(sess_data.paused_threads)
    end
    debugevents.report_session_update(sess_id, {
        name = sess_data.sess_name,
        data_providers = sess_data.data_providers,
        state = state,
        is_paused = is_paused,
        nb_paused_threads = nb_paused_threads
    })
end

---Internal helper: Sets the current frame without triggering side effects.
---@param frame loopdebug.proto.StackFrame?
local function _set_frame_silent(frame)
    local mgr_data = _manager_data
    local sess_id = mgr_data.current_session_id
    local sess_data = sess_id and mgr_data.session_data[sess_id]
    if not sess_data then return end

    _increment_context("frame")
    sess_data.cur_frame = frame
end

---Internal helper: Sets the current thread without triggering side effects.
---@param thread_id number?
local function _set_thread_silent(thread_id)
    local mgr_data = _manager_data
    local sess_data = mgr_data.session_data[mgr_data.current_session_id]
    if not sess_data then return end

    _increment_context("thread")
    sess_data.cur_thread_id = thread_id
    -- When thread changes, the frame is inherently invalidated
    _set_frame_silent(nil)
end

-- =============================================================================
-- Switching Logic (Refactored)
-- =============================================================================

---Switches the active frame and updates UI.
---@param frame loopdebug.proto.StackFrame?
---@param send_updates boolean If true, triggers a UI refresh
local function _switch_to_frame(frame, send_updates)
    _set_frame_silent(frame)
    if send_updates then _report_current_view("frame") end
end

---Switches the active thread, optionally fetches the stack, and updates UI.
---@param thread_id number?
---@param send_updates boolean
local function _switch_to_thread(thread_id, send_updates)
    local mgr_data = _manager_data
    local sess_data = mgr_data.session_data[_manager_data.current_session_id]
    if not sess_data then return end

    -- 1. Update internal state immediately
    _set_thread_silent(thread_id)

    -- 2. Report initial view (thread changed, frame empty)
    if send_updates then _report_current_view("thread") end

    if not thread_id or not sess_data then return end

    -- 3. Async Fetch: Get top stack frame
    local ctx = _get_context()
    sess_data.data_providers.stack_provider({ threadId = thread_id, levels = 1 }, function(err, data)
        -- Validate context hasn't changed while we were waiting
        if _is_current_context(ctx, "thread") then
            local topframe = data and data.stackFrames and data.stackFrames[1]
            if topframe then
                _set_frame_silent(topframe)
                _report_current_view("thread")
            end
        end
    end)
end

---Switches the active session and handles thread synchronization on pause.
---@param sess_id number?
---@param thread_id number?
local function _switch_to_session(sess_id, thread_id)
    _increment_context("session")

    local mgr_data = _manager_data
    local sess_data = sess_id and mgr_data.session_data[sess_id] or nil
    if not sess_data then
        mgr_data.current_session_id = nil
        _report_current_view("session")
        return
    end

    mgr_data.current_session_id = sess_id
    _switch_to_thread(thread_id or sess_data.cur_thread_id, true)
end

-- =============================================================================
-- Event Handlers
-- =============================================================================

---@param sess_id number
---@param sess_name string
---@param parent_id number|nil
---@param controller loop.job.DebugJob.SessionController
---@param data_providers loopdebug.session.DataProviders
function M.add_session(sess_id,
                       sess_name,
                       parent_id,
                       controller,
                       data_providers)
    assert(not _manager_data.session_data[sess_id])

    if next(_manager_data.session_data) == nil then
        debugevents.report_debug_start()
    end

    debugevents.report_session_added(sess_id, {
        name = sess_name,
        data_providers = data_providers,
        state = "starting",
        is_paused = false,
    })

    ---@type loopdebug.mgr.SessionData
    local session_data = {
        sess_name = sess_name,
        controller = controller,
        data_providers = data_providers,
        all_threads_paused = false,
        spurious_pause = false,
        paused_threads = {},
    }

    _manager_data.session_data[sess_id] = session_data

    -- If this is the first session, select it automatically
    if not _manager_data.current_session_id then
        _manager_data.current_session_id = sess_id
    end
end

---@param sess_id number
---@param sess_name string
function M.remove_session(sess_id, sess_name)
    _manager_data.session_data[sess_id] = nil
    debugevents.report_session_removed(sess_id)
    if _manager_data.current_session_id == sess_id then
        _switch_to_session(nil)
    end
    if next(_manager_data.session_data) == nil then
        debugevents.report_debug_end()
    end
end

---@param sess_id number
---@param sess_name string
---@param data loopdebug.session.notify.StateData
function M.on_session_state_update(sess_id, sess_name, data)
    local mgr_data = _manager_data
    local session_data = mgr_data.session_data[sess_id]
    if not session_data then return end

    session_data.state = data.state
    _report_session_update(sess_id)

    if data.state == "ended" then
        session_data.cur_thread_id = nil
        session_data.cur_frame = nil
        if mgr_data.current_session_id == sess_id then
            _switch_to_session(nil)
        end
    end
end

---@param sess_id number
---@param sess_name string
---@param event_data loopdebug.session.notify.ThreadsEventScope
function M.on_session_thread_pause(sess_id, sess_name, event_data)
    local sess_data = _manager_data.session_data[sess_id]
    if not sess_data then return end
    -- If the adapter says 'all stopped', we can assume the whole process is halted
    if event_data.all_threads then
        sess_data.all_threads_paused = true
    end
    -- Always track the specific thread that hit the signal
    if event_data.thread_id then
        sess_data.paused_threads[event_data.thread_id] = true
    end
    local is_spurious = daptools.is_spurious_stop(event_data.reason)
    sess_data.spurious_pause = is_spurious
    _report_session_update(sess_id)
    _switch_to_session(sess_id, event_data.thread_id)
end

---@param sess_id number
---@param sess_name string
---@param event_data loopdebug.session.notify.ThreadsEventScope
function M.on_session_thread_continue(sess_id, sess_name, event_data)
    local mgr_data = _manager_data
    local sess_data = mgr_data.session_data[sess_id]
    if not sess_data then return end

    if event_data.all_threads then
        -- Hard Reset: Everything is moving
        sess_data.all_threads_paused = false
        sess_data.paused_threads = {}
    else
        -- Single thread continued
        sess_data.paused_threads[event_data.thread_id] = nil
        -- If a single thread starts, 'all_threads_paused' cannot logically remain true.
        sess_data.all_threads_paused = false
    end
    -- Handle UI Context Invalidation
    if sess_id == mgr_data.current_session_id then
        -- If the thread we were looking at is the one that started moving...
        if event_data.all_threads or event_data.thread_id == sess_data.cur_thread_id then
            _increment_context("pause")  -- Kill pending async requests
            _switch_to_thread(nil, true) -- Clear the view
        end
    end
    _report_session_update(sess_id)
end

---@param sess_id number
---@param sess_name string
function M.on_session_variable_change(sess_id, sess_name)
    if _manager_data.current_session_id ~= sess_id then return end
    -- force the trackers to refresh
    _report_current_view("variable")
end

---@param sess_id number
---@param event loopdebug.session.notify.BreakpointsEvent
function M.on_breakpoint_event(sess_id, event)
    debugevents.report_breakpoints_update(sess_id, event)
end

-- =============================================================================
-- Command Processors
-- =============================================================================

---@return boolean, string|nil
local function _process_continue_all_command()
    local mgr_data = _manager_data
    for _, session_data in pairs(mgr_data.session_data) do
        if session_data.cur_thread_id then
            session_data.controller.continue(session_data.cur_thread_id, true)
        end
    end
    return true
end

---@return boolean, string|nil
local function _process_terminate_all_command()
    local mgr_data = _manager_data
    for _, session_data in pairs(mgr_data.session_data) do
        session_data.controller.terminate()
    end
    return true
end

---@return boolean, string|nil
local function _process_select_session_command()
    local mgr_data = _manager_data
    local choices = {}
    local initial
    local ids = vim.tbl_keys(mgr_data.session_data)
    vim.fn.sort(ids)
    for _, sess_id in ipairs(ids) do
        local sess_data = mgr_data.session_data[sess_id]
        table.insert(choices, { label = sess_data.sess_name, data = sess_id })
        if sess_id == mgr_data.current_session_id then
            initial = #choices
        end
    end
    selector.select({
            prompt = "Select debug session",
            items = choices,
            initial = initial,
        },
        function(sess_id)
            if sess_id then _switch_to_session(sess_id) end
        end
    )
    return true
end

---@return boolean, string|nil
local function _process_select_thread_command()
    local mgr_data = _manager_data
    local sess_id = mgr_data.current_session_id
    local sess_data = sess_id and mgr_data.session_data[sess_id] or nil
    if not sess_id or not sess_data then return false, "No active debug session" end

    local ctx = _get_context()
    sess_data.data_providers.threads_provider(function(err, data)
        if _is_current_context(ctx, "pause") then
            if err or not data or not data.threads then
                vim.notify("Failed to load thread list: " .. (err or ""))
            else
                local choices = {}
                local initial
                for _, thread in pairs(data.threads) do
                    table.insert(choices, {
                        label = tostring(thread.id) .. ": " .. tostring(thread.name),
                        data = thread.id
                    })
                    if thread.id == sess_data.cur_thread_id then
                        initial = #choices
                    end
                end
                selector.select({
                        prompt = "Select thread",
                        items = choices,
                        initial = initial,
                    },
                    function(thread_id)
                        if thread_id and sess_id == mgr_data.current_session_id then
                            _switch_to_thread(thread_id, true)
                        end
                    end
                )
            end
        end
    end)
    return true
end

---@return boolean, string|nil
local function _process_select_frame_command()
    local mgr_data = _manager_data
    local sess_id = mgr_data.current_session_id
    local sess_data = sess_id and mgr_data.session_data[sess_id] or nil
    if not sess_data then return false, "No active debug session" end

    local thread_id = sess_data.cur_thread_id
    if not thread_id then return false, "No selected thread" end

    local ctx = _get_context()
    sess_data.data_providers.stack_provider({ threadId = thread_id }, function(err, data)
        if _is_current_context(ctx, "thread") then
            if err or not data then
                vim.notify("Failed to load call stack: " .. (err or ""))
            else
                ---@type loop.SelectorItem[]
                local choices = {}
                local initial
                for _, frame in pairs(data.stackFrames) do
                    table.insert(choices,
                        ---@type loop.SelectorItem
                        {
                            label = frame.name,
                            file = frame.source and frame.source.path,
                            lnum = frame.source and frame.line,
                            data = frame
                        })
                    if sess_data.cur_frame and frame.id == sess_data.cur_frame.id then
                        initial = #choices
                    end
                end
                if not initial then
                    for idx, frame in pairs(data.stackFrames) do
                        if sess_data.cur_frame and frame.name == sess_data.cur_frame.name
                            and frame.moduleId == sess_data.cur_frame.moduleId
                            and frame.line == sess_data.cur_frame.line then
                            initial = idx
                        end
                    end
                end
                selector.select({
                        prompt = "Select frame",
                        items = choices,
                        initial = initial,
                        file_preview = true,
                        list_wrap = false,
                    },
                    function(frame)
                        if frame and sess_id == mgr_data.current_session_id and thread_id == sess_data.cur_thread_id then
                            _switch_to_frame(frame, true)
                        end
                    end
                )
            end
        end
    end)
    return true
end

---@diagnostic disable-next-line: undefined-doc-name
---@param opts vim.api.keyset.create_user_command.command_args
local function _process_inspect_var_command(opts)
    local mgr_data = _manager_data
    local sess_id = mgr_data.current_session_id
    local sess_data = sess_id and mgr_data.session_data[sess_id] or nil
    if not sess_data then return false, "No active debug session" end

    local dbgtools = require('loop-debug.tools.dbgtools')
    local expr, expr_err = dbgtools.get_value_for_inspect(opts)
    if not expr then
        if expr_err then vim.notify(expr_err, vim.log.levels.WARN) end
        return
    end

    local frame = sess_data.cur_frame
    local ctx = _get_context()

    sess_data.data_providers.evaluate_provider({
        expression = expr,
        context = "watch",
        frameId = frame and frame.id or nil
    }, function(err, data)
        if _is_current_context(ctx, "frame") then
            if data and data.result then
                local title = data.type and (expr .. ' - ' .. data.type) or expr
                floatwin.show_floatwin(daptools.format_variable(data.result, data.presentationHint), {
                    title = title
                })
            else
                local text = ("%s\n\n:%s"):format(expr, err or "not available")
                floatwin.show_floatwin(text, { title = "Error" })
            end
        end
    end)
end

---@param command loop.job.DebugJob.Command|nil
---@param args string[]
---@param opts vim.api.keyset.create_user_command.command_args
---@param wsdir string
function M.debug_command(command, args, opts, wsdir)
    if command == "breakpoint" then
        local bp_cmd = args[2]
        if bp_cmd == "list" then
            breakpoints.select_breakpoint(wsdir)
        else
            breakpoints.breakpoints_command(bp_cmd)
        end
        return
    end

    local mgr_data = _manager_data
    if not mgr_data then
        vim.notify("No active debug task", vim.log.levels.WARN)
        return
    end

    if not command then return end

    -- Dispatch commands
    if command == 'continue_all' then
        _process_continue_all_command(); return
    end
    if command == 'terminate_all' then
        _process_terminate_all_command(); return
    end
    if command == "session" then
        _process_select_session_command(); return
    end
    if command == "thread" then
        _process_select_thread_command(); return
    end
    if command == "frame" then
        _process_select_frame_command(); return
    end
    if command == "inspect" then
        _process_inspect_var_command(opts); return
    end

    local sess_id = mgr_data.current_session_id
    local sess_data = sess_id and mgr_data.session_data[sess_id]
    if not sess_data then
        vim.notify("No active debug session", vim.log.levels.WARN); return
    end

    if command == 'pause' then
        sess_data.controller.pause(sess_data.cur_thread_id or 0); return
    end

    if command == 'terminate' then
        sess_data.controller.terminate(); return
    end

    if not sess_data.cur_thread_id then
        vim.notify("No thread selected", vim.log.levels.WARN); return
    end

    local step_map = {
        continue = "continue",
        step_in = "step_in",
        step_out = "step_out",
        step_over = "step_over",
        step_back = "step_back"
    }
    if step_map[command] then
        -- Passing 'true' to continue usually implies reverse continue in some adapters,
        -- but strictly standard DAP uses separate reqs. Assuming loop controller handles it.
        sess_data.controller[command](sess_data.cur_thread_id, command == 'continue')
    else
        vim.notify("Invalid debug command: " .. tostring(command), vim.log.levels.WARN)
    end
end

return M
