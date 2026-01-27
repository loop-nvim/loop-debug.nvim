local M         = {}

local Trackers  = require("loop.tools.Trackers")

---@alias loopdebug.ConfigElement "layout"|"watch"|"breakpoints"|"bookmarks"

---@class loopdebug.PersistenceData
---@field state loop.ExtensionState

---@type loopdebug.PersistenceData?
local _current_data

---@class loopdebug.persistence.Tracker
---@field on_ws_load fun()?
---@field on_ws_unload fun()?
---@field on_ws_will_save fun()?

---@type loop.tools.Trackers<loopdebug.persistence.Tracker>
local _trackers = Trackers:new()

---@param callbacks loopdebug.persistence.Tracker
---@return loop.TrackerRef
function M.add_tracker(callbacks)
    local ref = _trackers:add_tracker(callbacks)
    if _current_data and callbacks.on_ws_load then
        callbacks.on_ws_load()
    end
    return ref
end

---@param state loop.ExtensionState
function M.on_workspace_load(state)
    _current_data = {
        state = state
    }
    _trackers:invoke("on_ws_load")
end

function M.on_workspace_unload()
    _current_data = nil
    _trackers:invoke("on_ws_unload")
end

---@param state loop.ExtensionState
function M.on_state_will_save(state)
    _trackers:invoke_sync("on_ws_will_save")
end

function M.is_ws_open()
    return _current_data ~= nil
end

---@param element loopdebug.ConfigElement
---@param data table
function M.set_config(element, data) if _current_data then _current_data.state.set(element, data) end end

---@param element loopdebug.ConfigElement
---@return table?
function M.get_config(element) return _current_data and _current_data.state.get(element) end

return M
