---@class loop.signs
local M              = {}

local debugevents    = require('loop-debug.debugevents')
local signsmgr       = require('loop.signsmgr')
local config         = require("loop-debug.config")
local filetools      = require('loop.tools.file')
local uitools        = require('loop.tools.uitools')

local _sign_group    = "currentframe"
local _sign_name     = "currentframe"

local _init_done     = false
local _query_context = 0

local _locals_ns     = vim.api.nvim_create_namespace("loop-debug-locals")

local function _remove_locals_virttext()
    -- Clear in all buffers to be safe
    for _, buf in ipairs(vim.api.nvim_list_bufs()) do
        if vim.api.nvim_buf_is_loaded(buf) then
            vim.api.nvim_buf_clear_namespace(buf, _locals_ns, 0, -1)
        end
    end
end

local function _find_variable_columns(line_text, var_name)
    local cols = {}
    local start = 1

    while true do
        local s, e = line_text:find("%f[%w_]" .. vim.pesc(var_name) .. "%f[^%w_]", start)
        if not s then break end
        table.insert(cols, { s - 1, e - 1 }) -- 0-based cols
        start = e + 1
    end

    return cols
end

local function _place_variables_virttext(frame, data)
    if not (frame.source and frame.source.path) then return end
    if not data.variables then return end

    local bufnr = vim.fn.bufnr(frame.source.path)
    if bufnr == -1 then return end

    vim.api.nvim_buf_clear_namespace(bufnr, _locals_ns, 0, -1)

    local line = frame.line - 1
    local line_text = vim.api.nvim_buf_get_lines(bufnr, line, line + 1, false)[1]
    if not line_text then return end

    for _, var in ipairs(data.variables) do
        local name  = var.name
        local value = var.value or "nil"
        if not name then goto continue end

        local cols = _find_variable_columns(line_text, name)

        for _, col in ipairs(cols) do
            local _, end_col = unpack(col)

            vim.api.nvim_buf_set_extmark(bufnr, _locals_ns, line, end_col + 1, {
                virt_text = {
                    { " = ", "Comment" },
                    { value, "Comment" },
                },
                virt_text_pos = "inline",
                hl_mode = "combine",
            })
        end

        ::continue::
    end
end


---@param view loopdebug.events.CurrentViewUpdate
local function _place_locals_virttext(view)
    local frame = view.frame
    if not (frame and frame.source and frame.source.path) then
        return
    end
    _query_context = _query_context + 1
    local context = _query_context
    view.data_providers.scopes_provider({ frameId = frame.id }, function(_, scopes_data)
        if context ~= _query_context then return end
        if scopes_data and scopes_data.scopes then
            for _, scope in pairs(scopes_data.scopes) do
                if scope.presentationHint == "locals" or scope.name == "Local" then
                    view.data_providers.variables_provider({ variablesReference = scope.variablesReference },
                        function(err, data)
                            if context ~= _query_context then return end
                            if data then
                                _place_variables_virttext(frame, data)
                            end
                        end)
                end
            end
        end
    end)
end

function M.init()
    if _init_done then return end
    _init_done = true

    local highlight = "LoopDebugCurrentFrame"
    vim.api.nvim_set_hl(0, highlight, { link = "Todo" })

    signsmgr.define_sign_group(_sign_group, config.current.sign_priority.currentframe)
    signsmgr.define_sign(_sign_group, _sign_name, "▶", highlight)

    debugevents.add_tracker({
        on_debug_start = function()

        end,
        on_debug_end = function(success)

        end,
        on_view_udpate = function(view)
            local frame = view.frame
            if not (frame and frame.source and frame.source.path) then
                signsmgr.remove_signs(_sign_group)
                _remove_locals_virttext()
                return
            end
            if not filetools.file_exists(frame.source.path) then return end
            -- Open file and move cursor
            uitools.smart_open_file(frame.source.path, frame.line, frame.column)
            -- Place sign for current frame
            signsmgr.place_file_sign(1, frame.source.path, frame.line, _sign_group, _sign_name)

            _place_locals_virttext(view)
        end
    })
end

return M
