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

local MAX_VALUE_LEN        = 25
local _vars_extmarks_group = extmarks.define_group("debug_vars", { priority = 80 })
local _vars_extmark_id     = 0

local function _remove_locals_virttext()
    _vars_extmarks_group.remove_extmarks()
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
    -- Debugger lookup: name → value
    --------------------------------------------------------------------

    local dbg_vars = {}
    for _, v in ipairs(data.variables) do
        if v.name and v.value then
            dbg_vars[v.name] = vim.trim(v.value)
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
            local v = scope.declared[name]
            if v ~= nil then
                return scope, v
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

    -- Nodes that *introduce* names (we’ll search inside them for identifiers)
    local DECL_NODES = {
        declaration = true,
        init_declarator = true,
        declarator = true,
        parameter_declaration = true,
    }

    local function find_identifier(node)
        if not node then return nil end
        if node:type() == "identifier" then
            return node
        end
        for child in node:iter_children() do
            local id = find_identifier(child)
            if id then return id end
        end
        return nil
    end

    local function is_declaration_node(node)
        return DECL_NODES[node:type()] == true
    end

    --------------------------------------------------------------------
    -- Virttext placement for an identifier usage
    --------------------------------------------------------------------
    local function show_identifier(node, scope)
        local name = vim.treesitter.get_node_text(node, bufnr)
        local owner, value = lookup(scope, name)
        if not owner or owner.shown[name] then
            return
        end
        owner.shown[name] = true

        local display_value = tostring(value)
        if MAX_VALUE_LEN and #display_value > MAX_VALUE_LEN then
            display_value = display_value:sub(1, MAX_VALUE_LEN) .. "…"
        end

        local pill = ("%s %s: %s"):format(config.current.symbols.variable_value, name, display_value)
        local sr, _, _, ec = node:range()
        _vars_extmark_id = _vars_extmark_id + 1
        _vars_extmarks_group.place_file_extmark(_vars_extmark_id, filepath, sr + 1, ec, {
            virt_text = { { " ", "" }, { pill, "DiagnosticFloatingHint" } },
            virt_text_pos = "eol",
            hl_mode = "combine",
        })

    end

    --------------------------------------------------------------------
    -- Scan a subtree in execution order:
    --  * first collect declarations (so later usages in the same subtree see them)
    --  * then annotate identifier usages
    -- This is a heuristic but works well for "previous siblings" scanning.
    --------------------------------------------------------------------
    local function scan_subtree(node, scope)
        if not node then return end

        -- Enter new scope if this node is a scope boundary.
        local t = node:type()
        if SCOPE_NODES[t] then
            scope = new_scope(scope)
        end

        -- If this node is a declaration container, add declared names to *current* scope.
        -- if is_declaration_node(node) then
        local idn = find_identifier(node)
        if idn then
            local name = vim.treesitter.get_node_text(idn, bufnr)
            local val = dbg_vars[name]
            if val ~= nil then
                scope.declared[name] = val
                dbg_vars[name] = nil
            end
        end
        -- Still continue scanning: declaration initializers may reference earlier vars.
        -- end

        if t == "identifier" then
            show_identifier(node, scope)
        end

        for child in node:iter_children() do
            scan_subtree(child, scope)
        end
    end


    --------------------------------------------------------------------
    -- Node at frame location
    --------------------------------------------------------------------
    local function clamp(v, lo, hi)
        if v < lo then return lo end
        if v > hi then return hi end
        return v
    end

    local row0 = clamp((frame.line or 1) - 1, 0, root:end_())
    local col0 = frame.column or 0
    -- If your adapter reports 1-based columns, uncomment:
    -- col0 = math.max(col0 - 1, 0)

    local node_at_pos = root:named_descendant_for_range(row0, col0, row0, col0)
    if not node_at_pos then return end

    --------------------------------------------------------------------
    -- Build scope chain by going up to root, but we’ll *scan previous siblings*
    -- at each parent level to approximate what’s in scope at this point.
    --------------------------------------------------------------------
    local scope = new_scope(nil)

    -- First: scan the current node subtree (so you annotate identifiers “here”),
    -- but without pulling in later siblings.
    scan_subtree(node_at_pos, scope)

    local current = node_at_pos
    while current and current ~= root do
        local parent = current:parent()
        if not parent then break end

        -- If parent is a scope node, we are “inside” it; create a scope for it.
        if SCOPE_NODES[parent:type()] then
            scope = new_scope(scope)
        end

        -- Scan previous named siblings of `current` (within parent), in source order.
        -- Only siblings *before* current should affect current point.
        local sib = current:prev_named_sibling()
        local stack = {}
        while sib do
            table.insert(stack, sib)
            sib = sib:prev_named_sibling()
        end
        -- Reverse so we scan earliest → latest (important for intra-block ordering).
        for i = #stack, 1, -1 do
            scan_subtree(stack[i], scope)
        end

        current = parent
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
    signsmgr.define_sign(_sign_group, _sign_name,  config.current.symbols.debug_frame or ">", highlight)

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
            local _, bufnr = uitools.smart_open_file(frame.source.path, frame.line, frame.column)
            -- Place sign for current frame
            signsmgr.place_file_sign(1, frame.source.path, frame.line, _sign_group, _sign_name)

            _place_locals_virttext(view)
        end
    })
end

return M
