local config        = require('loop-debug.config')
local loopsigns     = require('loop.signs')
local breakpoints   = require('loop-debug.breakpoints')
local debugevents   = require('loop-debug.debugevents')
local selector      = require("loop.tools.selector")
local uitools       = require("loop.tools.uitools")

local M             = {}

local _init_done    = false
local _init_err_msg = "init() not called"

---@type loop.signs.Group
local _sign_group

local _sign_names   = {
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


---@class loop.debug_ui.Breakpointata
---@field breakpoint loopdebug.SourceBreakpoint
---@field states table<number,boolean>|nil

---@type table<number,loop.debug_ui.Breakpointata>
local _breakpoints_data = {}

---@param bp loopdebug.SourceBreakpoint
---@param verified boolean
---@param wsdir string
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
        table.insert(parts, " | hits=" .. bp.hitCondition)
    end
    if bp.logMessage and bp.logMessage ~= "" then
        table.insert(parts, " | log: " .. bp.logMessage:gsub("\n", " "))
    end
    return table.concat(parts, '')
end

---@param bp loopdebug.SourceBreakpoint
---@param verified boolean
---@return string
local function _get_breakpoint_sign(bp, verified)
    -- Disabled breakpoints
    if bp.enabled == false then
        if bp.logMessage then
            return _sign_names.disabled_logpoint
        elseif bp.condition or bp.hitCondition then
            return _sign_names.disabled_cond_breakpoint
        else
            return _sign_names.disabled_breakpoint
        end
    end

    -- Enabled breakpoints
    local active = verified

    if bp.logMessage then
        return active
            and _sign_names.logpoint
            or _sign_names.inactive_logpoint
    elseif bp.condition or bp.hitCondition then
        return active
            and _sign_names.cond_breakpoint
            or _sign_names.inactive_cond_breakpoint
    else
        return active
            and _sign_names.active_breakpoint
            or _sign_names.inactive_breakpoint
    end
end

---@param data loop.debug_ui.Breakpointata
---@@return boolean
local function _get_breakpoint_state(data)
    local verified = nil
    if data.states then
        for _, state in ipairs(data.states) do
            verified = verified or state
        end
    end
    if verified == nil then verified = true end
    return verified
end

---@param id number
---@param data loop.debug_ui.Breakpointata
local function _refresh_breakpoint_sign(id, data)
    local verified = _get_breakpoint_state(data)
    local sign = _get_breakpoint_sign(data.breakpoint, verified)
    _sign_group.place_file_sign(id, data.breakpoint.file, data.breakpoint.line, sign)
end

---@param bp loopdebug.SourceBreakpoint
local function _on_breakpoint_set(bp)
    _breakpoints_data[bp.id] = {
        breakpoint = bp,
    }
    local sign = _get_breakpoint_sign(bp, true)
    _sign_group.place_file_sign(bp.id, bp.file, bp.line, sign)
end

---@param bp loopdebug.SourceBreakpoint
local function _on_breakpoint_enabled(bp)
    local data = _breakpoints_data[bp.id]
    if data then
        _refresh_breakpoint_sign(bp.id, data)
    end
end

---@param bp loopdebug.SourceBreakpoint
local function _on_breakpoint_disabled(bp)
    local data = _breakpoints_data[bp.id]
    if data then
        _refresh_breakpoint_sign(bp.id, data)
    end
end

---@param bp loopdebug.SourceBreakpoint
---@param old_line number
local function _on_breakpoint_moved(bp, old_line)
    local data = _breakpoints_data[bp.id]
    if not data then
        return
    end

    -- Sign is already moved by Neovim; just refresh its appearance
    _refresh_breakpoint_sign(bp.id, data)
end

---@param bp loopdebug.SourceBreakpoint
local function _on_breakpoint_removed(bp)
    _breakpoints_data[bp.id] = nil
    _sign_group.remove_file_sign(bp.id)
end

---@param removed loopdebug.SourceBreakpoint[]
local function _on_all_breakpoints_removed(removed)
    _breakpoints_data = {}
    local files = {}
    for _, bp in ipairs(removed) do
        files[bp.file] = true
    end
    for file, _ in pairs(files) do
        _sign_group.remove_file_signs(file)
    end
end

---@param id number
local function _on_session_added(id)
    for bp_id, data in pairs(_breakpoints_data) do
        data.states = data.states or {}
        data.states[id] = false
        _refresh_breakpoint_sign(bp_id, data)
    end
end

---@param id number
local function _on_session_removed(id)
    for bp_id, data in pairs(_breakpoints_data) do
        if data.states then
            data.states[id] = nil
            _refresh_breakpoint_sign(bp_id, data)
        end
    end
end

---@type fun(sess_id: number, event: loopdebug.session.notify.BreakpointState[])
local function _on_breakpoints_update(sess_id, event)
    for _, state in ipairs(event) do
        local bp = _breakpoints_data[state.breakpoint_id]
        if bp then
            bp.states = bp.states or {}
            bp.states[sess_id] = state.verified
            local data = _breakpoints_data[state.breakpoint_id]
            if data then
                _refresh_breakpoint_sign(state.breakpoint_id, data)
            end
        end
    end
end

---@param ws_dir string
function M.select_breakpoint(ws_dir)
    if not ws_dir then
        vim.notify('No active workspace')
        return
    end
    local data = breakpoints.get_breakpoints()
    if not data or #data == 0 then
        vim.notify('No existing breakpoints')
        return
    end
    ---@cast data loopdebug.SourceBreakpoint[]
    local choices = {}
    for _, bp in pairs(data) do
        local bpdata = _breakpoints_data[bp.id]
        local verified = bpdata and _get_breakpoint_state(bpdata) or false
        local item = {
            label = _format_breakpoint(bp, verified, ws_dir),
            file = bp.file,
            line = bp.line,
            data = bp,
        }
        table.insert(choices, item)
    end
    table.sort(choices, function(a, b)
        if a.file ~= b.file then return a.file < b.file end
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

function M.init()
    if _init_done then return end
    _init_done = true
    assert(config.current)

    local highlight = "LoopDebugBreakpoint"

    vim.api.nvim_set_hl(0, highlight, { link = "Debug" })

    local symbols = config.current.symbols
    assert(symbols)

    _sign_group = loopsigns.define_group("Breakpoints", {priority = config.current.sign_priority.breakpoints},
        function(file, signs)
            for id, sign in pairs(signs) do
                -- Update breakpoint line to match sign
                breakpoints.update_breakpoint_line(id, sign.lnum)
            end
        end)

    for name, full_name in pairs(_sign_names) do
        _sign_group.define_sign(full_name, symbols[name], highlight)
    end

    breakpoints.add_tracker({
        on_set = _on_breakpoint_set,
        on_enabled = _on_breakpoint_enabled,
        on_disabled = _on_breakpoint_disabled,
        on_moved = _on_breakpoint_moved,
        on_removed = _on_breakpoint_removed,
        on_all_removed = _on_all_breakpoints_removed
    })

    debugevents.add_tracker({
        on_session_added = _on_session_added,
        on_session_removed = _on_session_removed,
        on_breakpoints_update = _on_breakpoints_update,
    })
end

return M
