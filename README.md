# loop-debug.nvim

Debug extension for [loop.nvim](https://github.com/mbfoss/loop.nvim). Adds a **debug** task type and debugging support via DAP (breakpoints, stepping, call stack, watch, REPL) inside the Loop UI. Supports multiple debuggers and sessions.

**Note:** This plugin uses its own DAP implementation and configuration. It does **not** require or depend on `nvim-dap`.

## Requirements

- **Neovim** ≥ 0.10  
- **loop.nvim**

Debug adapters (e.g. lldb-dap, debugpy, codelldb) are typically installed via [Mason](https://github.com/williamboman/mason.nvim) or your system; see each debugger below.

## Features

- **Debug task type** — Run debug sessions as loop tasks with `debugger`, `request` (launch/attach), and optional `command`, `cwd`, `env`, etc.
- **UI** — Breakpoints, call stack, watch expressions, debugger console (REPL), debuggee output (with optional run-in-terminal).
- **Multisession** — Multiple debug sessions; switch via `:Loop debug session`.
- **Persistence** — Breakpoints and related state are persisted per workspace.
- **Templates** — Predefined **Debug** tasks for Lua, LLDB, GDB, CodeLLDB, Node, Python, Go, Chrome, Bash, PHP, .NET, Java.

## Installation

**lazy.nvim**

```lua
{
    "mbfoss/loop-debug.nvim",
    dependencies = { "mbfoss/loop.nvim" },
}
```

**packer.nvim**

```lua
use {
    "mbfoss/loop-debug.nvim",
    requires = { "mbfoss/loop.nvim" },
}
```

## Quick Start

1. Install loop.nvim and loop-debug.nvim.
2. Open a loop workspace (`:Loop workspace open`).
3. Add a debug task: `:Loop task configure` and add a task from one of the templates in the **Debug** category.
4. Run the debug task: `:Loop task run` (or `:Loop task run Debug`).
5. Use `:Loop debug ui toggle` to show the debug UI.

## Commands

All commands live under `:Loop debug ...`.
Commands be selected using the command selector by typing `:Loop`

| Command | Description |
|--------|-------------|
| `:Loop debug ui` | Toggle / show / hide debug UI; `save_layout` to save layout |
| `:Loop debug breakpoint` | Manage breakpoints (see subcommands below) |
| `:Loop debug continue` | Continue execution |
| `:Loop debug continue_all` | Continue all sessions |
| `:Loop debug pause` | Pause execution |
| `:Loop debug step_over` | Step over |
| `:Loop debug step_in` | Step in |
| `:Loop debug step_out` | Step out |
| `:Loop debug step_back` | Step back (if supported) |
| `:Loop debug session` | Switch debug session |
| `:Loop debug thread` | Switch thread |
| `:Loop debug frame` | Switch stack frame |
| `:Loop debug inspect` | Inspect expression/variable |
| `:Loop debug terminate` | Terminate current session |
| `:Loop debug terminate_all` | Terminate all sessions |

**Breakpoint subcommands** (`:Loop debug breakpoint ...`):

`list`, `set`, `logpoint`, `conditional`, `enable`, `disable`, `toggle_enabled`, `disable_all`, `enable_all`, `delete`, `clear_file`, `clear_all`.


| Field | Type | Description |
|:---|:---|:---|
| `debugger` | `string` | Backend name (e.g., `gdb`, `lldb`, `debugpy`, `js-debug`, `go`, `chrome`, `netcoredbg`). |
| `request` | `string` | `"launch"` or `"attach"`. |
| `command` | `string \| string[]` | The program or command to run (primarily for `launch`). |
| `cwd` | `string` | Working directory. Defaults to `${wsdir}` if not specified. |
| `env` | `table<string, string>` | Environment variables for the debuggee process. |
| `stop_on_entry` | `boolean` | Whether to break immediately at the entry point. |
| `run_in_terminal` | `boolean` | Run the debuggee in an integrated terminal. |
| `processId` | `number \| string` | PID for attaching (supports macros like `${select-pid}`). |
| `host` | `string` | Hostname/IP for remote debugging. |
| `port` | `number \| string` | Port for remote debugging or inspector protocols. |
| `debug_options` | `table` | Flexible table for debugger-specific settings. |


All fields support [loop.nvim macros](https://github.com/mbfoss/loop.nvim) (e.g. `${file}`, `${wsdir}`, `${prompt:...}`, `${select-pid}`).

## Built-in Debuggers

| Debugger | Typical use | Adapter (e.g. Mason) |
|----------|-------------|----------------------|
| `lua` | Lua (local) | local-lua-debugger-vscode |
| `lua:remote` | Lua (attach) | — |
| `gdb` | C/C++ (GDB) | system GDB with `--interpreter=dap` |
| `lldb` | C/C++/Rust (LLDB) | lldb-dap |
| `codelldb` | C/C++/Rust (CodeLLDB) | codelldb |
| `js-debug` | Node.js | js-debug-adapter |
| `debugpy` | Python (launch) | debugpy |
| `debugpy:remote` | Python (attach) | debugpy |
| `go` | Go (Delve) | delve |
| `chrome` | Chrome | chrome-debug-adapter |
| `bash` | Bash | bash-debug-adapter |
| `php` | PHP (Xdebug) | php-debug |
| `java` | Java (attach) | jdtls / server |
| `netcoredbg` | .NET | netcoredbg |

Adapter paths are often resolved from Mason; install the matching package if a debugger fails to start.

## Debug UI

The debug UI gives you a full view of the debug sessions:

- **Sessions & threads** – See all active debug sessions, threads, and stack frames, and switch between them.
- **Call stack & scopes** – Inspect the current call stack and expand scopes to see locals, arguments, and other variables.
- **Watches** – Add and edit watch expressions; values are refreshed as you step through code (use `i` to insert watch expression, and `c` to change an existing expression).
- **Variables** – Inspect variables in the variables view (use `c` to to change the value of a variable, when supported by the adapter)
- **inline values** Local variables are shown as virtual text when a thread is paused (the treesitter parser for the file type must be installed for this to work, can be disabled in the config table).

## Templates

Under the **Debug** category, templates include:

- **Lua** — run, attach
- **LLDB** — run, attach
- **GDB** — run, attach
- **CodeLLDB** — run, attach
- **Node** — run, attach
- **Python** — run, attach
- **Go** — run, attach
- **Chrome** — run, attach
- **Bash** — run
- **PHP** — listen
- **.NET** — run, attach
- **Java** — attach

## Configuration

Optional setup:

```lua
require("loop-debug").setup({
    auto_switch_page = true,       -- Switch to debug page when session starts
    stack_levels_limit = 100,     -- Max stack frames
    enable_inlay_variables = true, -- Inline variable values in source
    anti_flicker_delay = 500,     -- ms
    debug_line_blend_color = 0xD65A5A, -- reddish tint
    sign_priority = {
        breakpoints = 80,
        currentframe = 100,
    },
    symbols = {
        running                  = "●",
        paused                   = "⏸",
        success                  = "✓",
        failure                  = "✗",
        debug_frame              = "▶",
        active_breakpoint        = "●",
        inactive_breakpoint      = "○",
        logpoint                 = "◆",
        inactive_logpoint        = "◇",
        cond_breakpoint          = "■",
        inactive_cond_breakpoint = "□",
        disabled_breakpoint      = "ø",
        disabled_logpoint        = "ø",
        disabled_cond_breakpoint = "ø",
    },
})
```


## Keymap suggestion
```lua
vim.keymap.set("n", "<leader>d", "<Nop>", { noremap = true })-- to avoid deleting text by accident
vim.keymap.set("n", "<leader>du", ":Loop debug ui<CR>", { desc = "Toggle UI", silent = true })
vim.keymap.set("n", "<leader>bb", ":Loop debug breakpoint toggle<CR>", { desc = "Toggle breakpoints", silent = true })
vim.keymap.set("n", "<leader>bd", ":Loop debug breakpoint delete<CR>", { desc = "Delete breakpoints", silent = true })
vim.keymap.set("n", "<leader>bc", ":Loop debug breakpoint conditional<CR>", { desc = "Set conditional breakpoint", silent = true })
vim.keymap.set("n", "<leader>bl", ":Loop debug breakpoint logpoint<CR>", { desc = "Set logpoint", silent = true })
vim.keymap.set("n", "<leader>bt", ":Loop debug breakpoint toggle_enabled<CR>", { desc = "Enable/disable breakpoint", silent = true })
vim.keymap.set("n", "<leader>bl", ":Loop debug breakpoint list<CR>", { desc = "List breakpoints", silent = true })
vim.keymap.set("n", "<leader>bE", ":Loop debug breakpoint enable_all<CR>", { desc = "Enable all breakpoints", silent = true })
vim.keymap.set("n", "<leader>bD", ":Loop debug breakpoint disable_all<CR>", { desc = "Disable all breakpoints", silent = true })
vim.keymap.set("n", "<leader>ds", ":Loop debug session<CR>", { desc = "Select debug session", silent = true })
vim.keymap.set("n", "<leader>dt", ":Loop debug thread<CR>", { desc = "Select thread", silent = true })
vim.keymap.set("n", "<leader>df", ":Loop debug frame<CR>", { desc = "Select stack frame", silent = true })
vim.keymap.set("n", "<leader>di", ":Loop debug inspect<CR>", { desc = "Inspect value", silent = true })
vim.keymap.set("n", "<leader>dp", ":Loop debug pause<CR>", { desc = "Pause execution", silent = true })
vim.keymap.set("n", "<leader>dl", ":Loop debug step_in<CR>", { desc = "Step into", silent = true })
vim.keymap.set("n", "<leader>dh", ":Loop debug step_out<CR>", { desc = "Step out", silent = true })
vim.keymap.set("n", "<leader>dj", ":Loop debug step_over<CR>", { desc = "Step over", silent = true })
vim.keymap.set("n", "<leader>dk", ":Loop debug step_back<CR>", { desc = "Step back", silent = true })
vim.keymap.set("n", "<leader>dc", ":Loop debug continue<CR>", { desc = "Continue execution", silent = true })
vim.keymap.set("n", "<leader>dC", ":Loop debug continue_all<CR>", { desc = "Continue debug", silent = true })
vim.keymap.set("n", "<leader>dk", ":Loop debug terminate<CR>", { desc = "Terminate debug", silent = true })
vim.keymap.set("n", "<leader>dK", ":Loop debug terminate_all<CR>", { desc = "Terminate debug", silent = true })
vim.keymap.set("n", "<A-l>", ":Loop debug step_in<CR>", { desc = "Step into", silent = true })
vim.keymap.set("n", "<A-h>", ":Loop debug step_out<CR>", { desc = "Step out", silent = true })
vim.keymap.set("n", "<A-j>", ":Loop debug step_over<CR>", { desc = "Step over", silent = true })
vim.keymap.set("n", "<A-c>", ":Loop debug continue_all<CR>", { desc = "Step back", silent = true })
vim.keymap.set("n", "<A-b>", ":Loop debug breakpoint toggle<CR>", { desc = "Toggle breakpoints", silent = true })
```

## License

MIT
