local M = {}

-- reasons that represent REAL execution stops
-- anything not in this set will be treated as spurious
local _non_spurious_stop_reasons = {
    ["step"] = true,
    ["breakpoint"] = true,
    ["exception"] = true,
    ["pause"] = true,
    ["entry"] = true,
    ["goto"] = true,
    ["function breakpoint"] = true,
    ["data breakpoint"] = true,
    ["instruction breakpoint"] = true,
}

---Returns true if stop should be treated as spurious
---@param reason string|nil
---@return boolean
function M.is_spurious_stop(reason)
    -- No reason? Treat as spurious (defensive default)
    if type(reason) ~= "string" then
        return true
    end
    -- If it's explicitly known to be a real stop → not spurious
    if _non_spurious_stop_reasons[reason] then
        return false
    end
    -- Everything else (including "function call") → spurious
    return true
end

--- Format a DAP error body into a human-readable string
--- @param body table|nil  DAP response body
--- @return string|nil
function M.dap_error_to_string(body)
    if not body or type(body) ~= "table" then
        return nil
    end

    local err = body.error
    if not err or type(err) ~= "table" then
        return nil
    end

    local fmt = err.format
    if type(fmt) ~= "string" or fmt == "" then
        return nil
    end

    local vars = err.variables or {}

    -- Replace {var} with variables[var]
    local msg = fmt:gsub("{(.-)}", function(key)
        local v = vars[key]
        if v == nil then
            return "{" .. key .. "}"
        end
        return tostring(v)
    end)

    return msg
end

---@param value  string|nil
---@param presentationHint loopdebug.proto.VariablePresentationHint|nil
---@return string
function M.format_variable(value, presentationHint)
    local hint = presentationHint
    value = value or ""
    if hint and hint.attributes and vim.list_contains(hint.attributes, "rawString") then
        -- unwrap quotes and decode escape sequences
        value = value
            :gsub("^(['\"])(.*)%1$", "%2")
            :gsub("\\n", "\n")
            :gsub("\\t", "\t")
    end
    return value
end

return M
