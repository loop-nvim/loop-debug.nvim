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
    local info = data.info or {}

    local symbols = config.current.symbols
    assert(symbols)

    local chunks = {}
    local nb_paused = info.nb_paused_threads or 0
    local is_paused = nb_paused > 0

    table.insert(chunks, {
        is_paused and symbols.paused or symbols.running,
        is_paused and "DiagnosticWarn" or "DiagnosticOk",
    })
    table.insert(chunks, { " ", nil })
    table.insert(chunks, {
        tostring(info.name or "unknown"),
        "Title",
    })
    if info.state and info.state ~= "running" then
        table.insert(chunks, { " ", nil })
        table.insert(chunks, {
            "(" .. info.state .. ")",
            "Comment",
        })
    end
    if nb_paused > 0 then
        local s = nb_paused > 1 and "s" or ""
        table.insert(chunks, { " ", nil })
        table.insert(chunks, {
            string.format("[%d paused thread%s]", nb_paused, s),
            "DiagnosticWarn",
        })
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
            self._sessions[id] = info
            self:_refresh()
        end,
        on_session_removed = function(id)
            self._sessions[id] = nil
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
    if next(self._sessions) == nil then
        --@type loop.pages.ItemListPage.Item
        local item = {
            id = 0,
            ---@class loopdebug.mgr.TaskPageItemData
            data = {
                label = "No debug sessions",
                nb_paused_threads = 0,
            }
        }
        self:set_items({ item })
        return
    end

    local session_ids = vim.tbl_keys(self._sessions)
    table.sort(session_ids)

    ---@type loop.comp.ItemList.Item[]
    local list_items = {}

    for _, sess_id in ipairs(session_ids) do
        local info = self._sessions[sess_id]
        --@type loop.pages.ItemListPage.Item
        local item = {
            id = sess_id,
            ---@class loopdebug.mgr.TaskPageItemData
            data = {
                info = info
            }
        }
        table.insert(list_items, item)
    end

    self:set_items(list_items)
end

return SessionListComp
