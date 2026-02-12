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

local _windows        = {} -- ordered array of winids
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

-- ======================================
-- Helpers
-- ======================================

local function is_managed_window(win_id)
    if not vim.api.nvim_win_is_valid(win_id) then return false end
    local ok, is_managed = pcall(function() return vim.w[win_id][KEY_MARKER] end)
    return ok and is_managed == true
end

local function get_managed_windows()
    local found = {}
    for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
        if is_managed_window(win) then
            table.insert(found, win)
        end
    end
    return found
end

-- ======================================
-- Layout Persistence (N - 1 heights)
-- ======================================

local function _save_layout()
    if #_windows == 0 then return end

    local total_cols  = vim.o.columns
    local total_lines = vim.o.lines

    local layout      = {
        width_ratio = vim.api.nvim_win_get_width(_windows[1]) / total_cols,
        heights     = {},
    }

    -- save height ratios for first N-1 windows
    for i = 1, (#_windows - 1) do
        local h = vim.api.nvim_win_get_height(_windows[i])
        layout.heights[i] = h / total_lines
    end

    persistence.set_config("layout", layout)
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

local function _create_components()
    _destroy_components()

    for i, def in ipairs(_window_defs) do
        local winid = _windows[i]

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
    vim.cmd("topleft vsplit")
    local first_win = vim.api.nvim_get_current_win()

    vim.api.nvim_win_set_width(
        first_win,
        math.floor(width_ratio * vim.o.columns)
    )

    table.insert(_windows, first_win)

    -- Create remaining windows
    for i = 2, #_window_defs do
        vim.cmd("below split")
        local win = vim.api.nvim_get_current_win()
        table.insert(_windows, win)
    end

    -- Apply height ratios for first N-1 windows
    for i = 1, (#_windows - 1) do
        local ratio =
            height_ratios[i]
            or _window_defs[i].default_height_ratio

        if ratio then
            vim.api.nvim_set_current_win(_windows[i])
            vim.api.nvim_win_set_height(
                _windows[i],
                math.floor(ratio * vim.o.lines)
            )
        end
    end

    -- Configure windows
    for i, win in ipairs(_windows) do
        vim.wo[win].wrap        = false
        vim.wo[win].spell       = false
        vim.wo[win].winfixbuf   = true
        vim.wo[win].winfixwidth = true
        --vim.wo[win].winfixheight = true

        vim.w[win][KEY_MARKER]  = true
    end

    if vim.api.nvim_win_is_valid(original_win) then
        vim.api.nvim_set_current_win(original_win)
    end

    _create_components()

    -- Resize tracking
    vim.api.nvim_clear_autocmds({ group = _ui_auto_group })
    vim.api.nvim_create_autocmd("WinResized", {
        group = _ui_auto_group,
        callback = function()
            if #_windows > 0 then
                _save_layout()
            end
        end,
    })
end

-- ======================================
-- Hide / Toggle
-- ======================================

function M.hide()
    vim.api.nvim_clear_autocmds({ group = _ui_auto_group })

    for _, win in ipairs(_windows) do
        if vim.api.nvim_win_is_valid(win) then
            vim.api.nvim_win_close(win, true)
        end
    end

    _windows = {}
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
