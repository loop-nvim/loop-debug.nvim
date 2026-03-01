local M = {}

local run = require('loop-debug.run')

---@param ext_data loop.ExtensionData
function M.get_task_type_provider(ext_data)
    ---@type loop.TaskTypeProvider
    return
    {
        get_task_schema = function()
            local schema = require('loop-debug.schema')
            return schema
        end,
        start_one_task = function(task, page_group, on_exit)
            ---@cast task loopdebug.Task
            return run.start_debug_task(ext_data.ws_dir, task, page_group, on_exit)
        end,
        on_tasks_cleanup = function()
        end,
    }
end

function M.get_task_template_provider()
    local sorted = false
    ---@type loop.TaskTemplateProvider
    return
    {
        get_task_templates = function()
            local templates = require('loop-debug.templates')
            if not sorted then
                table.sort(templates, function(a, b)
                    return a.name < b.name
                end)
                sorted = true
            end
            return templates
        end,
    }
end

return M
