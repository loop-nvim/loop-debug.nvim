local M           = {}

local filetools   = require('loop.tools.file')
local debugevents = require('loop-debug.debugevents')
local config      = require("loop-debug.config")
local strtools    = require('loop.tools.strtools')
local tslangspec  = require("loop-debug.tools.tslangspec")

do
    vim.api.nvim_set_hl(0, 'LoopDebugVarPill', { link = 'Visual' })
    local pill = vim.api.nvim_get_hl(0, { name = 'LoopDebugVarPill', link = false })
    vim.api.nvim_set_hl(0, 'LoopDebugVarPillSep', { fg = pill.bg, bg = 'NONE' })
end

local _vars_ns           = vim.api.nvim_create_namespace("LoopDebug-InlineVars")

local _current_sequence  = 0
local _max_var_pill_size = 30
local _vars_extmark_id   = 0
local _init_done         = false

---@type loopdebug.events.CurrentViewUpdate
local _current_view      = nil

local _vars_clear_timer

local function _remove_extmarks()
    for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
        if vim.api.nvim_buf_is_loaded(bufnr) then
            vim.api.nvim_buf_clear_namespace(bufnr, _vars_ns, 0, -1)
        end
    end
    _vars_extmark_id = 0
end

---@param id integer
---@param filepath string
---@param line integer   -- 1-based
---@param col integer    -- 1-based
---@param opts table
local function _place_file_extmark(id, filepath, line, col, opts)
    local bufnr = vim.fn.bufnr(filepath)
    if bufnr == -1 then return end
    if not vim.api.nvim_buf_is_loaded(bufnr) then return end

    -- Convert to 0-based indexing for extmarks
    local row = math.max(0, (line or 1) - 1)
    local column = math.max(0, (col or 1) - 1)

    vim.api.nvim_buf_set_extmark(
        bufnr,
        _vars_ns,
        row,
        column,
        vim.tbl_extend("force", {
            id = id,
        }, opts or {})
    )
end


local function _deferred_remove_locals_virttext()
    if not _vars_clear_timer then
        _vars_clear_timer = vim.defer_fn(function()
                _vars_clear_timer = nil
                _remove_extmarks()
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
---@param row integer
---@param langspec loopdebug.TSLangSpec
---@return TSNode[] list of identifier nodes in reversed order
local function _ts_find_scope_identifiers(node, row, langspec)
    if not node then return {} end
    local identifiers = {}

    local function collect(n)
        local r = select(1, n:start())
        if r <= row then
            local type = n:type()
            if langspec.scope_nodes[type] then
                return
            end
            if type == "identifier" then
                table.insert(identifiers, n)
            else
                for child in n:iter_children() do
                    collect(child)
                end
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
---@param results {node: TSNode?, name: string?,row :number}[]
local function _ts_get_identifiers_in_scope(scope, bufnr, row, langspec, results)
    ---@type TSNode[]
    for child in scope:iter_children() do
        local r = select(1, child:start())
        if r <= row then
            local found = {}
            -- Collect all identifier nodes in reversed order
            local ids = _ts_find_scope_identifiers(child, row, langspec)
            for _, id in ipairs(ids) do
                local name = vim.treesitter.get_node_text(id, bufnr)
                if name and name ~= "" then
                    if not found[name] then
                        found[name] = true
                        table.insert(results, {
                            node = id,
                            name = name,
                            row = id:start()
                        })
                    end
                end
            end
        end
    end
end

---@param frame loopdebug.proto.StackFrame
---@param variables loopdebug.proto.Variable[]
local function _place_variables_virttext(frame, variables)
    if not (variables and frame.source and frame.source and frame.line) then
        return
    end
    local filepath = frame.source.path
    if not filepath then return end

    if not filetools.file_exists(filepath) then
        return
    end

    local bufnr = vim.fn.bufnr(filepath)
    if bufnr == -1 then return end

    local langspec = tslangspec.get_lang_spec(vim.bo[bufnr].filetype)

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
    for _, v in ipairs(variables) do
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
        _place_file_extmark(_vars_extmark_id, filepath, sr + 1, 1, {
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
    for _, scope_node in ipairs(scope_stack) do
        if next(dbg_vars) == nil then break end
        local decls = {}
        _ts_get_identifiers_in_scope(scope_node, bufnr, cursor_row, langspec, decls)
        -- Reverse lookup
        table.sort(decls, function(a, b)
            return a.row > b.row
        end)
        for _, entry in ipairs(decls) do
            if next(dbg_vars) == nil then break end
            local name = entry.name
            if name then
                local value = dbg_vars[name]
                if value then
                    place_value(entry.node, name, value)
                    dbg_vars[name] = nil
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
    local sequence = view.sequence
    _current_sequence = view.sequence
    view.data_providers.scopes_provider({ frameId = frame.id }, function(_, scopes_data)
        if sequence ~= _current_sequence then return end
        if scopes_data and scopes_data.scopes then
            local managed_scopes = {}
            for _, scope in pairs(scopes_data.scopes) do
                local loname = scope.name and tostring(scope.name):lower() or nil
                if not scope.expensive and scope.presentationHint ~= "globals" and scope.presentationHint ~= "registers" and loname ~= "global" and loname ~= "globals" and loname ~= "registers" and loname ~= "static" then
                    table.insert(managed_scopes, scope)
                end
            end
            ---@type loopdebug.proto.Variable[]
            local variables = {}
            local nb_replies = 0
            for _, scope in pairs(managed_scopes) do
                view.data_providers.variables_provider({ variablesReference = scope.variablesReference },
                    function(err, respone)
                        if sequence ~= _current_sequence then return end
                        nb_replies = nb_replies + 1
                        if respone and respone.variables then
                            vim.list_extend(variables, respone.variables)
                        end
                        if nb_replies == #managed_scopes then
                            _cancel_deferred_remove_locals_virttext()
                            _remove_extmarks()
                            _place_variables_virttext(frame, variables)
                        end
                    end)
            end
        end
    end)
end

function M.init()
    if _init_done then return end
    _init_done = true

    if not config.current.enable_inlay_variables then
        return
    end

    local augroup = vim.api.nvim_create_augroup("LoopDebug-InlineVars", { clear = true })

    debugevents.add_tracker({
        on_debug_start = function()
        end,
        on_debug_end = function()
        end,
        on_view_udpate = function(view)
            _current_view = view
            local frame = view.frame
            if not (frame and frame.source and frame.source.path) then
                --defer to avoid flickering
                _deferred_remove_locals_virttext()
            else
                --vim.notify("planing inline vars (view update)")
                _place_locals_virttext(view)
            end
        end
    })

    vim.api.nvim_create_autocmd({ "BufReadPost" }, {
        group = augroup,
        callback = function(ev)
            local bufname = vim.api.nvim_buf_get_name(ev.buf)
            if bufname then
                local bufpath = vim.fn.fnamemodify(bufname, ":p") -- normalize
                if _current_view and _current_view.frame then
                    local view = _current_view
                    local frame = _current_view.frame
                    if frame and frame.source and frame.source.path then
                        local source_path = vim.fn.fnamemodify(frame.source.path, ":p") -- normalize
                        if bufpath == source_path then
                            --vim.notify("planing inline vars (bufenter)")
                            _place_locals_virttext(view)
                        end
                    end
                end
            end
        end,
    })
end

return M
