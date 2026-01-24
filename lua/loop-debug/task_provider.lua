local M = {}

local run = require('loop-debug.run')

function M.get_task_type_provider()
    ---@type loop.TaskTypeProvider
    return
    {
        get_task_schema = function()
            local schema = require('loop-debug.schema')
            return schema
        end,
        start_one_task = run.start_debug_task,
        on_tasks_cleanup = function()
            --ui.hide()
        end,
    }
end

function M.get_task_template_provider()
    ---@type loop.TaskTemplateProvider
    return
    {
        get_task_templates = function()
            local templates = require('loop-debug.templates')
            return templates
        end,
    }
end

return M
