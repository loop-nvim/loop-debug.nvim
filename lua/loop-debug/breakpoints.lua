---@module "loop.debug_ui.breakpoints"

local Trackers    = require("loop.tools.Trackers")
local config      = require('loop-debug.config')
local loopsigns   = require('loop.signs')
local debugevents = require('loop-debug.debugevents')
local selector    = require("loop.tools.selector")
local uitools     = require("loop.tools.uitools")
local persistence = require('loop-debug.persistence')
local floatwin    = require('loop.tools.floatwin')

---@class loop.debug_ui.BreakpointSignData
---@field column integer|nil
---@field condition string|nil
---@field hitCondition string|nil
---@field logMessage string|nil
---@field enabled boolean
---@field states table<number, boolean>|nil

---@class loopdebug.SourceBreakpoint
---@field id number
---@field file string
---@field line integer
---@field column integer|nil
---@field condition string|nil
---@field hitCondition string|nil
---@field logMessage string|nil
---@field enabled boolean

---@class loopdebug.breakpoints.Tracker
---@field on_update fun(bp:loopdebug.SourceBreakpoint)|nil
---@field on_removed fun(bp:loopdebug.SourceBreakpoint)|nil
---@field on_all_removed fun(bpts:loopdebug.SourceBreakpoint[])|nil

---@class loop.debug_ui.Module
local M           = {}

---@type boolean
local _init_done  = false

---@type loop.tools.Trackers<loopdebug.breakpoints.Tracker>
local _trackers   = Trackers:new()

---@type loop.signs.Group
local _sign_group

---@type integer
local _id_counter = 0

---@type table<string, string>
local _sign_names = {
    active_breakpoint        = "active_breakpoint",
    inactive_breakpoint      = "inactive_breakpoint",
    logpoint                 = "logpoint",
    inactive_logpoint        = "inactive_logpoint",
    cond_breakpoint          = "cond_breakpoint",
    inactive_cond_breakpoint = "inactive_cond_breakpoint",
    disabled_breakpoint      = "disabled_breakpoint",
    disabled_logpoint        = "disabled_logpoint",
    disabled_cond_breakpoint = "disabled_cond_breakpoint",
}

-- ===================================================================
-- ID Management
-- ===================================================================

---@return integer
local function _next_breakpoint_id()
    _id_counter = _id_counter + 1
    return _id_counter
end

-- ===================================================================
-- State + Sign Logic
-- ===================================================================

---@param sign loop.signs.SignInfo
---@return loopdebug.SourceBreakpoint
local function _sign_info_to_source_breakpoint(sign)
    ---@type loop.debug_ui.BreakpointSignData
    local data = sign.user_data
    return
    {
        id = sign.id,
        file = sign.file,
        line = sign.lnum,
        column = data.column,
        condition = data.condition,
        hitCondition = data.hitCondition,
        logMessage = data.logMessage,
        enabled = data.enabled,
    }
end

---@param data loop.debug_ui.BreakpointSignData
---@return boolean
local function _get_breakpoint_state(data)
    local verified = nil

    if data.states then
        for _, state in pairs(data.states) do
            verified = verified or state
        end
    end

    if verified == nil then
        verified = true
    end

    return verified
end

---@param data loop.debug_ui.BreakpointSignData
---@param verified boolean
---@return string
local function _get_breakpoint_sign(data, verified)
    if data.enabled == false then
        if data.logMessage and data.logMessage ~= "" then
            return _sign_names.disabled_logpoint
        elseif (data.condition and data.condition ~= "")
            or (data.hitCondition and data.hitCondition ~= "") then
            return _sign_names.disabled_cond_breakpoint
        else
            return _sign_names.disabled_breakpoint
        end
    end

    if data.logMessage and data.logMessage ~= "" then
        return verified and _sign_names.logpoint
            or _sign_names.inactive_logpoint
    elseif (data.condition and data.condition ~= "")
        or (data.hitCondition and data.hitCondition ~= "") then
        return verified and _sign_names.cond_breakpoint
            or _sign_names.inactive_cond_breakpoint
    else
        return verified and _sign_names.active_breakpoint
            or _sign_names.inactive_breakpoint
    end
end

---@param sign loop.signs.SignInfo
local function _update_sign(sign)
    ---@type loop.debug_ui.BreakpointSignData
    local data = sign.user_data
    if not data then return end

    local verified = _get_breakpoint_state(data)
    local name = _get_breakpoint_sign(data, verified)

    if sign.name == name then
        return
    end

    _sign_group.set_file_sign(sign.id, sign.file, sign.lnum, name, data)
end

---@param file string
---@param line integer
---@return loop.signs.SignInfo|nil
local function _get_sign_at(file, line)
    return _sign_group.get_sign_by_location(file, line, true)
end

-- ===================================================================
-- Breakpoint Creation
-- ===================================================================

---@param id integer
---@param file string
---@param line integer
---@param data loop.debug_ui.BreakpointSignData
local function _set_breakpoint(id, file, line, data)
    local name = _get_breakpoint_sign(data, true)
    _sign_group.set_file_sign(id, file, line, name, data)
    local sign = _sign_group.get_sign_by_id(id)
    assert(sign)
    _trackers:invoke("on_update", _sign_info_to_source_breakpoint(sign))
end

---@param file string
---@param line integer
local function _delete_breakpoint(file, line)
    local sign = _get_sign_at(file, line)
    if not sign then return end
    _sign_group.remove_file_sign(sign.id)
    _trackers:invoke("on_removed", _sign_info_to_source_breakpoint(sign))
end

---@param file string
local function _clear_file_breakpoints(file)
    _sign_group.remove_file_signs(file)
    local signs = _sign_group.get_file_signs(file, true)
    for _, sign in ipairs(signs) do
        _trackers:invoke("on_removed", _sign_info_to_source_breakpoint(sign))
    end
end

---@return nil
local function _clear_all_breakpoints()
    _sign_group.remove_signs()
    _trackers:invoke("on_all_removed");
end

---@param file string
---@param line integer
local function _set_normal_breakpoint(file, line)
    local existing = _get_sign_at(file, line)
    if existing then
        _delete_breakpoint(file, line)
    end
    _set_breakpoint(_next_breakpoint_id(), file, line, {
        enabled = true
    })
end

---@param file string
---@param line integer
---@param message string
local function _set_logpoint(file, line, message)
    local existing = _get_sign_at(file, line)
    if existing then
        _sign_group.remove_file_sign(existing.id)
    end

    _set_breakpoint(_next_breakpoint_id(), file, line, {
        enabled = true,
        logMessage = message
    })
end

---@param file string
---@param line integer
---@param cond string|nil
---@param hit string|nil
local function _set_cond_breakpoint(file, line, cond, hit)
    local existing = _get_sign_at(file, line)
    if existing then
        _sign_group.remove_file_sign(existing.id)
    end

    _set_breakpoint(_next_breakpoint_id(), file, line, {
        enabled = true,
        condition = cond,
        hitCondition = hit
    })
end

-- ===================================================================
-- Enable / Disable
-- ===================================================================

---@param file string
---@param line integer
---@param value boolean
local function _set_enabled(file, line, value)
    local sign = _get_sign_at(file, line)
    if not sign then return end

    ---@type loop.debug_ui.BreakpointSignData
    local data = sign.user_data

    data.enabled = value
    _update_sign(sign)
end

---@param file string
---@param line integer
local function _toggle_enabled(file, line)
    local sign = _get_sign_at(file, line)
    if not sign then return end

    ---@type loop.debug_ui.BreakpointSignData
    local data = sign.user_data

    data.enabled = not (data.enabled == true)
    _update_sign(sign)

    _trackers:invoke("on_update", _sign_info_to_source_breakpoint(sign))
end

---@param value boolean
local function _set_all_enabled(value)
    for _, sign in ipairs(_sign_group.get_signs(true)) do
        ---@type loop.debug_ui.BreakpointSignData
        local data = sign.user_data
        data.enabled = value
        _update_sign(sign)

        _trackers:invoke("on_update", _sign_info_to_source_breakpoint(sign))
    end
end

-- ===================================================================
-- Session Events
-- ===================================================================

---@param id integer
local function _on_session_added(id)
    for _, sign in ipairs(_sign_group.get_signs(true)) do
        ---@type loop.debug_ui.BreakpointSignData
        local data = sign.user_data
        data.states = data.states or {}
        data.states[id] = false
        _update_sign(sign)
    end
end

---@param id integer
local function _on_session_removed(id)
    for _, sign in ipairs(_sign_group.get_signs(true)) do
        ---@type loop.debug_ui.BreakpointSignData
        local data = sign.user_data
        if data.states then
            data.states[id] = nil
            _update_sign(sign)
        end
    end
end

---@param sess_id integer
---@param event loopdebug.session.notify.BreakpointState[]
local function _on_breakpoints_update(sess_id, event)
    for _, state in ipairs(event) do
        local sign = _sign_group.get_sign_by_id(state.breakpoint_id)
        if sign then
            ---@type loop.debug_ui.BreakpointSignData
            local data = sign.user_data
            data.states = data.states or {}
            data.states[sess_id] = state.verified
            _update_sign(sign)
        end
    end
end

-- ===================================================================
-- Public API
-- ===================================================================

---@param callbacks loopdebug.breakpoints.Tracker
---@param no_snapshot boolean?
---@return loop.TrackerRef
function M.add_tracker(callbacks, no_snapshot)
    local tracker_ref = _trackers:add_tracker(callbacks)
    if not no_snapshot then
        if callbacks.on_update then
            local signs = _sign_group.get_signs(true)
            for _, sign in ipairs(signs) do
                local bp = _sign_info_to_source_breakpoint(sign)
                callbacks.on_update(bp)
            end
        end
    end
    return tracker_ref
end

---@return loopdebug.SourceBreakpoint[]
function M.get_breakpoints()
    local result = {}

    for _, sign in ipairs(_sign_group.get_signs(true)) do
        table.insert(result, _sign_info_to_source_breakpoint(sign))
    end

    return result
end

---@param command nil
---| "set"
---| "logpoint"
---| "conditional"
---| "enable"
---| "disable"
---| "toggle_enabled"
---| "enable_all"
---| "disable_all"
---| "delete"
---| "disable_all"
---| "clear_all"
function M.breakpoints_command(command)
    command = command and command:match("^%s*(.-)%s*$") or ""
    if command == "" or command == "set" then
        local file, line = uitools.get_current_file_and_line()
        if file and line then
            _set_normal_breakpoint(file, line)
        end
    elseif command == "logpoint" then
        local file, line = uitools.get_current_file_and_line()
        if file and line then
            floatwin.input_at_cursor({ prompt = "Enter log message: " }, function(message)
                if message and message ~= "" then
                    _set_logpoint(file, line, message)
                    print("Logpoint set at " .. file .. ":" .. line)
                end
            end)
        end
    elseif command == "conditional" then
        local file, line = uitools.get_current_file_and_line()
        if file and line then
            floatwin.input_at_cursor({ prompt = "Condition (empty for none): " }, function(cond)
                if cond then
                    floatwin.input_at_cursor({ prompt = "Hit condition (empty for none): " }, function(hit)
                        if hit then
                            if cond == "" then cond = nil end
                            if hit == "" then hit = nil end
                            _set_cond_breakpoint(file, line, cond, hit)
                        end
                    end)
                end
            end)
        end
    elseif command == "disable" then
        local file, line = uitools.get_current_file_and_line()
        if file and line then
            _set_enabled(file, line, false)
        end
    elseif command == "enable" then
        local file, line = uitools.get_current_file_and_line()
        if file and line then
            _set_enabled(file, line, true)
        end
    elseif command == "toggle_enabled" then
        local file, line = uitools.get_current_file_and_line()
        if file and line then
            _toggle_enabled(file, line)
        end
    elseif command == "disable_all" then
        uitools.confirm_action("Disable all breakpoints", false, function(accepted)
            if accepted == true then
                _set_all_enabled(false)
            end
        end)
    elseif command == "enable_all" then
        uitools.confirm_action("Enable all breakpoints", false, function(accepted)
            if accepted == true then
                _set_all_enabled(true)
            end
        end)
    elseif command == "delete" then
        local file, line = uitools.get_current_file_and_line()
        if file and line then
            _delete_breakpoint(file, line)
        end
    elseif command == "clear_file" then
        local bufnr = vim.api.nvim_get_current_buf()
        if vim.api.nvim_buf_is_valid(bufnr) then
            local full_path = vim.api.nvim_buf_get_name(bufnr)
            if full_path and full_path ~= "" then
                uitools.confirm_action("Clear dapbreakpoints in file", false, function(accepted)
                    if accepted == true then
                        _clear_file_breakpoints(full_path)
                    end
                end)
            end
        end
    elseif command == "clear_all" then
        uitools.confirm_action("Clear all dapbreakpoints", false, function(accepted)
            if accepted == true then
                _clear_all_breakpoints()
            end
        end)
    else
        vim.notify('Invalid breakpoints subcommand: ' .. tostring(command))
    end
end

---@param ws_dir string
---@return nil
function M.select_breakpoint(ws_dir)
    if not ws_dir or ws_dir == "" then
        vim.notify('No active workspace')
        return
    end
    local symbols = config.current.symbols
    assert(symbols)

    -- ---------------------------------------------------------------
    -- Formatter: generate label_chunks with highlights
    -- ---------------------------------------------------------------
    ---@param sign loop.signs.SignInfo
    ---@return string[][] label_chunks, string[][][] virt_lines
    local function format_breakpoint_chunks(sign)
        ---@type loop.debug_ui.BreakpointSignData
        local data = sign.user_data
        local verified = _get_breakpoint_state(data)
        local symbol

        if data.enabled == false then
            if data.logMessage and data.logMessage ~= "" then
                symbol = symbols.disabled_logpoint
            elseif (data.condition and data.condition ~= "")
                or (data.hitCondition and data.hitCondition ~= "") then
                symbol = symbols.disabled_cond_breakpoint
            else
                symbol = symbols.disabled_breakpoint
            end
        else
            if data.logMessage and data.logMessage ~= "" then
                if verified then
                    symbol = symbols.logpoint
                else
                    symbol = symbols.inactive_logpoint
                end
            elseif (data.condition and data.condition ~= "")
                or (data.hitCondition and data.hitCondition ~= "") then
                if verified then
                    symbol = symbols.cond_breakpoint
                else
                    symbol = symbols.inactive_cond_breakpoint
                end
            else
                if verified then
                    symbol = symbols.active_breakpoint
                else
                    symbol = symbols.inactive_breakpoint
                end
            end
        end

        local rel = vim.fs.relpath(ws_dir, sign.file) or sign.file
        local text = (" %s:%s"):format(rel, tostring(sign.lnum))
        local label_chunks = {
            { symbol, "Debug" },
            { text,   nil },
        }

        local virt_lines = {}
        if data.condition and data.condition ~= "" then
            table.insert(virt_lines, { { "  Condition: ", "Conditional" }, { data.condition } })
        end
        if data.hitCondition and data.hitCondition ~= "" then
            table.insert(virt_lines, { { "  Hit condition: ", "Conditional" }, { data.hitCondition } })
        end
        if data.logMessage and data.logMessage ~= "" then
            local msg = data.logMessage:gsub("\n", " ")
            table.insert(virt_lines, { { "  Log: ", "Conditional" }, { msg } })
        end

        return label_chunks, virt_lines
    end

    -- ---------------------------------------------------------------
    -- Build selector items with label_chunks
    -- ---------------------------------------------------------------
    local cur_file, cur_lnum = uitools.get_current_file_and_line()
    local choices = {}

    for _, sign in ipairs(_sign_group.get_signs(true)) do
        local label_chunks, virt_lines = format_breakpoint_chunks(sign)
        table.insert(choices, {
            label_chunks = label_chunks, -- highlight-aware display
            virt_lines = virt_lines,
            file = sign.file,
            lnum = sign.lnum,
            data = {
                file = sign.file or "",
                lnum = sign.lnum or 1,
                column = sign.user_data.column,
                sign = sign
            }
        })
    end

    if #choices == 0 then
        vim.notify('No existing breakpoints')
        return
    end

    table.sort(choices, function(a, b)
        if a.file ~= b.file then
            return a.file < b.file
        end
        return a.lnum < b.lnum
    end)

    local initial
    for idx, choice in ipairs(choices) do
        if cur_file == choice.file and cur_lnum == choice.lnum then
            initial = idx
            break
        end
    end

    selector.select({
            prompt = "Breakpoints",
            items = choices,
            initial = initial,
            file_preview = true,
        },
        function(data)
            if data and data.file then
                uitools.smart_open_file(data.file, data.lnum, data.column)
            end
        end
    )
end

-- ===================================================================
-- Init
-- ===================================================================

---@return nil
function M.init()
    if _init_done then return end
    _init_done = true

    local highlight = "LoopDebugBreakpoint"
    vim.api.nvim_set_hl(0, highlight, { link = "Debug" })

    _sign_group = loopsigns.define_group("Breakpoints", {
        priority = config.current.sign_priority.breakpoints
    })

    for name, full_name in pairs(_sign_names) do
        _sign_group.define_sign(full_name, config.current.symbols[name], highlight)
    end

    persistence.add_tracker({
        on_ws_load = function()
            local bps = persistence.get_config("breakpoints") or {}
            _sign_group.remove_signs()
            _id_counter = 0

            for _, bp in ipairs(bps) do
                if bp.id > _id_counter then
                    _id_counter = bp.id
                end

                _set_breakpoint(bp.id, bp.file, bp.line, {
                    column = bp.column,
                    condition = bp.condition,
                    hitCondition = bp.hitCondition,
                    logMessage = bp.logMessage,
                    enabled = bp.enabled ~= false,
                })
            end
        end,
        on_ws_will_save = function()
            persistence.set_config("breakpoints", M.get_breakpoints())
        end
    })

    debugevents.add_tracker({
        on_session_added = _on_session_added,
        on_session_removed = _on_session_removed,
        on_breakpoints_update = _on_breakpoints_update,
    })
end

return M
