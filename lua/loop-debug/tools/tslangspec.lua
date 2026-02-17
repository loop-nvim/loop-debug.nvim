local M = {}

--- @class loopdebug.TSLangSpec
--- @field scope_nodes table<string, boolean> Nodes that create a new lexical scope
--- @field decl_nodes  table<string, boolean> Nodes that declare/bind a new variable name

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
        decl_nodes = {
            assignment            = true, -- x = 1
            augmented_assignment  = true, -- x += 1
            for_statement         = true, -- for x in ...
            function_definition   = true, -- def name(
            class_definition      = true, -- class Name:
            import_statement      = true,
            import_from_statement = true,
            parameters            = true, -- (self, a, b)
            parameter             = true, -- individual param node
            default_parameter     = true,
            list_parameter        = true, -- *args
            dict_parameter        = true, -- **kwargs
            typed_parameter       = true, -- x: int
        }
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
        decl_nodes = {
            variable_declaration       = true, -- local x = ...
            local_variable_declaration = true,
            function_declaration       = true,
            local_function_declaration = true,
            parameter                  = true,
            variadic_parameter         = true, -- ...
        }
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
        decl_nodes = {
            -- Main declaration wrappers
            variable_declaration           = true, -- var x = …
            lexical_declaration            = true, -- let x = … / const x = …
            -- The actual binding nodes inside them
            variable_declarator            = true, -- x in const x = 10
            -- Functions & classes
            function_declaration           = true,
            generator_function_declaration = true,
            class_declaration              = true,
            -- Parameters
            formal_parameters              = true,
            parameter                      = true,
            rest_parameter                 = true,
            -- Class fields / object shorthand
            public_field_definition        = true, -- class { x = 1 }
            property_identifier            = true, -- in { x } shorthand
        }
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
        decl_nodes = {
            variable_declarator     = true,
            function_declaration    = true,
            variable_declaration    = true,
            formal_parameters       = true,
            required_parameter      = true,
            optional_parameter      = true,
            rest_parameter          = true,
            class_declaration       = true,
            method_definition       = true,
            property_declaration    = true, -- class fields
            public_field_definition = true,
        }
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
        decl_nodes = {
            declaration           = true,
            init_declarator       = true,
            parameter_declaration = true,
            function_declarator   = true,
            declarator            = true,
            pointer_declarator    = true,
            array_declarator      = true,
            function_definition   = true,
            reference_declarator  = true
        }
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
