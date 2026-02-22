local config      = require('loop-debug.config')
local loopsigns   = require('loop.signs')
local debugevents = require('loop-debug.debugevents')
local selector    = require("loop.tools.selector")
local uitools     = require("loop.tools.uitools")
local persistence = require('loop-debug.persistence')
local floatwin    = require('loop.tools.floatwin')

---@class loop.debug_ui.BreakpointSignData
---@field breakpoint loopdebug.SourceBreakpoint
---@field states table<number, boolean>?

---@class loop.debug_ui.Module
local M           = {}

local _init_done  = false

---@type loop.signs.Group
local _sign_group

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

local function _format_breakpoint(bp, verified, wsdir)
    local symbols = config.current.symbols
    assert(symbols)

    local symbol
    if bp.enabled == false then
        if bp.logMessage and bp.logMessage ~= "" then
            symbol = symbols.disabled_logpoint
        elseif bp.condition and bp.condition ~= "" or bp.hitCondition and bp.hitCondition ~= "" then
            symbol = symbols.disabled_cond_breakpoint
        else
            symbol = symbols.disabled_breakpoint
        end
    else
        -- Enabled breakpoints
        if bp.logMessage and bp.logMessage ~= "" then
            symbol = verified and symbols.logpoint or symbols.inactive_logpoint
        elseif bp.condition and bp.condition ~= "" or bp.hitCondition and bp.hitCondition ~= "" then
            symbol = verified and symbols.cond_breakpoint or symbols.inactive_cond_breakpoint
        else
            symbol = verified and symbols.active_breakpoint or symbols.inactive_breakpoint
        end
    end

    local file = bp.file
    file = vim.fs.relpath(wsdir, file) or file
    local parts = { symbol }
    table.insert(parts, " ")
    table.insert(parts, file)
    table.insert(parts, ":")
    table.insert(parts, tostring(bp.line))

    if bp.condition and bp.condition ~= "" then
        table.insert(parts, " | if " .. bp.condition)
    end
    if bp.hitCondition and bp.hitCondition ~= "" then
        table.insert(parts, " | hits: " .. bp.hitCondition)
    end
    if bp.logMessage and bp.logMessage ~= "" then
        table.insert(parts, " | log: " .. bp.logMessage:gsub("\n", " "))
    end
    return table.concat(parts, '')
end

-- ===================================================================
-- Helpers
-- ===================================================================

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

---@param bp loopdebug.SourceBreakpoint
---@param verified boolean
---@return string
local function _get_breakpoint_sign(bp, verified)
    if bp.enabled == false then
        if bp.logMessage and bp.logMessage ~= "" then
            return _sign_names.disabled_logpoint
        elseif (bp.condition and bp.condition ~= "")
            or (bp.hitCondition and bp.hitCondition ~= "") then
            return _sign_names.disabled_cond_breakpoint
        else
            return _sign_names.disabled_breakpoint
        end
    end

    if bp.logMessage and bp.logMessage ~= "" then
        return verified and _sign_names.logpoint
            or _sign_names.inactive_logpoint
    elseif (bp.condition and bp.condition ~= "")
        or (bp.hitCondition and bp.hitCondition ~= "") then
        return verified and _sign_names.cond_breakpoint
            or _sign_names.inactive_cond_breakpoint
    else
        return verified and _sign_names.active_breakpoint
            or _sign_names.inactive_breakpoint
    end
end

---@param sign loop.signs.Sign
local function _update_sign_from_data(sign)
    ---@type loop.debug_ui.BreakpointSignData?
    local data = sign.user_data
    if not data then
        return
    end

    local verified = _get_breakpoint_state(data)
    local name = _get_breakpoint_sign(data.breakpoint, verified)

    _sign_group.set_file_sign(
        sign.id,
        sign.file,
        sign.lnum,
        name,
        data
    )
end

-- ===================================================================
-- Breakpoint Events
-- ===================================================================

---@param bp loopdebug.SourceBreakpoint
local function _set_breakpoint(bp)
    ---@type loop.debug_ui.BreakpointSignData
    local data = {
        breakpoint = bp,
        states = {},
    }

    local name = _get_breakpoint_sign(bp, true)

    _sign_group.set_file_sign(
        bp.id,
        bp.file,
        bp.line,
        name,
        data
    )
end

---@param bp loopdebug.SourceBreakpoint
local function _on_breakpoint_enabled(bp)
    local sign = _sign_group.get_sign_by_id(bp.id)
    if not sign then
        return
    end

    ---@type loop.debug_ui.BreakpointSignData
    local data = sign.user_data
    data.breakpoint = bp

    _update_sign_from_data(sign)
end

---@param bp loopdebug.SourceBreakpoint
local function _on_breakpoint_disabled(bp)
    _on_breakpoint_enabled(bp)
end

---@param bp loopdebug.SourceBreakpoint
local function _on_breakpoint_removed(bp)
    _sign_group.remove_file_sign(bp.id)
end

local function _on_all_breakpoints_removed()
    _sign_group.remove_signs()
end

-- ===================================================================
-- Session Events
-- ===================================================================

---@param id number
local function _on_session_added(id)
    for _, sign in ipairs(_sign_group.get_signs(true)) do
        ---@type loop.debug_ui.BreakpointSignData?
        local data = sign.user_data
        if data then
            data.states = data.states or {}
            data.states[id] = false
            _update_sign_from_data(sign)
        end
    end
end

---@param id number
local function _on_session_removed(id)
    for _, sign in ipairs(_sign_group.get_signs(true)) do
        ---@type loop.debug_ui.BreakpointSignData?
        local data = sign.user_data
        if data and data.states then
            data.states[id] = nil
            _update_sign_from_data(sign)
        end
    end
end

---@param sess_id number
---@param event loopdebug.session.notify.BreakpointState[]
local function _on_breakpoints_update(sess_id, event)
    for _, state in ipairs(event) do
        local sign = _sign_group.get_sign_by_id(state.breakpoint_id)
        if sign then
            ---@type loop.debug_ui.BreakpointSignData?
            local data = sign.user_data
            if data then
                data.states = data.states or {}
                data.states[sess_id] = state.verified
                _update_sign_from_data(sign)
            end
        end
    end
end

-- ===================================================================
-- Breakpoint Selector
-- ===================================================================

---@return loopdebug.SourceBreakpoint[]
function M.get_breakpoints()
    local signs = _sign_group.get_signs(true)
    ---@type loopdebug.SourceBreakpoint[]
    local bpts = {}
    for _, sign in pairs(signs) do
        ---@type loop.debug_ui.BreakpointSignData
        local data = sign.user_data
        table.insert(bpts, data.breakpoint)
    end
    return bpts
end

---@param ws_dir string
function M.select_breakpoint(ws_dir)
    if not ws_dir then
        vim.notify('No active workspace')
        return
    end

    ---@type table[]
    local choices = {}

    for _, sign in ipairs(_sign_group.get_signs(true)) do
        ---@type loop.debug_ui.BreakpointSignData?
        local data = sign.user_data
        if data then
            local bp = data.breakpoint
            local verified = _get_breakpoint_state(data)

            local file = vim.fs.relpath(ws_dir, bp.file) or bp.file
            local label = string.format(
                "%s %s:%d",
                config.current.symbols[_get_breakpoint_sign(bp, verified)],
                file,
                bp.line
            )

            table.insert(choices, {
                label = _format_breakpoint(bp, verified, ws_dir),
                file = bp.file,
                line = bp.line,
                data = bp,
            })
        end
    end

    if #choices == 0 then
        vim.notify('No existing breakpoints')
        return
    end

    table.sort(choices, function(a, b)
        if a.file ~= b.file then
            return a.file < b.file
        end
        return a.line < b.line
    end)

    selector.select({
        prompt = "Breakpoints",
        items = choices,
        file_preview = true,
        callback = function(bp)
            ---@cast bp loopdebug.SourceBreakpoint
            if bp and bp.file then
                uitools.smart_open_file(bp.file, bp.line, bp.column)
            end
        end
    })
end

---@param breakpoints loopdebug.SourceBreakpoint[]
local function _set_breakpoints(breakpoints)
    _sign_group.remove_signs()

    table.sort(breakpoints, function(a, b)
        if a.file ~= b.file then return a.file < b.file end
        return a.line < b.line
    end)

    for _, bp in ipairs(breakpoints) do
        _set_breakpoint(bp)
    end

    return true, nil
end


---@param command nil
---| "toggle"
---| "logpoint"
---| "conditional"
---| "enable"
---| "disable"
---| "toggle_enabled"
---| "enable_all"
---| "disable_all"
---| "clear_file"
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
            _disable_breakpoint(file, line)
        end
    elseif command == "enable" then
        local file, line = uitools.get_current_file_and_line()
        if file and line then
            _enable_breakpoint(file, line)
        end
    elseif command == "toggle_enabled" then
        local file, line = uitools.get_current_file_and_line()
        if file and line then
            _toggle_breakpoint_enabled(file, line)
        end
    elseif command == "disable_all" then
        uitools.confirm_action("Disable all breakpoints", false, function(accepted)
            if accepted == true then
                _disable_all_breakpoints()
            end
        end)
    elseif command == "enable_all" then
        uitools.confirm_action("Enable all breakpoints", false, function(accepted)
            if accepted == true then
                _enable_all_breakpoints()
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

-- ===================================================================
-- Init
-- ===================================================================

function M.init()
    if _init_done then
        return
    end
    _init_done = true

    local highlight = "LoopDebugBreakpoint"
    vim.api.nvim_set_hl(0, highlight, { link = "Debug" })

    _sign_group = loopsigns.define_group("Breakpoints", {
        priority = config.current.sign_priority.breakpoints
    })

    local symbols = config.current.symbols
    assert(symbols)

    for name, full_name in pairs(_sign_names) do
        _sign_group.define_sign(full_name, symbols[name], highlight)
    end

    persistence.add_tracker({
        on_ws_load = function()
            _set_breakpoints(persistence.get_config("breakpoints") or {})
        end,
        on_ws_unload = function()
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
