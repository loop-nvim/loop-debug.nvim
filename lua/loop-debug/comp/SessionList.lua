local class = require('loop.tools.class')
local ItemList = require('loop.comp.ItemList')
local config = require('loop-debug.config')
local debugevents = require('loop-debug.debugevents')

---@class loopdebug.comp.SessionListComp : loop.comp.ItemList
---@field new fun(self: loopdebug.comp.SessionListComp): loopdebug.comp.SessionListComp
local SessionListComp = class(ItemList)

---@param id any
---@param data table
---@return loop.comp.ItemList.Chunk[]
local function _item_formatter(id, data)
    ---@type loopdebug.events.SessionInfo
    local name = data.name
    local state = data.state
    local is_paused = data.is_paused

    local symbols = config.current.symbols
    assert(symbols)

    local chunks = {}

    table.insert(chunks, {
        is_paused and symbols.paused or symbols.running,
        is_paused and "DiagnosticWarn" or "DiagnosticOk",
    })
    table.insert(chunks, { " ", nil })
    table.insert(chunks, {
        tostring(name or "unknown"),
        "Title",
    })
    if state and state ~= "running" then
        table.insert(chunks, { " ", nil })
        table.insert(chunks, { ("[%s]"):format(state), "DiagnosticInfo", })
    end
    if is_paused then
        table.insert(chunks, { " ", nil })
        table.insert(chunks, { "[paused]", "DiagnosticInfo" })
    end
    return chunks
end


function SessionListComp:init()
    ItemList.init(self, {
        formatter = _item_formatter,
        show_current_prefix = true,
    })

    ---@type table<number,loopdebug.events.SessionInfo>
    self._sessions = {}

    ---@type table<number,table>
    self._deferred_update_timers = {}

    ---@type loop.TrackerRef?
    self._events_tracker_ref = debugevents.add_tracker({
        on_debug_start = function()
            self._sessions = {}
            self:_refresh()
        end,
        on_debug_end = function()
            self._sessions = {}
            self:_refresh()
        end,
        on_session_added = function(id, info)
            self._sessions[id] = info
            self:_refresh()
        end,
        on_session_update = function(id, info)
            -- cancel any existing deferred timer for this session
            local prev_timer = self._deferred_update_timers[id]
            if prev_timer then
                prev_timer:stop()
                prev_timer:close()
                self._deferred_update_timers[id] = nil
            end
            if info.is_paused then
                -- immediate update for paused sessions
                self._sessions[id] = info
                self:_refresh()
            else
                -- schedule deferred update for running sessions
                local timer
                timer = vim.defer_fn(function()
                    -- make sure the timer is still registered (hasn't been canceled)
                    if self._deferred_update_timers[id] ~= timer then
                        return
                    end
                    self._sessions[id] = info
                    self:_refresh()
                    self._deferred_update_timers[id] = nil
                end, config.current.anti_flicker_delay)
                -- store timer handle immediately for future cancellation
                self._deferred_update_timers[id] = timer
            end
        end,
        on_session_removed = function(id)
            self._sessions[id] = nil
            local timer = self._deferred_update_timers[id]
            if timer then
                if timer:is_active() then timer:stop() end
                timer:close()
            end
            self._deferred_update_timers[id] = nil
            self:_refresh()
        end,
        on_view_udpate = function(view)
            self:set_current_id(view.session_id)
        end
    })
end

function SessionListComp:dispose()
    ItemList.dispose(self)
    if self._events_tracker_ref then
        self._events_tracker_ref.cancel()
    end
    for _, timer in pairs(self._deferred_update_timers) do
        if timer:is_active() then
            timer:stop()
        end
        timer:close()
    end
    self._deferred_update_timers = {}
end

---@param page loop.PageController
function SessionListComp:set_page(page)
    self._page = page
end

---@param buf_ctrl loop.CompBufferController
function SessionListComp:link_to_buffer(buf_ctrl)
    ItemList.link_to_buffer(self, buf_ctrl)
    buf_ctrl.disable_change_events()
end

function SessionListComp:_refresh()
    local session_ids = vim.tbl_keys(self._sessions)
    table.sort(session_ids)

    ---@type loop.comp.ItemList.Item[]
    local list_items = {}

    for _, sess_id in ipairs(session_ids) do
        local info = self._sessions[sess_id]
        --@type loop.pages.ItemListPage.Item
        local item = {
            id = sess_id,
            data = {
                name = info.name,
                state = info.state,
                is_paused = info.is_paused,
            }
        }
        table.insert(list_items, item)
    end
    self:set_items(list_items)
end

return SessionListComp
