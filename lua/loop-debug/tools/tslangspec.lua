local M = {}

--- @class loopdebug.TSLangSpec
--- @field scope_nodes table<string, boolean> Nodes that create a new lexical scope

--- @type table<string, loopdebug.TSLangSpec>
local _lang_spec = {
    ---@type loopdebug.TSLangSpec
    python = {
        scope_nodes = {
            module              = true, -- file level
            function_definition = true,
            class_definition    = true,
            for_statement       = true,
            while_statement     = true,
            if_statement        = true,
            elif_clause         = true,
            else_clause         = true,
            try_statement       = true,
            except_clause       = true,
            finally_clause      = true,
            with_statement      = true,
            match_statement     = true, -- Python 3.10+
            case_clause         = true,
        },
    },

    lua = {
        scope_nodes = {
            chunk                      = true, -- file level
            function_declaration       = true,
            local_function_declaration = true,
            do_statement               = true,
            while_statement            = true,
            repeat_statement           = true,
            if_statement               = true,
            for_numeric_statement      = true, -- numeric for
            for_generic_statement      = true, -- generic for
        },
    },

    javascript = {
        scope_nodes = {
            program              = true, -- top-level
            ["function"]         = true,
            function_declaration = true,
            arrow_function       = true,
            generator_function   = true,
            method_definition    = true,
            class_body           = true,
            class_declaration    = true,
            class                = true,
            for_statement        = true,
            for_in_statement     = true,
            for_of_statement     = true,
            while_statement      = true,
            do_statement         = true,
            if_statement         = true,
            switch_statement     = true,
            try_statement        = true,
            catch_clause         = true,
            finally_clause       = true,
            block                = true,
            lexical_declaration  = true, -- let / const create block scope
        },
    },

    typescript = {
        scope_nodes = {
            program              = true,
            ["function"]         = true,
            function_declaration = true,
            arrow_function       = true,
            generator_function   = true,
            method_definition    = true,
            class_body           = true,
            class_declaration    = true,
            for_statement        = true,
            for_in_statement     = true,
            for_of_statement     = true,
            while_statement      = true,
            do_statement         = true,
            if_statement         = true,
            switch_statement     = true,
            try_statement        = true,
            catch_clause         = true,
            finally_clause       = true,
            block                = true,
        },
    },

    -- Very basic fallback for C/C++/Java/Rust/etc.
    ["default"] = {
        scope_nodes = {
            compound_statement  = true, -- { ... }
            function_definition = true,
            for_statement       = true,
            while_statement     = true,
            do_statement        = true,
            if_statement        = true,
            switch_statement    = true,
            class_specifier     = true,
            struct_specifier    = true,
        },
    },
}

--- Get Tree-sitter language specification for variable/scope detection
--- @param filetype string usually vim.bo.filetype
--- @return loopdebug.TSLangSpec
function M.get_lang_spec(filetype)
    -- Some common aliases / fallbacks
    local aliases = {
        ["c"]       = "default",
        ["cpp"]     = "default",
        ["java"]    = "default",
        ["rust"]    = "default",
        ["go"]      = "default",
        ["c_sharp"] = "default",
        ["zig"]     = "default",
        ["tsx"]     = "typescript",
        ["jsx"]     = "javascript",
    }

    local key = aliases[filetype] or filetype

    return _lang_spec[key] or _lang_spec["default"]
end

return M
