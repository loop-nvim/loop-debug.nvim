local M               = {}

local persistence     = require('loop-debug.persistence')
local CompBuffer      = require('loop.buf.CompBuffer')
local VariablesComp   = require('loop-debug.comp.Variables')
local StackTraceComp  = require('loop-debug.comp.StackTrace')
local SessionListComp = require('loop-debug.comp.SessionList')

local _init_done      = false
local _ui_auto_group  = vim.api.nvim_create_augroup("LoopDebugPluginUI", { clear = true })

-- ======================================
-- State
-- ======================================

local _buffers        = {} -- [index] = CompBuffer
local _components     = {} -- [index] = component instance

-- ======================================
-- Window Definitions (ORDER MATTERS)
-- ======================================

local _window_defs    = {
    {
        key                  = "variables",
        label                = "Variables",
        buf_type             = "loopdebug-vars",
        comp_class           = VariablesComp,

        -- layout defaults
        default_width_ratio  = 0.20,
        default_height_ratio = 0.50,
    },
    {
        key = "callstack",
        label = "Call Stack",
        buf_type = "loopdebug-callstack",
        comp_class = StackTraceComp,
        default_height_ratio = 0.30,
    },
    {
        key = "sessions",
        label = "Sessions",
        buf_type = "loopdebug-sessions",
        comp_class = SessionListComp,
        -- last window does not need height ratio
    }
}

local KEY_MARKER      = "loopdebugplugin_debugpanel"
local INDEX_MARKER    = "loopdebugplugin_debugpanelidx"

-- ======================================
-- Helpers
-- ======================================

local function is_managed_window(win_id)
    if not vim.api.nvim_win_is_valid(win_id) then return false end
    local ok, is_managed = pcall(function() return vim.w[win_id][KEY_MARKER] end)
    return ok and is_managed == true
end

local function get_window_index(win_id)
    if not vim.api.nvim_win_is_valid(win_id) then return 1 end
    local ok, index = pcall(function() return vim.w[win_id][INDEX_MARKER] end)
    return ok and index or 1
end

local function get_managed_windows()
    local found = {}
    for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
        if is_managed_window(win) then
            table.insert(found, win)
        end
    end
    table.sort(found, function(a, b)
        return get_window_index(a) < get_window_index(b)
    end)
    return found
end

-- ======================================
-- Layout Persistence (N - 1 heights)
-- ======================================

-- Save the current layout: total height and each window's height
local function _save_layout()
    local windows = get_managed_windows()
    if #windows ~= #_window_defs then return end

    -- Compute total height and current height ratios
    local total_lines = 0
    local height_ratios = {}
    for i, win in ipairs(windows) do
        if vim.api.nvim_win_is_valid(win) then
            local h = vim.api.nvim_win_get_height(win)
            total_lines = total_lines + h
            height_ratios[i] = h
        else
            return
        end
    end

    for i, h in ipairs(height_ratios) do
        height_ratios[i] = h / total_lines
    end

    -- Compute current width ratio for the first window
    local width_ratio = 0.5
    local first_win = windows[1]
    if first_win and vim.api.nvim_win_is_valid(first_win) then
        width_ratio = vim.api.nvim_win_get_width(first_win) / vim.o.columns
    end

    -- Load previously saved layout
    local saved = persistence.get_config("layout") or {}
    local epsilon = 1.2 / vim.o.lines

    local height_changed = false
    if saved.height_ratios then
        for i, r in ipairs(height_ratios) do
            if math.abs(r - (saved.height_ratios[i] or 0)) > epsilon then
                height_changed = true
                break
            end
        end
    else
        height_changed = true
    end

    local width_changed = math.abs(width_ratio - (saved.width_ratio or 0)) > epsilon

    -- Only save if something meaningful changed
    if height_changed or width_changed then
        local config = persistence.get_config("layout") or {}
        config.total_lines = total_lines
        if height_changed then
            config.height_ratios = height_ratios
        end
        if width_changed then
            config.width_ratio = width_ratio
        end
        persistence.set_config("layout", config)
    end
end

-- Apply saved layout, scaling heights if total height changed
local function _apply_layout()
    local windows = get_managed_windows()
    if #windows ~= #_window_defs then
        return
    end

    local total_lines = 0
    for i, win in ipairs(windows) do
        if vim.api.nvim_win_is_valid(win) then
            total_lines = total_lines + vim.api.nvim_win_get_height(win)
        end
    end

    local saved = persistence.get_config("layout") or {}
    local height_ratios = saved.height_ratios or {}

    -- Compute new heights for each window
    local heights = {}
    local accumulated = 0
    for i = 1, #windows - 1 do
        local h = math.floor(total_lines * (height_ratios[i] or _window_defs[i].default_height_ratio))
        heights[i] = h
        accumulated = accumulated + h
    end

    -- Last window takes remaining lines
    heights[#windows] = total_lines - accumulated

    -- Apply heights
    for i, win in ipairs(windows) do
        if vim.api.nvim_win_is_valid(win) then
            vim.api.nvim_win_set_height(win, heights[i])
        end
    end
end

-- ======================================
-- Component Lifecycle
-- ======================================

local function _destroy_components()
    for i, buf in pairs(_buffers) do
        buf:destroy()
        _buffers[i] = nil
    end

    for i, comp in pairs(_components) do
        if comp.dispose then
            comp:dispose()
        end
        _components[i] = nil
    end
end

local function _create_components(windows)
    _destroy_components()
    for i, def in ipairs(_window_defs) do
        local winid = windows[i]
        local compbuf = CompBuffer:new(def.buf_type, def.label)
        _buffers[i] = compbuf
        vim.wo[winid].winfixbuf = false
        vim.api.nvim_win_set_buf(winid, (compbuf:get_or_create_buf()))
        vim.wo[winid].winfixbuf = true
        if def.comp_class then
            local comp = def.comp_class:new()
            comp:link_to_buffer(compbuf:make_controller())
            _components[i] = comp
        end
    end
end

local function _on_resize()
    _save_layout()
end

-- ======================================
-- Show (Fully Generic)
-- ======================================

function M.show()
    if #get_managed_windows() > 0 then
        return
    end

    assert(_init_done)

    if not persistence.is_ws_open() then
        vim.notify("loopdebug: No active workspace", vim.log.levels.WARN)
        return
    end

    local saved = persistence.get_config("layout") or {}

    local width_ratio =
        saved.width_ratio
        or _window_defs[1].default_width_ratio
        or 0.50

    local height_ratios = saved.heights or {}

    local original_win = vim.api.nvim_get_current_win()

    -- Create vertical container (first window)
    vim.cmd("topleft 1vsplit")
    local first_win = vim.api.nvim_get_current_win()

    vim.api.nvim_win_set_width(
        first_win,
        math.floor(width_ratio * vim.o.columns)
    )

    local windows = {}
    table.insert(windows, first_win)

    -- Create remaining windows
    for i = 2, #_window_defs do
        vim.cmd("below 1split")
        local win = vim.api.nvim_get_current_win()
        table.insert(windows, win)
    end

    -- Apply height ratios for first N-1 windows
    for i = 1, (#windows - 1) do
        local ratio =
            height_ratios[i]
            or _window_defs[i].default_height_ratio

        if ratio then
            vim.api.nvim_set_current_win(windows[i])
            vim.api.nvim_win_set_height(
                windows[i],
                math.floor(ratio * vim.o.lines)
            )
        end
    end

    -- Configure windows
    for i, win in ipairs(windows) do
        vim.wo[win].wrap         = false
        vim.wo[win].spell        = false
        vim.wo[win].winfixbuf    = true

        vim.w[win][KEY_MARKER]   = true
        vim.w[win][INDEX_MARKER] = i
    end

    for i, def in ipairs(_window_defs) do
        local winid = windows[i]
        vim.api.nvim_set_option_value('winfixwidth', true, { scope = 'local', win = winid })
    end

    if vim.api.nvim_win_is_valid(original_win) then
        vim.api.nvim_set_current_win(original_win)
    end

    _create_components(windows)

    _apply_layout()

    -- Resize tracking
    vim.api.nvim_clear_autocmds({ group = _ui_auto_group })
    vim.api.nvim_create_autocmd("WinResized", {
        group = _ui_auto_group,
        callback = function()
            _on_resize()
        end,
    })
end

-- ======================================
-- Hide / Toggle
-- ======================================

function M.hide()
    local windows = get_managed_windows()

    vim.api.nvim_clear_autocmds({ group = _ui_auto_group })

    for _, win in ipairs(windows) do
        if vim.api.nvim_win_is_valid(win) then
            vim.api.nvim_win_close(win, true)
        end
    end

    _destroy_components()
end

function M.toggle()
    if #get_managed_windows() > 0 then
        M.hide()
    else
        M.show()
    end
end

-- ======================================
-- Init
-- ======================================

function M.init()
    if _init_done then return end
    _init_done = true

    persistence.add_tracker({
        on_ws_unload = function()
            M.hide()
        end,
    })
end

return M
