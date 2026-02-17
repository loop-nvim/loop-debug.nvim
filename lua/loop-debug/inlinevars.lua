local M           = {}

local filetools   = require('loop.tools.file')
local debugevents = require('loop-debug.debugevents')
local extmarks    = require('loop.extmarks')
local config      = require("loop-debug.config")
local strtools    = require('loop.tools.strtools')
local tslangspec  = require("loop-debug.tools.tslangspec")

do
    vim.api.nvim_set_hl(0, 'LoopDebugVarPill', { link = 'Visual' })
    local pill = vim.api.nvim_get_hl(0, { name = 'LoopDebugVarPill', link = false })
    vim.api.nvim_set_hl(0, 'LoopDebugVarPillSep', { fg = pill.bg, bg = 'NONE' })
end

local _query_context       = 0

local _max_var_pill_size   = 30
local _vars_extmarks_group = extmarks.define_group("debug_vars", { priority = 80 })
local _vars_extmark_id     = 0

local _vars_clear_timer
local function _deferred_remove_locals_virttext()
    if not _vars_clear_timer then
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


---@param node TSNode
---@param langspec loopdebug.TSLangSpec
---@return TSNode[] list of identifier nodes in reversed order
local function _ts_find_identifiers(node, langspec)
    if not node then return {} end
    local identifiers = {}

    local function collect(n)
        local type = n:type()
        if type == "identifier" then
            table.insert(identifiers, 1, n) -- insert at front to reverse order
        elseif langspec.decl_nodes[type] then
            for child in n:iter_children() do
                collect(child)
            end
        end
    end

    collect(node)
    return identifiers
end

---@param scope TSNode
---@param bufnr integer
---@param row integer
---@param langspec loopdebug.TSLangSpec
---@param results {node: TSNode, id_node: TSNode?, name: string?}[]
local function _ts_get_identifiers_in_scope(scope, bufnr, row, langspec, results)
    ---@type TSNode[]
    local children = {}
    for child in scope:iter_children() do
        local r = select(1, child:start())
        if r <= row then
            table.insert(children, child)
        end
    end

    -- Reverse the children array
    for i = #children, 1, -1 do
        local child = children[i]

        -- Collect all identifier nodes in reversed order
        local ids = _ts_find_identifiers(child, langspec)
        for _, id in ipairs(ids) do
            local name = vim.treesitter.get_node_text(id, bufnr)
            if name and name ~= "" then
                table.insert(results, {
                    node    = child,
                    id_node = id,
                    name    = name,
                })
            end
        end

        -- Recurse into non-scope nodes
        local t = child:type()
        if not langspec.scope_nodes[t] then
            _ts_get_identifiers_in_scope(child, bufnr, row, langspec, results)
        end
    end
end

local function _place_variables_virttext(frame, data)
    if not (data.variables and frame.source and frame.source.path and frame.line) then
        return
    end

    if not filetools.file_exists(frame.source.path) then
        return
    end

    local filepath = frame.source.path
    local bufnr = vim.fn.bufnr(filepath)
    if bufnr == -1 then return end

    local langspec = tslangspec.get_lang_spec(vim.bo[bufnr].filetype)

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
        local name_len = #name
        local display_len = #display
        if name_len + display_len > _max_var_pill_size then
            name_len = _max_var_pill_size - display_len
            name_len = math.max(7, name_len)
            display_len = math.min(display_len, _max_var_pill_size - name_len - 2)
        end
        local text = string.format(
            "%s: %s",
            strtools.crop_string_for_ui(name, name_len),
            strtools.crop_string_for_ui(display, display_len)
        )

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
        if langspec.scope_nodes[n:type()] then
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
        _ts_get_identifiers_in_scope(scope_node, bufnr, cursor_row, langspec, decls)
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

function M.on_view_udpate(view)
    local frame = view.frame
    if not (frame and frame.source and frame.source.path) then
        if config.current.enable_inlay_variables then
            --defer to avoid flickering
            _deferred_remove_locals_virttext()
        end
        return
    end
    if config.current.enable_inlay_variables then
        _cancel_deferred_remove_locals_virttext()
        _place_locals_virttext(view)
    end
end

return M
