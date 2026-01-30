---@class loop.signs
local M                    = {}

local debugevents          = require('loop-debug.debugevents')
local signsmgr             = require('loop.signsmgr')
local extmarks             = require('loop.extmarks')
local config               = require("loop-debug.config")
local filetools            = require('loop.tools.file')
local uitools              = require('loop.tools.uitools')

local _sign_group          = "currentframe"
local _sign_name           = "currentframe"

local _init_done           = false
local _query_context       = 0

local MAX_VALUE_LEN        = 15
local _vars_extmarks_group = extmarks.define_group("debug_vars", { priority = 80 })
local _vars_extmark_id = 0

local function _remove_locals_virttext()
    _vars_extmarks_group.remove_extmarks()
end

local function _place_variables_virttext(frame, data)
    if not (data.variables and frame.source and frame.source.path) then
        return
    end

    local bufnr = vim.fn.bufnr(frame.source.path, true)
    if bufnr == -1 then return end

    _vars_extmarks_group.remove_extmarks()

    local lang = vim.treesitter.language.get_lang(vim.bo[bufnr].filetype)
    local ok, parser = pcall(vim.treesitter.get_parser, bufnr, lang)
    if not ok or not parser then return end

    local tree = parser:parse()[1]
    if not tree then return end
    local root = tree:root()

    --------------------------------------------------------------------
    -- Debugger lookup: name → value
    --------------------------------------------------------------------

    local dbg_vars = {}
    for _, v in ipairs(data.variables) do
        if v.name and v.value then
            dbg_vars[v.name] = v.value
        end
    end
    if vim.tbl_isempty(dbg_vars) then return end

    --------------------------------------------------------------------
    -- Scope model
    --------------------------------------------------------------------

    local function new_scope(parent)
        return {
            parent = parent,
            declared = {}, -- name → value
            shown = {},    -- name → bool
        }
    end

    local function lookup(scope, name)
        while scope do
            if scope.declared[name] then
                return scope, scope.declared[name]
            end
            scope = scope.parent
        end
    end

    --------------------------------------------------------------------
    -- Language rules (C/C++)
    --------------------------------------------------------------------

    local SCOPE_NODES = {
        compound_statement = true, -- { ... }
        for_statement = true,
        while_statement = true,
        if_statement = true,
        function_definition = true,
    }

    local DECL_NODES = {
        init_declarator = true, -- int i = 1
        declarator = true,      -- int i
    }

    --------------------------------------------------------------------
    -- AST walk
    --------------------------------------------------------------------

    local function visit(node, scope)
        local t = node:type()

        -- Enter scope
        if SCOPE_NODES[t] then
            scope = new_scope(scope)
        end

        -- Declaration: introduce variable into THIS scope
        if DECL_NODES[t] then
            for child in node:iter_children() do
                if child:type() == "identifier" then
                    local name = vim.treesitter.get_node_text(child, bufnr)
                    local val = dbg_vars[name]
                    if val then
                        scope.declared[name] = val
                    end
                end
            end
        end

        -- Identifier usage
        if t == "identifier" then
            local name = vim.treesitter.get_node_text(node, bufnr)
            local owner, value = lookup(scope, name)

            if owner and not owner.shown[name] then
                owner.shown[name] = true

                local display_value = value
                if #display_value > MAX_VALUE_LEN then
                    display_value = display_value:sub(1, MAX_VALUE_LEN) .. "…" -- ellipsis
                end

                local sr, _, _, ec = node:range()
                _vars_extmark_id = _vars_extmark_id + 1
                local id = _vars_extmark_id
                _vars_extmarks_group.place_file_extmark(id, frame.source.path, sr, ec, {
                    virt_text = { {
                        ("%s %s = %s"):format(
                            config.current.symbols.variable_value,
                            name,
                            display_value
                        ),
                        "DiagnosticInfo",
                    } },
                    virt_text_pos = "eol",
                    hl_mode = "combine",
                })
            end
        end

        for child in node:iter_children() do
            visit(child, scope)
        end
    end

    visit(root, new_scope(nil))
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
