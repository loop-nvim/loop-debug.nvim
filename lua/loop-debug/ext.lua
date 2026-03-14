local persistence   = require('loop-debug.persistence')
local task_provider = require('loop-debug.task_provider')
local cmd_provider  = require('loop-debug.cmd_provider')
local sideviewdef   = require('loop-debug.sideviewdef')

local _init_done    = false

---@type loop.Extension
local extension     =
{
    on_workspace_load = function(ext_data)
        if not _init_done then
            _init_done = true
            require('loop-debug.breakpoints').init()
            require('loop-debug.curframe').init()
            require('loop-debug.inlinevars').init()
        end

        persistence.on_workspace_load(ext_data.state)
        local sideview_ctrl = ext_data.register_side_view("debug", sideviewdef.get_sideview_def())
        ext_data.register_user_command("debug", cmd_provider.get_cmd_provider(ext_data))
        ext_data.register_task_type("debug", task_provider.get_task_type_provider(ext_data, sideview_ctrl))
        ext_data.register_task_templates("Debug", task_provider.get_task_template_provider())
    end,
    on_workspace_unload = function(_)
        persistence.on_workspace_unload()
    end,
    on_state_will_save = function(ext_data)
        persistence.on_state_will_save(ext_data.state)
    end,
}
return extension
