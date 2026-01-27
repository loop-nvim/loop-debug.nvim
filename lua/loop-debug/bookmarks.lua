local M = {}

local Trackers = require("loop.tools.Trackers")
local uitools = require("loop.tools.uitools")
local wsinfo = require('loop.wsinfo')
local persistence = require('loop-debug.persistence')

---@class loopdebug.Bookmark
---@field id number
---@field file string
---@field line integer
---@field column integer|nil
---@field note string|nil

---@class loopdebug.bookmarks.Tracker
---@field on_set fun(bm:loopdebug.Bookmark)|nil
---@field on_removed fun(bm:loopdebug.Bookmark)|nil
---@field on_all_removed fun(bms:loopdebug.Bookmark[])|nil
---@field on_moved fun(bm:loopdebug.Bookmark,old_line:number)|nil

local _last_bookmark_id = 1000

---@type table<string,table<number,number>> -- file --> line --> id
local _source_bookmarks = {}

---@type table<number,loopdebug.Bookmark>
local _by_id = {} -- bookmarks by unique id

---@type loop.tools.Trackers<loopdebug.bookmarks.Tracker>
local _trackers = Trackers:new()

---@param callbacks loopdebug.bookmarks.Tracker
---@param no_snapshot boolean?
---@return loop.TrackerRef
function M.add_tracker(callbacks, no_snapshot)
    local tracker_ref = _trackers:add_tracker(callbacks)
    if not no_snapshot then
        --initial snapshot
        ---@type loopdebug.Bookmark[]
        local current = vim.tbl_values(_by_id)
        if callbacks.on_set then
            for _, bm in ipairs(current) do
                callbacks.on_set(bm)
            end
        end
    end
    return tracker_ref
end

local function _norm(file)
    if not file or file == "" then return file end
    return vim.fn.fnamemodify(file, ":p")
end

--- Check if a file has a bookmark on a specific line.
---@param file string File path
---@param line integer Line number
---@return number|nil
---@return loopdebug.Bookmark|nil
local function _get_source_bookmark(file, line)
    local lines = _source_bookmarks[file]
    if not lines then return nil, nil end
    local id = lines[line]
    if not id then return nil, nil end
    return id, _by_id[id]
end

--- Check if a file has a bookmark on a specific line.
---@param file string File path
---@param line integer Line number
---@return boolean has_bookmark True if a bookmark exists on that line
local function _have_source_bookmark(file, line)
    return _get_source_bookmark(file, line) ~= nil
end

--- Remove a single bookmark.
---@param file string File path
---@param line integer Line number
---@return boolean removed True if a bookmark was removed
local function _remove_source_bookmark(file, line)
    local lines = _source_bookmarks[file]
    if not lines then return false end
    local id = lines[line]
    if not id then return false end
    local bm = _by_id[id]
    if bm then
        lines[line] = nil
        _by_id[id] = nil
        _trackers:invoke("on_removed", bm)
    end
    return true
end

---@param file string File path
local function _clear_file_bookmarks(file)
    local lines = _source_bookmarks[file]
    local removed = {}
    if not lines then return end
    for _, id in pairs(lines) do
        local bm = _by_id[id]
        if bm then
            table.insert(removed, bm)
            _by_id[id] = nil
        end
    end
    _source_bookmarks[file] = nil
    for _, bm in pairs(removed) do
        _trackers:invoke("on_removed", bm)
    end
end

local function _clear_bookmarks()
    ---@type loopdebug.Bookmark[]
    local removed = vim.tbl_values(_by_id)
    _by_id = {}
    _source_bookmarks = {}
    _trackers:invoke("on_all_removed", removed)
end

--- Add a new bookmark.
---@param file string File path
---@param line integer Line number
---@param note? string Optional note
---@return boolean added
local function _set_source_bookmark(file, line, note)
    if _have_source_bookmark(file, line) then
        return false
    end
    local id = _last_bookmark_id + 1
    _last_bookmark_id = id
    ---@type loopdebug.Bookmark
    local bm = {
        id = id,
        file = file,
        line = line,
        note = note
    }
    _by_id[id] = bm
    _source_bookmarks[file] = _source_bookmarks[file] or {}
    local lines = _source_bookmarks[file]
    lines[line] = id
    _trackers:invoke("on_set", bm)
    return true
end

---@param file string
---@param lnum number
function M.toggle_bookmark(file, lnum)
    file = _norm(file)
    if not _remove_source_bookmark(file, lnum) then
        _set_source_bookmark(file, lnum)
    end
end

---@param file string
---@param lnum number
---@return boolean
function M.set_bookmark(file, lnum)
    file = _norm(file)
    return _set_source_bookmark(file, lnum)
end

---@param file string
---@param lnum number
---@param message string
function M.set_note_bookmark(file, lnum, message)
    if type(message) == "string" and #message > 0 then
        file = _norm(file)
        _remove_source_bookmark(file, lnum)
        _set_source_bookmark(file, lnum, message)
    end
end

---@param id number
---@param newline number
---@return boolean
function M.update_bookmark_line(id, newline)
    local bm = _by_id[id]
    if not bm or bm.line == newline then
        return false
    end
    local old_line = bm.line
    local file = bm.file
    local lines = _source_bookmarks[file]
    if lines then
        lines[old_line] = nil
        lines[newline] = id
    end
    bm.line = newline
    _trackers:invoke("on_moved", bm, old_line)
    return true
end

---@param file string
function M.clear_file_bookmarks(file)
    _clear_file_bookmarks(_norm(file))
end

--- clear all bookmarks.
function M.clear_all_bookmarks()
    _clear_bookmarks()
end

---@return loopdebug.Bookmark[]
function M.get_bookmarks()
    ---@type loopdebug.Bookmark[]
    local bms = {}
    for _, bm in pairs(_by_id) do
        table.insert(bms, bm)
    end
    return bms
end

---@param bookmarks loopdebug.Bookmark[]
local function _set_bookmarks(bookmarks)
    _clear_bookmarks()
    table.sort(bookmarks, function(a, b)
        if a.file ~= b.file then return a.file < b.file end
        return a.line < b.line
    end)
    for _, bm in ipairs(bookmarks) do
        local file = vim.fn.fnamemodify(bm.file, ":p")
        _set_source_bookmark(file,
            bm.line,
            bm.note
        )
    end
    return true, nil
end
---@return boolean
function M.have_bookmarks()
    return next(_by_id) ~= nil
end

---@param handler fun(bm:loopdebug.Bookmark)
function M.for_each(handler)
    for _, bm in pairs(_by_id) do
        handler(bm)
    end
end

---@param command nil
---| "toggle"
---| "note"
---| "clear_file"
---| "clear_all"
function M.bookmarks_command(command)
    local ws_dir = wsinfo.get_ws_dir()
    if not ws_dir then
        vim.notify('No active workspace')
        return
    end
    command = command and command:match("^%s*(.-)%s*$") or ""
    if command == "" or command == "toggle" then
        local file, line = uitools.get_current_file_and_line()
        if file and line then
            M.toggle_bookmark(file, line)
        end
    elseif command == "note" then
        local file, line = uitools.get_current_file_and_line()
        if file and line then
            vim.ui.input({ prompt = "Enter bookmark note: " }, function(message)
                if message and message ~= "" then
                    M.set_note_bookmark(file, line, message)
                    print("Bookmark set at " .. file .. ":" .. line)
                end
            end)
        end
    elseif command == "clear_file" then
        local bufnr = vim.api.nvim_get_current_buf()
        if vim.api.nvim_buf_is_valid(bufnr) then
            local full_path = vim.api.nvim_buf_get_name(bufnr)
            if full_path and full_path ~= "" then
                uitools.confirm_action("Clear bookmarks in file", false, function(accepted)
                    if accepted == true then
                        M.clear_file_bookmarks(full_path)
                    end
                end)
            end
        end
    elseif command == "clear_all" then
        uitools.confirm_action("Clear all bookmarks", false, function(accepted)
            if accepted == true then
                M.clear_all_bookmarks()
            end
        end)
    else
        vim.notify('Invalid bookmarks subcommand: ' .. tostring(command))
    end
end

local _init_done = false
function M.init()
    if _init_done then return end
    _init_done = true
    persistence.add_tracker({
        on_ws_load = function()
            _set_bookmarks(persistence.get_config("bookmarks") or {})
        end,
        on_ws_unload = function()
        end,
        on_ws_will_save = function()
            persistence.set_config("bookmarks", M.get_bookmarks())
        end
    })
end

return M
