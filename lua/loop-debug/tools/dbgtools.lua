local M = {}

local MAX_INSPECT_BYTES = 512

--- Gets the expression to send to dap.evaluate()
---@param opts vim.api.keyset.create_user_command.command_args
---@return string|nil expr
---@return string|nil err
function M.get_value_for_inspect(opts)
    local expr = vim.fn.expand("<cword>")
    if expr == "" then
        return nil, "no expression under cursor"
    elseif #expr > MAX_INSPECT_BYTES then
        return nil, "expression under cursor is too large to inspect"
    end

    return expr, nil
end

return M
