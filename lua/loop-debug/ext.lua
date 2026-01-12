local persistence = require('loop-debug.persistence')
local task_provider = require('loop-debug.task_provider')
local cmd_provider = require('loop-debug.cmd_provider')

---@type loop.Extension
local extension =
{
    on_workspace_load = function(ext_data)
        persistence.on_workspace_load(ext_data.state)
        ext_data.register_cmd_provider("debug", cmd_provider)
        ext_data.register_task_provider("debug", task_provider)
    end,
    on_workspace_unload = function(_)
        persistence.on_workspace_unload()
    end,
    on_state_will_save = function(ext_data)
        persistence.on_state_will_save(ext_data.state)
    end,
}
return extension
