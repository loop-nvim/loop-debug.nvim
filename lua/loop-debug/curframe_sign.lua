---@class loop.signs
local M           = {}

local debugevents = require('loop-debug.debugevents')
local loopsigns   = require('loop.signs')
local extmarks    = require('loop.extmarks')
local config      = require("loop-debug.config")
local filetools   = require('loop.tools.file')
local uitools     = require('loop.tools.uitools')
local strtools    = require('loop.tools.strtools')

do
    -- vim.api.nvim_set_hl(0, 'LoopDebugVarPill', { link = 'DiagnosticInfo' })
    -- vim.api.nvim_set_hl(0, 'LoopDebugVarPill', { link = 'FloatBorder' })
    -- vim.api.nvim_set_hl(0, 'LoopDebugVarPill', { link = 'NormalFloat' })
    vim.api.nvim_set_hl(0, 'LoopDebugVarPill', { link = 'Visual' })
    local pill = vim.api.nvim_get_hl(0, { name = 'LoopDebugVarPill', link = false })
    vim.api.nvim_set_hl(0, 'LoopDebugVarPillSep', { fg = pill.bg, bg = 'NONE' })
end

---@type loop.signs.Group
local _sign_group

local _sign_name           = "currentframe"

local _init_done           = false
local _query_context       = 0

local _vars_max_value_len  = 30
local _vars_extmarks_group = extmarks.define_group("debug_vars", { priority = 80 })
local _vars_extmark_id     = 0

local _vars_clear_timer
local function _remove_locals_virttext()
    if not _vars_clear_timer then
        --defer to avoid flickering
        _vars_clear_timer = vim.defer_fn(function()
                _vars_clear_timer = nil
                _vars_extmarks_group.remove_extmarks()
            end,
            config.current.anti_flicker_delay)
    end
end

local function _cancel_deferred_remove_locals_virttext()
    if _vars_clear_timer and _vars_clear_timer:is_active() then
        _vars_clear_timer:stop()
        _vars_clear_timer:close()
        _vars_clear_timer = nil
    end
end

local _ts_SCOPE_NODES = {
    compound_statement = true, -- { ... }
    for_statement = true,
    while_statement = true,
    if_statement = true,
    function_definition = true,
}

-- Nodes that *introduce* names (we’ll search inside them for identifiers)
local _ts_DECL_NODES = {
    declaration = true,
    init_declarator = true,
    declarator = true,
    parameter_declaration = true,
    reference_declarator = true
}

local function _ts_find_identifier(node)
    if not node then return nil end
    local type = node:type()
    if type == "identifier" then
        return node
    end
    if _ts_DECL_NODES[type] then
        for child in node:iter_children() do
            local id = _ts_find_identifier(child)
            if id then return id end
        end
    end
    return nil
end

---@param scope TSNode
---@param bufnr integer
---@param results {node: TSNode, id_node: TSNode?, name: string?}[]
local function _ts_get_indentifiers_in_scope(scope, bufnr, row, results)
    ---@type TSNode[]
    local children = {}
    for child in scope:iter_children() do
        local r = select(1, child:start())
        if r <= row then
            table.insert(children, child)
        end
    end
    local reversed = {}
    for i = #children, 1, -1 do
        reversed[#reversed + 1] = children[i]
    end
    for _, child in ipairs(reversed) do
        local t = child:type()
        local id = _ts_find_identifier(child)
        if id then
            local name = vim.treesitter.get_node_text(id, bufnr)
            if name and name ~= "" then
                table.insert(results, {
                    node    = child,
                    id_node = id,
                    name    = name,
                })
            end
        elseif not _ts_SCOPE_NODES[t] then
            _ts_get_indentifiers_in_scope(child, bufnr, row, results)
        end
    end
end

local function _place_variables_virttext(frame, data)
    if not (data.variables and frame.source and frame.source.path and frame.line) then
        return
    end

    local filepath = frame.source.path
    local bufnr = vim.fn.bufnr(filepath)
    if bufnr == -1 then return end

    _vars_extmarks_group.remove_extmarks()

    local lang = vim.treesitter.language.get_lang(vim.bo[bufnr].filetype)
    local ok, parser = pcall(vim.treesitter.get_parser, bufnr, lang)
    if not ok or not parser then return end

    local tree = parser:parse()[1]
    if not tree then return end

    local root = tree:root()

    --------------------------------------------------------------------
    -- Debugger → name → trimmed value
    --------------------------------------------------------------------
    local dbg_vars = {}
    for _, v in ipairs(data.variables) do
        if v.name and v.value then
            dbg_vars[v.name] = vim.trim(v.value)
        end
    end

    if vim.tbl_isempty(dbg_vars) then return end

    --------------------------------------------------------------------
    -- Place helper
    --------------------------------------------------------------------
    local function place_value(id_node, name, value)
        local display = tostring(value)
        local text = string.format(
            "%s: %s",
            name,
            display
        )
        if #text > _vars_max_value_len then
            text = string.format(
                "%s: %s",
                strtools.crop_string_for_ui(name, math.floor(_vars_max_value_len / 3)),
                display
            )
            text = strtools.crop_string_for_ui(text, _vars_max_value_len)
        end

        local sr, _, _, _ = id_node:range() -- 0-based

        _vars_extmark_id = _vars_extmark_id + 1
        _vars_extmarks_group.place_file_extmark(_vars_extmark_id, filepath, sr + 1, 0, {
            virt_text     = {
                { "", "LoopDebugVarPillSep" }, -- left rounded cap (many themes have these)
                { text, "LoopDebugVarPill" },
                { "", "LoopDebugVarPillSep" }, -- right rounded cap
            },
            virt_text_pos = "eol",
            hl_mode       = "combine",
        })
    end

    --------------------------------------------------------------------
    -- Build scope stack (innermost → outermost)
    --------------------------------------------------------------------
    local cursor_row = frame.line - 1 -- 0-based
    local cursor_col = (frame.column or 1) - 1

    local current = root:descendant_for_range(cursor_row, cursor_col, cursor_row, cursor_col + 1)
    if not current then return end

    ---@type TSNode[]
    local scope_stack = {}

    ---@type TSNode?
    local n = current
    while n do
        if _ts_SCOPE_NODES[n:type()] then
            table.insert(scope_stack, n)
        end
        n = n:parent()
    end

    -- Now scope_stack[1] = innermost

    --------------------------------------------------------------------
    -- Process scopes from inner → outer (respect shadowing)
    --------------------------------------------------------------------
    local seen = {} -- name → true (already displayed from inner scope)

    for _, scope_node in ipairs(scope_stack) do
        local decls = {}
        _ts_get_indentifiers_in_scope(scope_node, bufnr, cursor_row, decls)
        for _, entry in ipairs(decls) do
            local name = entry.name
            if name and not seen[name] then
                local value = dbg_vars[name]
                if value then
                    place_value(entry.id_node or entry.node, name, value)
                    seen[name] = true
                end
            end
        end
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

    _sign_group = loopsigns.define_group("CurrentFrame", { priority = config.current.sign_priority.currentframe })
    _sign_group.define_sign(_sign_name, config.current.symbols.debug_frame or ">", highlight)

    debugevents.add_tracker({
        on_debug_start = function()

        end,
        on_debug_end = function()

        end,
        on_view_udpate = function(view)
            local frame = view.frame
            if not (frame and frame.source and frame.source.path) then
                _sign_group.remove_signs()
                if config.current.enable_inlay_variables then
                    _remove_locals_virttext()
                end
                return
            end
            if not filetools.file_exists(frame.source.path) then return end
            -- Open file and move cursor
            local _, bufnr = uitools.smart_open_file(frame.source.path, frame.line, frame.column)
            -- Place sign for current frame
            _sign_group.place_file_sign(1, frame.source.path, frame.line, _sign_name)
            if config.current.enable_inlay_variables then
                _cancel_deferred_remove_locals_virttext()
                _place_locals_virttext(view)
            end
        end
    })
end

return M
