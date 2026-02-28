local class        = require('loop.tools.class')
local floatwin     = require('loop.tools.floatwin')
local ItemTreeComp = require('loop.comp.ItemTree')
local config       = require('loop-debug.config')
local persistence  = require('loop-debug.persistence')
local daptools     = require('loop-debug.dap.daptools')
local debugevents  = require('loop-debug.debugevents')

---@class loopdebug.comp.Variables.ItemData
---@field path string
---@field name string
---@field value string
---@field presentationHint loopdebug.proto.VariablePresentationHint?
---@field variablesReference number?
---@field evaluateName string?
---@field is_expr boolean?
---@field is_na boolean?
---@field greyout_pending boolean?
---@field greyout boolean?
---@field scopelabel string?

---@alias loopdebug.comp.Variables.ItemDef loop.comp.ItemTree.ItemDef

---@class loopdebug.comp.Vars.DataSource
---@field sess_id number
---@field sess_name string
---@field data_providers loopdebug.session.DataProviders
---@field frame loopdebug.proto.StackFrame

---@class loopdebug.comp.Vars.Expression
---@field id number
---@field expr string
---@field disabled boolean

---@class loopdebug.comp.Variables : loop.comp.ItemTree
---@field new fun(self: loopdebug.comp.Variables): loopdebug.comp.Variables
local Variables    = class(ItemTreeComp)

---@param parent_id any
---@param name string
---@param index number
---@return string
local function _get_semantic_id(parent_id, name, index)
    return string.format("%s::%s#%d", tostring(parent_id), name, index)
end

---@param str string
---@param max_len number
---@return string preview
---@return boolean is_different
local function _preview_string(str, max_len)
    assert(type(str) == 'string', str)
    max_len = max_len > 2 and max_len or 2
    if #str < max_len and not str:find("\n", 1, true) then
        return str, false
    end
    local preview = str:gsub("\n", "⏎")
    if #preview <= max_len then return preview, true end
    preview = preview:sub(1, max_len)
    preview = preview:match("^%s*(.-)%s*$") -- trim
    return preview .. "…", true
end

---@type table<string, string>
local _var_kind_to_hl_group = {
    property   = "@property",
    method     = "@method",
    ["class"]  = "@type",
    data       = "@variable",
    event      = "@event",
    baseClass  = "@type",
    innerClass = "@type",
    interface  = "@type",
}

---@param id any
---@param data loopdebug.comp.Variables.ItemData
---@return string[][], string[][]
local function _variable_node_formatter(id, data)
    if not data then
        return {}, {}
    end

    local text_chunks = {}
    local virt_chunks = {}

    -- not available
    if data.is_na and not data.name then
        table.insert(text_chunks, { "not available", "NonText" })
        return text_chunks, virt_chunks
    end

    local base_hl = data.greyout and "NonText" or nil

    -- scope label (single segment)
    if data.scopelabel then
        table.insert(text_chunks, { data.scopelabel, "Directory" })
        return text_chunks, virt_chunks
    end

    local name = tostring(data.name or "unknown")
    local value = daptools.format_variable(
        tostring(data.value or ""),
        data.presentationHint
    )

    local preview, _ = _preview_string(value, vim.o.columns - 20)

    -- name
    table.insert(text_chunks, { name, base_hl or "@symbol" })
    table.insert(text_chunks, { ": ", base_hl or "NonText" })

    -- value highlight
    local hl = base_hl
    if data.is_na then
        hl = "NonText"
    end

    local kind = data.presentationHint and data.presentationHint.kind
    local val_hl = hl or _var_kind_to_hl_group[kind] or "@variable"

    table.insert(text_chunks, { preview, val_hl })

    return text_chunks, virt_chunks
end


function Variables:init()
    ItemTreeComp.init(self, {
        formatter = _variable_node_formatter,
        render_delay_ms = 200,
    })

    ---@type loopdebug.comp.Vars.Expression[]
    self._expressions = persistence.get_config("expr") or {}

    self._query_context = 0
    self._spurious_pause_counter = 0

    ---@type loopdebug.events.CurrentViewUpdate|nil
    self._current_data_source = nil
    ---@type table<string, boolean>
    self._layout_cache = {}
    self._expr_root_id = "x"

    self:add_tracker({
        on_toggle = function(_, data, expanded)
            self._layout_cache[data.path] = expanded
        end,
        on_open = function(_, data)
            if data.scopelabel or data.is_na then return end
            floatwin.show_floatwin(daptools.format_variable(tostring(data.value), data.presentationHint), {
                title = data.name or "value"
            })
        end
    })

    ---@type loop.TrackerRef?
    self._events_tracker_ref = debugevents.add_tracker({
        on_debug_start = function()
            self:clear_items()
            self._current_data_source = nil
            self._query_context = self._query_context + 1
            self:_update_data(self._query_context)
        end,
        on_debug_end = function()
            self:clear_items()
            self._current_data_source = nil
            self._query_context = self._query_context + 1
            self:_update_data(self._query_context)
        end,
        on_view_udpate = function(view)
            self._current_data_source = view
            self._query_context = self._query_context + 1
            if view.spurious_pause then self._spurious_pause_counter = self._spurious_pause_counter + 1 end
            self:_update_data(self._query_context)
        end
    })

    ---@type loop.TrackerRef?
    self._persistence_tracker_ref = persistence.add_tracker({
        on_ws_load = function()
            self._expressions = persistence.get_config("expr") or {}
            self:_update_data(self._query_context)
        end,
        on_ws_will_save = function()
            ---@type loopdebug.comp.Vars.Expression[]
            local data = vim.deepcopy(self._expressions)
            for _, exrobj in ipairs(data) do
                exrobj.disabled = nil
            end
            persistence.set_config("expr", data)
        end,
    })

    self:_load_expressions(self._query_context)
end

---@param expr string
---@return loopdebug.comp.Vars.Expression?
function Variables:_add_expr(expr)
    local data = self._expressions
    ---@cast data loopdebug.comp.Vars.Expression[]
    local max_id = 1
    for _, v in ipairs(data) do
        max_id = math.max(max_id, v.id)
    end
    local new_id = max_id + 1
    ---@type loopdebug.comp.Vars.Expression
    local obj = {
        id = new_id,
        expr = expr,
        disabled = false
    }
    table.insert(data, obj)
    return obj
end

---@param id number
---@param old string
---@param new string
---@return loopdebug.comp.Vars.Expression?
function Variables:_reset_expr(id, old, new)
    local data = self._expressions
    ---@cast data loopdebug.comp.Vars.Expression[]
    for _, v in ipairs(data) do
        if v.id == id then
            v.expr = new
            return v
        end
    end
end

---@param id number
---@return boolean
function Variables:_remove_expr(id)
    local data = self._expressions
    ---@cast data loopdebug.comp.Vars.Expression[]
    for i, v in ipairs(data) do
        if v.id == id then
            table.remove(data, i)
            return true
        end
    end
    return false
end

---@param ctx number
function Variables:_update_data(ctx)
    if self._defer_greyout_timer then
        self._defer_greyout_timer:stop()
        self._defer_greyout_timer:close()
        self._defer_greyout_timer = nil
    end
    --defer to avoid flickering
    local timer
    timer = vim.defer_fn(function()
        if self._defer_greyout_timer ~= timer then
            return
        end
        self._defer_greyout_timer = nil
        local items = self:get_items()
        for _, item in ipairs(items) do
            if item.data.greyout_pending then
                item.data.greyout = true
                item.data.greyout_pending = false
            end
        end
        self:refresh_content()
    end, config.current.anti_flicker_delay)
    self._defer_greyout_timer = timer

    local items = self:get_items()
    for _, item in ipairs(items) do item.data.greyout_pending = true end
    self:refresh_content()

    self:_load_expressions(ctx)
    self:_load_session_vars(ctx)
end

---@param context number
---@param data_providers loopdebug.session.DataProviders
---@param ref number
---@param parent_id any
---@param parent_path string
---@param callback fun(items:loopdebug.comp.Variables.ItemDef[])
function Variables:_load_variables(context, data_providers, ref, parent_id, parent_path, callback)
    data_providers.variables_provider({ variablesReference = ref }, function(_, vars_data)
        if self._query_context ~= context then return end
        local children = {}
        if vars_data and vars_data.variables then
            for idx, var in ipairs(vars_data.variables) do
                local item_id = _get_semantic_id(parent_id, var.name, idx)
                local path = parent_path .. '/' .. var.name

                ---@type loopdebug.comp.Variables.ItemDef
                local var_item = {
                    id = item_id,
                    parent_id = parent_id,
                    expanded = self._layout_cache[path],
                    ---@type loopdebug.comp.Variables.ItemData
                    data = {
                        path = path,
                        name = var.name,
                        value = var.value,
                        presentationHint = var.presentationHint,
                        variablesReference = var.variablesReference,
                        evaluateName = var.evaluateName
                    },
                }

                if var.variablesReference and var.variablesReference > 0 then
                    var_item.children_callback = function(cb)
                        if var_item.data.greyout then
                            cb({})
                        else
                            self:_load_variables(context, data_providers, var.variablesReference, item_id, path, cb)
                        end
                    end
                end
                table.insert(children, var_item)
            end
        end
        callback(children)
    end)
end

---@param context number
---@param parent_id string
---@param parent_path string
---@param scopes loopdebug.proto.Scope[]
---@param data_source loopdebug.events.CurrentViewUpdate
---@param scopes_cb fun(items: loop.comp.ItemTree.Item[])
function Variables:_load_scopes(context, parent_id, parent_path, scopes, data_source, scopes_cb)
    ---@type loop.comp.ItemTree.Item[]
    local scope_items = {}
    for idx, scope in ipairs(scopes) do
        local path = parent_path .. '/' .. scope.name
        local item_id = _get_semantic_id(parent_id, scope.name, idx)

        local expanded = self._layout_cache[path]
        if expanded == nil then
            expanded = not (scope.expensive or scope.presentationHint == "globals"
                or scope.name == "Registers" or scope.name == "Static"
                or scope.name == "Global" or scope.name == "Globals")
        end

        ---@type loop.comp.ItemTree.ItemDef
        local scope_item = {
            id = item_id,
            parent_id = parent_id,
            expanded = expanded,
            data = {
                path = path,
                scopelabel = (scope.expensive and "⏱ " or "") .. scope.name,
                variablesReference = scope.variablesReference,
            }
        }
        scope_item.children_callback = function(cb)
            self:_load_variables(context, data_source.data_providers, scope.variablesReference, item_id, path, cb)
        end
        table.insert(scope_items, scope_item)
    end
    scopes_cb(scope_items)
end

---@param context number
function Variables:_load_expressions(context)
    local root_id = self._expr_root_id
    local root_expanded = self._layout_cache[root_id]
    if root_expanded == nil then root_expanded = true end
    if not self:get_item(root_id) then
        self:add_item(nil,
            {
                id = root_id,
                expanded = root_expanded,
                data = { path = root_id, scopelabel = "Expressions" }
            })
    end

    if not persistence.is_ws_open() then
        self:remove_children(root_id)
        return
    end
    do
        local exr_names = {}
        for _, expr_obj in ipairs(self._expressions) do
            exr_names[expr_obj.expr] = true
        end
        local children = self:get_children(self._expr_root_id)
        for _, child in ipairs(children) do
            if not exr_names[child.data.name] then
                self:remove_item(child.id)
            end
        end
    end
    for _, expr_obj in ipairs(self._expressions) do
        local item_id = root_id .. "/" .. tostring(expr_obj.id)
        local existing_item = self:get_item(item_id)
        if not existing_item then
            local item_data = {
                name = expr_obj.expr,
                path = item_id,
                is_expr = true,
                expr_id = expr_obj.id,
                is_na = true,
                value = "not available"
            }
            ---@type loopdebug.comp.Variables.ItemDef
            local item_def = {
                id = item_id,
                expanded = self._layout_cache[item_data.path],
                data = item_data
            }
            self:add_item(root_id, item_def)
        end
    end

    local list = vim.fn.copy(persistence.get_config("expr") or {})
    local load_next
    load_next = function()
        if #list == 0 then return end
        local exprobj = table.remove(list, 1)
        self:_load_expr_value(context, exprobj, function()
            vim.schedule(function()
                load_next()
            end)
        end)
    end
    load_next()
end

---@param context number
---@param expr_obj loopdebug.comp.Vars.Expression
---@param on_complete fun()?
function Variables:_load_expr_value(context, expr_obj, on_complete)
    assert(expr_obj.id and expr_obj.expr)


    if not persistence.is_ws_open() then return end
    if self._query_context ~= context then return end

    local root_id = self._expr_root_id
    if not self:get_item(root_id) then return end

    local item_id = root_id .. "/" .. tostring(expr_obj.id)

    local expr = expr_obj.expr
    local existing_item = self:get_item(item_id)
    if not existing_item then return end
    local item_data = existing_item.data

    local ds = self._current_data_source
    if not expr or not ds or not ds.frame or not ds.data_providers then
        return
    end

    if expr_obj.disabled then
        item_data.is_na = true
        item_data.value = "disabled"
        return
    end

    local spurious_pause_counter = self._spurious_pause_counter
    ds.data_providers.evaluate_provider({
        expression = expr, frameId = ds.frame.id, context = "watch",
    }, function(err, data)
        if spurious_pause_counter ~= self._spurious_pause_counter then
            expr_obj.disabled = true
        end
        if self._query_context ~= context then return end
        if not self:have_item(item_id) then return end
        local children_callback
        if err or not data then
            item_data.value = "not available"
            item_data.is_na = true
            item_data.greyout = false
            item_data.greyout_pending = false
        else
            item_data.value = data.result
            item_data.presentationHint = data.presentationHint
            item_data.is_na = false
            item_data.greyout = false
            item_data.greyout_pending = false
            if data.variablesReference and data.variablesReference > 0 then
                children_callback = function(cb)
                    self:_load_variables(context, ds.data_providers, data.variablesReference, item_id, item_data.path, cb)
                end
            end
        end
        ---@type loop.comp.ItemTree.ItemDef
        local update_def = {
            id = item_id,
            data = item_data,
            children_callback = children_callback
        }
        self:update_item(update_def)
        if on_complete then on_complete() end
    end)
end

---@param context number
function Variables:_load_session_vars(context)
    local root_id = "s"
    ---@type loop.comp.ItemTree.ChildrenCallback
    local children_callback
    local ds = self._current_data_source
    if ds and ds.frame then
        children_callback = function(cb)
            ds.data_providers.scopes_provider({ frameId = ds.frame.id }, function(_, scopes_data)
                if self._query_context ~= context then return end
                if scopes_data and scopes_data.scopes then
                    self:_load_scopes(context, root_id, root_id, scopes_data.scopes, ds, cb)
                else
                    cb({ { id = "na", data = { is_na = true } } })
                end
            end)
        end
    end
    if self:have_item(root_id) then
        self:set_children_callback(root_id, children_callback)
    else
        local root_expanded = self._layout_cache[root_id]
        if root_expanded == nil then root_expanded = true end

        ---@type loop.comp.ItemTree.ItemDef
        local root_item = {
            id = root_id, expanded = root_expanded, children_callback = children_callback, data = { path = root_id, scopelabel = "Variables" }
        }
        self:add_item(nil, root_item)
    end
end

---@param comp loop.CompBufferController
function Variables:link_to_buffer(comp)
    ItemTreeComp.link_to_buffer(self, comp)

    local function add_watch_expr()
        floatwin.input_at_cursor({},
            function(expr)
                if not expr or expr == "" then return end
                local expr_obj = self:_add_expr(expr)
                if expr_obj then
                    self:_load_expr_value(self._query_context, expr_obj)
                end
            end
        )
    end

    ---@param item loop.comp.ItemTree.Item
    local function edit_watch_expr(item)
        floatwin.input_at_cursor({ default_text = item.data.name or "" },
            function(expr)
                if not expr or expr == "" then return end
                if expr ~= item.data.name then
                    local expr_obj = self:_reset_expr(item.data.expr_id, item.data.name, expr)
                    if expr_obj then
                        self:_load_expr_value(self._query_context, expr_obj)
                    end
                end
            end
        )
    end

    ---@param item loop.comp.ItemTree.Item
    local function edit_variable(item)
        local data_source = self._current_data_source
        if not data_source then return end
        local providers = data_source.data_providers
        if not providers then return end
        local parent_item = self:get_parent_item(item.id)
        if not parent_item then return end
        ---@type loopdebug.comp.Variables.ItemData
        local parent_data = parent_item.data
        ---@type loopdebug.comp.Variables.ItemData
        local data = item.data
        if data.is_expr then return end
        local supports_set_expr = providers.supports_set_expression()
        local supports_set_var = providers.supports_set_variable()
        if not supports_set_var and not (supports_set_expr and data.evaluateName) then
            vim.notify("Debug adapter does not support changing variables value")
            return
        end
        local context = self._query_context
        floatwin.input_at_cursor({ default_text = data.value },
            function(value)
                if not value or not self._current_data_source then return end
                if context ~= self._query_context then return end
                local frame_id = data_source.frame and data_source.frame.id
                if (supports_set_expr and data.evaluateName) then
                    providers.set_expression_provider({
                        expression = data.evaluateName,
                        value = value,
                        frameId = frame_id
                    }, function(err, rep)
                        if err and type(err) == "string" and #err > 0 then
                            vim.notify(err)
                        end
                    end)
                else
                    providers.set_variable_provider({
                        name = data.name,
                        variablesReference = parent_data.variablesReference,
                        value = value
                    }, function(err, rep)
                        if err and type(err) == "string" and #err > 0 then
                            vim.notify(err)
                        end
                    end)
                end
            end
        )
    end

    comp.add_keymap("i", { desc = "Add Expression", callback = function() add_watch_expr() end })
    comp.add_keymap("c", {
        desc = "Edit Expression/Variable",
        callback = function()
            local cur = self:get_cur_item()
            if cur then
                if cur.data.is_expr then
                    edit_watch_expr(cur)
                else
                    edit_variable(cur)
                end
            end
        end
    })
    comp.add_keymap("d", {
        desc = "Delete Expression",
        callback = function()
            local cur = self:get_cur_item()
            if cur and cur.data.is_expr then
                if self:_remove_expr(cur.data.expr_id) then
                    self:remove_item(cur.id)
                end
            end
        end
    })
end

function Variables:dispose()
    ItemTreeComp.dispose(self)
    if self._events_tracker_ref then self._events_tracker_ref.cancel() end
    if self._persistence_tracker_ref then self._persistence_tracker_ref.cancel() end
end

return Variables
