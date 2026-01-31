local class = require('loop.tools.class')
local ItemListComp = require('loop.comp.ItemList')
local config = require('loop-debug.config')
local debugevents = require('loop-debug.debugevents')
local Trackers = require("loop.tools.Trackers")

---@class loopdebug.comp.StackTrace : loop.comp.ItemList
---@field new fun(self: loopdebug.comp.StackTrace, name:string): loopdebug.comp.StackTrace
local StackTrace = class(ItemListComp)

---@param id any
---@param data table
---@return loop.comp.ItemList.Chunk[]
local function _item_formatter(id, data)
    local chunks = {}

    local frame = data.frame
    if not frame then
        table.insert(chunks, {
            text = tostring(data.text or ""),
            highlight = data.greyout and "NonText" or "Directory"
        })
        return chunks
    end

    -- function name
    table.insert(chunks, { text = tostring(frame.name), highlight = "@function" })

    if frame.source and frame.source.name then
        table.insert(chunks, { text = " - " }) -- separator
        table.insert(chunks, { text = tostring(frame.source.name), highlight = "@module" })

        if frame.line then
            table.insert(chunks, { text = ":" })
            table.insert(chunks, { text = tostring(frame.line), highlight = "@number" })

            if frame.column then
                table.insert(chunks, { text = ":" })
                table.insert(chunks, { text = tostring(frame.column), highlight = "@number" })
            end
        end
    end

    -- apply greyout if needed
    if data.greyout then
        for _, chunk in ipairs(chunks) do
            chunk.highlight = "NonText"
        end
    end

    return chunks
end

function StackTrace:init()
    ItemListComp.init(self, {
        formatter = _item_formatter,
        show_current_prefix = true,
    })

    ---@type number
    self._query_context = 0

    self._frametrackers = Trackers:new()
    self:add_tracker({
        on_selection = function(id, data)
            if id and data then
                -- id 0 is the title line
                if id > 0 then
                    ---@type loopdebug.proto.StackFrame
                    local frame = data.frame
                    vim.schedule(function()
                        self._frametrackers:invoke("frame_selected", frame)
                    end)
                end
            end
        end,
    })

    ---@type loop.TrackerRef?
    self._events_tracker_ref = debugevents.add_tracker({
        on_debug_start = function()
            self:set_items({})
        end,
        on_debug_end = function(success)
            self:set_items({})
        end,
        on_view_udpate = function(view)
            self:_update_data(view)
        end
    })
end

function StackTrace:dispose()
    if self._events_tracker_ref then
        self._events_tracker_ref.cancel()
    end
end

---@param callback fun(frame:loopdebug.proto.StackFrame)
function StackTrace:add_frame_tracker(callback)
    self._frametrackers:add_tracker({
        frame_selected = callback
    })
end

---@param view loopdebug.events.CurrentViewUpdate
function StackTrace:_update_data(view)
    if not view.thread_id then
        local items = self:get_items()
        for _, item in ipairs(items) do
            item.data.greyout = true
        end
        self:refresh_content()
        return
    end
    self._query_context = self._query_context + 1
    local context = self._query_context
    view.data_providers.stack_provider({
            threadId = view.thread_id,
            levels = config.current.stack_levels_limit or 100,
        },
        function(err, resp)
            local cur_item_id = nil
            if context ~= self._query_context then return end
            local text = "Thread: " .. (view.thread_name or tostring(view.thread_id))
            local items = { {
                id = 0,
                data = { text = text }
            } }
            if resp then
                for idx, frame in ipairs(resp.stackFrames) do
                    ---@type loop.comp.ItemList.Item
                    local item = { id = idx, data = { frame = frame } }
                    table.insert(items, item)
                    if view.frame and frame.id == view.frame.id then cur_item_id = item.id end
                end
                if not cur_item_id and view.frame then
                    for idx, frame in ipairs(resp.stackFrames) do
                        if frame.name == view.frame.name
                            and frame.moduleId == view.frame.moduleId
                            and frame.line == view.frame.line then
                            cur_item_id = idx
                        end
                    end
                end
            end
            self:set_items(items)
            if cur_item_id then self:set_current_id(cur_item_id) end
        end)
end

return StackTrace
