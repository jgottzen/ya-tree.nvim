# ya-tree.nvim

Ya-Tree is sidebar plugin with file browser, Git status, search and buffers
trees. Additional trees can easily be created.

## Features

- Git integration, including [yadm](https://yadm.io/), updates when working tree status changes.
- Directory watching for automatically updating the state of the file tree.
- Search.
- Go to node with path completion.
- Basic file operations.
- LSP Diagnostics.
- One sidebar per tabpage.
- One or more trees per sidebar.

## Requirements

 - [neovim](https://github.com/neovim/neovim/wiki/Installing-Neovim) >= 0.7.0
 - [plenary.nvim](https://github.com/nvim-lua/plenary.nvim)
 - [nui.nvim](https://github.com/MunifTanjim/nui.nvim)
 - [nvim-web-devicons](https://github.com/nvim-tree/nvim-web-devicons) (optional)

### Installation with Packer:
```lua
use({
  "jgottzen/ya-tree.nvim",
  config = function()
    require("ya-tree").setup()
  end,
  requires = {
    "nvim-lua/plenary.nvim",
    "MunifTanjim/nui.nvim",
    "nvim-tree/nvim-web-devicons", -- optional, used for displaying icons
  },
})
```
## Commands

ya-tree.nvim provides the following commands, and are enabled upon calling `ya-tree.setup()`.

### YaTreeOpen

The `YaTreeOpen` command accepts arguments for how the sidebar should be
opened. Arguments are either key-value pairs or a single value.

The arugments can be specific in any order:

`focus`

Type: single value.

Whether to focus the sidebar.

`:YaTreeOpen focus`

`tree`

Type: key-value pair.

Which tree to open in the sidebar, and focus on.

```vim
:YaTreeOpen tree=filesystem
```
The builtin trees are:
- `filesystem`: Regular file browser.
- `git`:        Current git status.
- `search`:     Search results.
- `buffers`:    List of currently open buffers.

`path`

Type: key-value pair.

Which path to open, or a file to expand to in the tree.

```vim
:YaTreeOpen path=./path/to/file.rs
:YaTreeOpen path=%
:YaTreeOpen path=/path/to/directory
```

If the path is located below the current tree root, the tree expands to the path, `%` expands to the current buffer.
If the path is not located in the tree the root is changed to the path.

`position`

Type: key-value pair.

Where the sidebar should be positioned.

```vim
:YaTreeOpen position=left
```

The positions are: `left`, `right`, `top`, `bottom`.

`size`

Type: key-value pair.

The size of the sidebar.

```vim
:YaTreeOpen size=20
```

Examples:

- `YaTreeOpen size=20 focus tree=git position=top` Open the Git tree at the top with a heigh of 20, and focus it.
- `YaTreeOpen` Open the sidebar, in the last used position and size, or the configured size.
- `YaTreeOpen tree=filesystem path=/path/to/directory` Open the filesystem tree and change the root directory to `/path/to/directory`.
- `YaTreeOpen path=%` Open the current tree, or filesystem, and expand the tree to the path of the current buffer, if possible. If the path is not located in the current root directory, the root will change the directory containing the path.

The lua api is:

```lua
---@class Yat.OpenWindowArgs
---@field path? string The path to open.
---@field focus? boolean Whether to focus the tree window.
---@field tree? Yat.Trees.Type Which type of tree to open, defaults to the current tree, or `"filesystem"` if no current tree exists.
---@field position? Yat.Ui.Position Where the tree window should be positioned.
---@field size? integer The size of the tree window, either width or height depending on position.
---@field tree_args? table<string, any> Any tree specific arguments.

---@param opts? Yat.OpenWindowArgs
require("ya-tree").open(opts)
```

### YaTreeClose

Closes the sidebar.

```vim
:YaTreeClose
```

The lua api is:

```lua
require("ya-tree").close()
```

### YaTreeToggle

Toggles the sidebar.

```vim
:YaTreeToggle
```

The lua api is:

```lua
require("ya-tree").toggle()
```

## Configuration

The `ya-tree.setup()` function must be run for YaTree to be properly
initialized. It takes an optional table argument.

The table argument is fully annotated with `EmmyLua`.

<details>

<summary><b>Default Configuration</b></summary>

```lua
---@class Yat.Config
---@field close_if_last_window boolean Force closing the YaTree window when it is the last window in the tabpage, default: `false`.
---@field follow_focused_file boolean Update the focused file in the tree on `BufEnter`, default: `false`.
---@field move_cursor_to_name boolean Keep the cursor on the name in tree, default: `false`.
---@field move_buffers_from_sidebar_window boolean Move buffers from the sidebar window to the last used window, default: `true`.
---@field hijack_netrw boolean Replace the `netrw` file explorer, default: `true`.
---@field expand_all_nodes_max_depth integer The maximum depth to expand when expanding nodes, default: 5.
---@field load_sidebar_on_setup boolean Whether to load the sidebar and its trees on setup, which makes the first open faster, default: `false`.
---@field log Yat.Config.Log Logging configuration.
---@field auto_open Yat.Config.AutoOpen Auto-open configuration.
---@field cwd Yat.Config.Cwd Current working directory configuration.
---@field dir_watcher Yat.Config.DirWatcher Directory watching configuration.
---@field sorting Yat.Config.Sorting Sorting configuration.
---@field search Yat.Config.Search Search configuration.
---@field filters Yat.Config.Filters Filters configuration.
---@field git Yat.Config.Git Git configuration.
---@field diagnostics Yat.Config.Diagnostics Lsp diagnostics configuration.
---@field system_open Yat.Config.SystemOpen Open file with system command configuration.
---@field trash Yat.Config.Trash `trash-cli` configuration.
---@field view Yat.Config.View Tree view configuration.
---@field sidebar Yat.Config.Sidebar Sidebar configuration.
---@field actions Yat.Config.Actions User actions.
---@field trees Yat.Config.Trees Tree configurations.
---@field renderers Yat.Config.Renderers Renderer configurations.
local DEFAULT = {
  close_if_last_window = false,

  follow_focused_file = false,
  move_cursor_to_name = false,
  move_buffers_from_sidebar_window = true,

  hijack_netrw = true,

  expand_all_nodes_max_depth = 5,

  load_sidebar_on_setup = false,

  ---@alias Yat.Logger.Level "trace"|"debug"|"info"|"warn"|"error"

  ---@class Yat.Config.Log
  ---@field level Yat.Logger.Level The logging level used, default: `"warn"`.
  ---@field to_console boolean Whether to log to the console, default: `false`.
  ---@field to_file boolean Whether to log to the log file, default: `false`.
  ---@field namespaces string[] For which namespaces logging is enabled, default: `{ "ya-tree", "actions", "events", "fs", "nodes", "trees", "ui", "git", "job", "sidebar", "lib" }`.
  log = {
    level = "warn",
    to_console = false,
    to_file = false,
    namespaces = { "ya-tree", "actions", "events", "fs", "nodes", "trees", "ui", "git", "job", "sidebar", "lib" },
  },

  ---@class Yat.Config.AutoOpen
  ---@field on_setup boolean Automatically open the sidebar when running setup, default: `false`.
  ---@field on_new_tab boolean Automatically open the sidebar when opening a new tabpage, default: `false`.
  ---@field focus_sidebar boolean Whether to focus the sidebar when automatically opened, default: `false`.
  auto_open = {
    on_setup = false,
    on_new_tab = false,
    focus_sidebar = false,
  },

  ---@class Yat.Config.Cwd
  ---@field follow boolean Update the tree root directory on `DirChanged`, default: `false`.
  ---@field update_from_tree boolean Update the *tabpage* cwd when changing root directory in the tree, default: `false`.
  cwd = {
    follow = false,
    update_from_tree = false,
  },

  ---@class Yat.Config.DirWatcher
  ---@field enable boolean Whether directory watching is enabled, default: `true`.
  ---@field exclude string[] The directory names to exclude from watching, `".git"` directories are always excluded.
  dir_watcher = {
    enable = true,
    exclude = {},
  },

  ---@alias Yat.Nodes.SortBy "name"|"type"|"extension"

  ---@class Yat.Config.Sorting
  ---@field directories_first boolean Whether to sort directories first, default: `true`.
  ---@field case_sensitive boolean Whether to use case sensitive sort, default: `false`.
  ---@field sort_by Yat.Nodes.SortBy|fun(a: Yat.Node, b: Yat.Node):boolean What to sort by, or a user specified function, default: `"name"`.
  sorting = {
    directories_first = true,
    case_sensitive = false,
    sort_by = "name",
  },

  ---@class Yat.Config.Search
  ---@field max_results integer Max number of search results, only `fd` supports it, setting to 0 will disable it, default: `200`.
  ---@field cmd? string Override the search command to use, default: `nil`.
  ---@field args? string[]|fun(cmd: string, term: string, path:string, config: Yat.Config):string[] Override the search command arguments to use, default: `nil`.
  search = {
    max_results = 200,
    cmd = nil,
    args = nil,
  },

  ---@class Yat.Config.Filters
  ---@field enable boolean If filters are enabled, toggleable, default: `true`.
  ---@field dotfiles boolean If dotfiles should be hidden, default: `true`.
  ---@field custom string[] Custom file/directory names to hide, default: `{}`.
  filters = {
    enable = true,
    dotfiles = true,
    custom = {},
  },

  ---@class Yat.Config.Git
  ---@field enable boolean If git should be enabled, default: `true`.
  ---@field all_untracked boolean If `git status` checks should include all untracked files: default: `false`.
  ---@field show_ignored boolean Whether to show git ignored files in the tree, toggleable, default: `true`.
  ---@field watch_git_dir boolean Whether to watch the repository `.git` directory for changes, using `fs_poll`, default: `true`.
  ---@field watch_git_dir_interval integer Interval for polling, in milliseconds, default: `1000`.
  ---@field yadm Yat.Config.Git.Yadm `yadm` configuration.
  git = {
    enable = true,
    all_untracked = false,
    show_ignored = true,
    watch_git_dir = true,
    watch_git_dir_interval = 1000,

    ---@class Yat.Config.Git.Yadm
    ---@field enable boolean Whether yadm is enabled, requires git to be enabled, default: `false`.
    yadm = {
      enable = false,
    },
  },

  ---@class Yat.Config.Diagnostics
  ---@field enable boolean Show lsp diagnostics in trees, default: `true`.
  ---@field debounce_time integer Debounce time in ms, for how often `DiagnosticChanged` is processed, default: `300`.
  ---@field propagate_to_parents boolean If the diagnostic status should be propagated to parents, default: `true`.
  diagnostics = {
    enable = true,
    debounce_time = 300,
    propagate_to_parents = true,
  },

  ---@class Yat.Config.SystemOpen
  ---@field cmd? string The system open command, if unspecified the detected OS determines the default, Linux: `xdg-open`, OS X: `open`, Windows: `cmd`.
  ---@field args string[] Any arguments for the system open command, default: `{}` for Linux and OS X, `{"/c", "start"}` for Windows.
  system_open = {
    cmd = nil,
    args = {},
  },

  ---@class Yat.Config.Trash
  ---@field enable boolean Whether to enable trashing (`trash-cli must be installed`), default: `true`.
  ---@field require_confirm boolean Confirm before trashing, default: `false`.
  trash = {
    enable = true,
    require_confirm = false,
  },

  ---@alias Yat.Ui.Position "left"|"right"|"top"|"bottom"

  ---@class Yat.Config.View
  ---@field size integer Size of the sidebar panel, default: `40`.
  ---@field position Yat.Ui.Position Where the sidebar is placed, default: `"left"`.
  ---@field number boolean Whether to show the number column, default: `false`.
  ---@field relativenumber boolean Whether to show relative numbers, default: `false`.
  ---@field popups Yat.Config.View.Popups Popup window configuration.
  view = {
    size = 40,
    position = "left",
    number = false,
    relativenumber = false,

    ---@class Yat.Config.View.Popups
    ---@field border string|string[] The border type for floating windows, default: `"rounded"`.
    popups = {
      border = "rounded",
    },
  },

  ---@alias Yat.Trees.Type "filesystem"|"buffers"|"git"|"search"|string

  ---@class Yat.Config.Sidebar
  ---@field single_mode boolean If the sidebar should be a single tree only, default: `false`.
  ---@field tree_order Yat.Trees.Type[] In which order the tree sections appear, default: `{ "filesystem", "search", "git", "buffers" }`.
  ---@field trees_always_shown Yat.Trees.Type[] Which trees are always present, default: `{ "filesystem" }`.
  ---@field section_layout Yat.Config.Sidebar.SectionLayout Layout configuration.
  sidebar = {
    single_mode = false,
    tree_order = { "filesystem", "search", "git", "buffers" },
    trees_always_shown = { "filesystem" },

    ---@class Yat.Config.Sidebar.SectionLayout
    ---@field header Yat.Config.Sidebar.SectionLayout.Header Header configuration.
    ---@field footer Yat.Config.Sidebar.SectionLayout.Footer Footer configuration.
    section_layout = {
      ---@class Yat.Config.Sidebar.SectionLayout.Header
      ---@field enable boolean Whether to show the section header, e.g. `trees.filesystem.section_icon` and `trees.filesystem.section_name`, default: `true`.
      ---@field empty_line_before_tree boolean Whether to show an empty line before the tree, default: `true`.
      header = {
        enable = true,
        empty_line_before_tree = true,
      },
      ---@class Yat.Config.Sidebar.SectionLayout.Footer
      ---@field enable boolean Whether to show the section footer, i.e. the divider, default: `true`.
      ---@field divider_char string The divider used between sections, default: `"─"`.
      ---@field empty_line_after_tree boolean Whether to show an empty line between the tree and the divider, default: `true`.
      ---@field empty_line_after_divider boolean Whether to show an empty line after the divider, default: `true`.
      footer = {
        enable = true,
        divider_char = "─",
        empty_line_after_tree = true,
        empty_line_after_divider = true,
      },
    },
  },

  ---@alias Yat.Action.Fn async fun(tree: Yat.Tree, node: Yat.Node, sidebar: Yat.Sidebar)

  ---@alias Yat.Actions.Mode "n"|"v"|"V"

  ---@class Yat.Action
  ---@field fn Yat.Action.Fn
  ---@field desc string
  ---@field trees Yat.Trees.Type[]
  ---@field modes Yat.Actions.Mode[]
  ---@field node_independent boolean

  ---@class Yat.Config.Actions : { [string]: Yat.Action }
  actions = {},

  ---@class Yat.Config.Mapping.Custom Key mapping for user functions configuration.
  ---@field modes Yat.Actions.Mode[] The mode(s) for the keybinding.
  ---@field fn Yat.Action.Fn User function.
  ---@field desc? string Description of what the mapping does.
  ---@field node_independent? boolean If the action can be invoked without a `node`.

  ---@class Yat.Config.Trees.GlobalMappings
  ---@field disable_defaults boolean Whether to disable all default mappings, default: `false`.
  ---@field list table<string, Yat.Trees.Tree.SupportedActions|Yat.Actions.Name|string|Yat.Config.Mapping.Custom> Map of key mappings, an empty string, `""`, disables the mapping.

  ---@class Yat.Config.Trees.Mappings
  ---@field disable_defaults boolean Whether to disable all default mappings, default: `false`.
  ---@field list table<string, Yat.Actions.Name|string|Yat.Config.Mapping.Custom> Map of key mappings, an empty string, `""`, disables the mapping.

  ---@alias Yat.Ui.Renderer.Name "indentation"|"icon"|"name"|"modified"|"repository"|"symlink_target"|"git_status"|"diagnostics"|"buffer_info"|"clipboard"|string

  ---@class Yat.Config.Trees.Renderer
  ---@field name Yat.Ui.Renderer.Name The name of the renderer.
  ---@field override Yat.Config.BaseRendererConfig The renderer specific configuration.

  ---@class Yat.Config.Trees.Renderers
  ---@field directory Yat.Config.Trees.Renderer[] Which renderers to use for directories, in order.
  ---@field file Yat.Config.Trees.Renderer[] Which renderers to use for files, in order

  ---@class Yat.Config.Trees.Tree
  ---@field section_icon string The icon for the section in the sidebar.
  ---@field section_name string The name of section the in the sidebar.
  ---@field mappings Yat.Config.Trees.Mappings The tree specific mappings.
  ---@field renderers Yat.Config.Trees.Renderers The tree specific renderers.

  ---@class Yat.Config.Trees : { [Yat.Trees.Type] : Yat.Config.Trees.Tree }
  ---@field global_mappings Yat.Config.Trees.GlobalMappings Mappings that applies to all trees.
  ---@field filesystem Yat.Config.Trees.Filesystem Filesystem tree configuration.
  ---@field search Yat.Config.Trees.Search Search tree configuration.
  ---@field git Yat.Config.Trees.Git Git tree configuration.
  ---@field buffers Yat.Config.Trees.Buffers Buffers tree configuration.
  trees = {
    global_mappings = {
      disable_defaults = false,
      list = {
        ["q"] = "close_window",
        ["gx"] = "system_open",
        ["?"] = "open_help",
        ["<C-i>"] = "show_node_info",
        ["<C-x>"] = "close_tree",
        ["gT"] = "focus_prev_tree",
        ["gt"] = "focus_next_tree",
        ["<C-g>"] = "open_git_tree",
        ["b"] = "open_buffers_tree",
        ["<CR>"] = "open",
        ["o"] = "open",
        ["<2-LeftMouse>"] = "open",
        ["<C-v>"] = "vsplit",
        ["<C-s>"] = "split",
        ["<C-t>"] = "tabnew",
        ["<Tab>"] = "preview",
        ["<C-Tab>"] = "preview_and_focus",
        ["y"] = "copy_name_to_clipboard",
        ["Y"] = "copy_root_relative_path_to_clipboard",
        ["gy"] = "copy_absolute_path_to_clipboard",
        ["<BS>"] = "close_node",
        ["Z"] = "close_all_nodes",
        ["z"] = "close_all_child_nodes",
        ["E"] = "expand_all_nodes",
        ["e"] = "expand_all_child_nodes",
        ["R"] = "refresh_tree",
        ["P"] = "focus_parent",
        ["<"] = "focus_prev_sibling",
        [">"] = "focus_next_sibling",
        ["K"] = "focus_first_sibling",
        ["J"] = "focus_last_sibling",
      },
    },
    ---@class Yat.Config.Trees.Filesystem : Yat.Config.Trees.Tree
    ---@field section_name string The name of the section in the sidebar, default: `"Files"`.
    ---@field section_icon string The icon for the section in the sidebar, default: `""`.
    ---@field completion Yat.Config.Trees.Filesystem.Completion Path completion for tree search.
    ---@field mappings Yat.Config.Trees.Filesystem.Mappings Tree specific mappings.
    ---@field renderers Yat.Config.Trees.Renderers Tree specific renderers.
    filesystem = {
      section_name = "Files",
      section_icon = "",
      ---@class Yat.Config.Trees.Filesystem.Completion
      ---@field on "root"|"node" Whether to complete on the tree root directory or the current node, ignored if `setup` is set, default: `"root"`.
      ---@field setup? fun(self: Yat.Trees.Filesystem, node: Yat.Node): string function for setting up completion, the returned string will be set as `completefunc`, default: `nil`.
      completion = {
        on = "root",
        setup = nil,
      },
      ---@class Yat.Config.Trees.Filesystem.Mappings : Yat.Config.Trees.Mappings
      ---@field disable_defaults boolean Whether to disable all default mappings, default: `false`.
      ---@field list table<string, Yat.Trees.Filesystem.SupportedActions|string|Yat.Config.Mapping.Custom> Map of key mappings, an empty string, `""`, disables the mapping.
      mappings = {
        disable_defaults = false,
        list = {
          ["a"] = "add",
          ["r"] = "rename",
          ["d"] = "delete",
          ["D"] = "trash",
          ["c"] = "copy_node",
          ["x"] = "cut_node",
          ["p"] = "paste_nodes",
          ["<C-c>"] = "clear_clipboard",
          ["<2-RightMouse>"] = "cd_to",
          ["<C-]>"] = "cd_to",
          ["."] = "cd_to",
          ["-"] = "cd_up",
          ["I"] = "toggle_ignored",
          ["H"] = "toggle_filter",
          ["S"] = "search_for_node_in_tree",
          ["/"] = "search_interactively",
          ["f"] = "search_once",
          ["ga"] = "git_stage",
          ["gu"] = "git_unstage",
          ["gr"] = "git_revert",
          ["<C-r>"] = "check_node_for_git",
          ["[c"] = "focus_prev_git_item",
          ["]c"] = "focus_next_git_item",
          ["[e"] = "focus_prev_diagnostic_item",
          ["]e"] = "focus_next_diagnostic_item",
        },
      },
      renderers = {
        directory = {
          { name = "indentation" },
          { name = "icon" },
          { name = "name" },
          { name = "repository", override = { show_status = false } },
          { name = "symlink_target" },
          { name = "git_status" },
          { name = "diagnostics" },
          { name = "clipboard" },
        },
        file = {
          { name = "indentation" },
          { name = "icon" },
          { name = "name", override = { use_git_status_colors = true } },
          { name = "symlink_target" },
          { name = "modified" },
          { name = "git_status" },
          { name = "diagnostics" },
          { name = "clipboard" },
        },
      },
    },
    ---@class Yat.Config.Trees.Search : Yat.Config.Trees.Tree
    ---@field section_icon string The icon for the section in the sidebar, default" `""`.
    ---@field section_name string The name of the section in the sidebar, default: `"Search"`.
    ---@field mappings Yat.Config.Trees.Search.Mappings Tree specific mappings.
    ---@field renderers Yat.Config.Trees.Renderers Tree specific renderers.
    search = {
      section_name = "Search",
      section_icon = "",
      ---@class Yat.Config.Trees.Search.Mappings : Yat.Config.Trees.Mappings
      ---@field disable_defaults boolean Whether to disable all default mappings, default: `false`.
      ---@field list table<string, Yat.Trees.Search.SupportedActions|string|Yat.Config.Mapping.Custom> Map of key mappings, an empty string, `""`, disables the mapping.
      mappings = {
        disable_defaults = false,
        list = {
          ["<C-]>"] = "cd_to",
          ["."] = "cd_to",
          ["I"] = "toggle_ignored",
          ["H"] = "toggle_filter",
          ["S"] = "search_for_node_in_tree",
          ["/"] = "search_interactively",
          ["f"] = "search_once",
          ["gn"] = "goto_node_in_filesystem_tree",
          ["ga"] = "git_stage",
          ["gu"] = "git_unstage",
          ["gr"] = "git_revert",
          ["<C-r>"] = "check_node_for_git",
          ["[c"] = "focus_prev_git_item",
          ["]c"] = "focus_next_git_item",
          ["[e"] = "focus_prev_diagnostic_item",
          ["]e"] = "focus_next_diagnostic_item",
        },
      },
      renderers = {
        directory = {
          { name = "indentation" },
          { name = "icon" },
          { name = "name" },
          { name = "repository", override = { show_status = false } },
          { name = "symlink_target" },
          { name = "git_status" },
          { name = "diagnostics" },
        },
        file = {
          { name = "indentation" },
          { name = "icon" },
          { name = "name", override = { use_git_status_colors = true } },
          { name = "symlink_target" },
          { name = "modified" },
          { name = "git_status" },
          { name = "diagnostics" },
        },
      },
    },
    ---@class Yat.Config.Trees.Git : Yat.Config.Trees.Tree
    ---@field section_icon string The icon for the section in the sidebar, default: `""`.
    ---@field section_name string The name of the section in the sidebar, default: `"Git"`.
    ---@field mappings Yat.Config.Trees.Git.Mappings Tree specific mappings.
    ---@field renderers? Yat.Config.Trees.Renderers Tree specific renderers.
    git = {
      section_name = "Git",
      section_icon = "",
      ---@class Yat.Config.Trees.Git.Mappings : Yat.Config.Trees.Mappings
      ---@field disable_defaults boolean Whether to disable all default mappings, default: `false`.
      ---@field list table<string, Yat.Trees.Git.SupportedActions|string|Yat.Config.Mapping.Custom> Map of key mappings, an empty string, `""`, disables the mapping.
      mappings = {
        disable_defaults = false,
        list = {
          ["<C-]>"] = "cd_to",
          ["."] = "cd_to",
          ["I"] = "toggle_ignored",
          ["H"] = "toggle_filter",
          ["S"] = "search_for_node_in_tree",
          ["gn"] = "goto_node_in_filesystem_tree",
          ["ga"] = "git_stage",
          ["gu"] = "git_unstage",
          ["gr"] = "git_revert",
          ["r"] = "rename",
          ["[c"] = "focus_prev_git_item",
          ["]c"] = "focus_next_git_item",
          ["[e"] = "focus_prev_diagnostic_item",
          ["]e"] = "focus_next_diagnostic_item",
        },
      },
      renderers = {
        directory = {
          { name = "indentation" },
          { name = "icon" },
          { name = "name" },
          { name = "repository" },
          { name = "symlink_target" },
          { name = "git_status" },
          { name = "diagnostics" },
        },
        file = {
          { name = "indentation" },
          { name = "icon" },
          { name = "name", override = { use_git_status_colors = true } },
          { name = "symlink_target" },
          { name = "modified" },
          { name = "git_status" },
          { name = "diagnostics" },
        },
      },
    },
    ---@class Yat.Config.Trees.Buffers : Yat.Config.Trees.Tree
    ---@field section_icon string The icon for the section in the sidebar, default: `""`.
    ---@field section_name string The name of the section in the sidebar, default: `"Buffers"`.
    ---@field mappings Yat.Config.Trees.Buffers.Mappings Tree specific mappings.
    ---@field renderers Yat.Config.Trees.Renderers Tree specific renderers.
    buffers = {
      section_name = "Buffers",
      section_icon = "",
      ---@class Yat.Config.Trees.Buffers.Mappings: Yat.Config.Trees.Mappings
      ---@field disable_defaults boolean Whether to disable all default mappings, default: `false`.
      ---@field list table<string, Yat.Trees.Buffers.SupportedActions|string|Yat.Config.Mapping.Custom> Map of key mappings, an empty string, `""`, disables the mapping.
      mappings = {
        disable_defaults = false,
        list = {
          ["<C-]>"] = "cd_to",
          ["."] = "cd_to",
          ["I"] = "toggle_ignored",
          ["H"] = "toggle_filter",
          ["S"] = "search_for_node_in_tree",
          ["gn"] = "goto_node_in_filesystem_tree",
          ["ga"] = "git_stage",
          ["gu"] = "git_unstage",
          ["gr"] = "git_revert",
          ["<C-r>"] = "check_node_for_git",
          ["[c"] = "focus_prev_git_item",
          ["]c"] = "focus_next_git_item",
          ["[e"] = "focus_prev_diagnostic_item",
          ["]e"] = "focus_next_diagnostic_item",
        },
      },
      renderers = {
        directory = {
          { name = "indentation" },
          { name = "icon" },
          { name = "name" },
          { name = "symlink_target" },
          { name = "git_status" },
          { name = "diagnostics" },
        },
        file = {
          { name = "indentation" },
          { name = "icon" },
          { name = "name", override = { use_git_status_colors = true } },
          { name = "symlink_target" },
          { name = "modified" },
          { name = "git_status" },
          { name = "diagnostics" },
          { name = "buffer_info" },
        },
      },
    },
  },

  ---@class Yat.Config.BaseRendererConfig : { [string]: any }
  ---@field padding string The padding to use to the left of the renderer.

  ---@class Yat.Config.Renderers : { [string] : Yat.Ui.Renderer.Renderer }
  ---@field builtin Yat.Config.Renderers.Builtin Built-in renderers configuration.
  renderers = {
    ---@class Yat.Config.Renderers.Builtin
    ---@field indentation Yat.Config.Renderers.Builtin.Indentation Indentation rendering configuration.
    ---@field icon Yat.Config.Renderers.Builtin.Icon Icon rendering configuration.
    ---@field name Yat.Config.Renderers.Builtin.Name File and directory name rendering configuration.
    ---@field modified Yat.Config.Renderers.Builtin.Modified Modified file rendering configurations.
    ---@field repository Yat.Config.Renderers.Builtin.Repository Repository rendering configuration.
    ---@field symlink_target Yat.Config.Renderers.Builtin.SymlinkTarget Symbolic link rendering configuration.
    ---@field git_status Yat.Config.Renderers.Builtin.GitStatus Git status rendering configuration.
    ---@field diagnostics Yat.Config.Renderers.Builtin.Diagnostics Lsp diagnostics rendering configuration.
    ---@field buffer_info Yat.Config.Renderers.Builtin.BufferInfo Buffer info rendering configuration.
    ---@field clipboard Yat.Config.Renderers.Builtin.Clipboard Clipboard rendering configuration.
    builtin = {
      ---@class Yat.Config.Renderers.Builtin.Indentation : Yat.Config.BaseRendererConfig
      ---@field padding string The padding to use to the left of the renderer, default: `""`.
      ---@field use_indent_marker boolean Whether to show indent markers, default: `false`.
      ---@field indent_marker string The icon for the indentation marker, default: `"│"`.
      ---@field last_indent_marker string The icon for the last indentation marker, default: `"└"`.
      ---@field use_expander_marker boolean Whether to show expanded and collapsed markers, default: `false`.
      ---@field expanded_marker string The icon for expanded directories, default: `""`.
      ---@field collapsed_marker string The icon for collapsed directories, default: `""`.
      indentation = {
        padding = "",
        use_indent_marker = false,
        indent_marker = "│",
        last_indent_marker = "└",
        use_expander_marker = false,
        expanded_marker = "",
        collapsed_marker = "",
      },

      ---@class Yat.Config.Renderers.Builtin.Icon : Yat.Config.BaseRendererConfig
      ---@field padding string The padding to use to the left of the renderer, default: `""`.
      ---@field directory Yat.Config.Renderers.Icon.Directory Directory icon rendering configuration.
      ---@field file Yat.Config.Renderers.Icon.File File icon rendering configuration.
      icon = {
        padding = "",

        ---@class Yat.Config.Renderers.Icon.Directory
        ---@field default string The icon for closed directories, default: `""`.
        ---@field expanded string The icon for opened directories, default: `""`.
        ---@field empty string The icon for closed empty directories, default: `""`.
        ---@field empty_expanded string The icon for opened empty directories, default: `""`.
        ---@field symlink string The icon for closed symbolic link directories, default: `""`.
        ---@field symlink_expanded string The icon for opened symbolic link directories, default: `""`.
        ---@field custom table<string, string> Map of directory names to custom icons, default: `{}`.
        directory = {
          default = "",
          expanded = "",
          empty = "",
          empty_expanded = "",
          symlink = "",
          symlink_expanded = "",
          custom = {},
        },

        ---@class Yat.Config.Renderers.Icon.File
        ---@field default string The default icon for files, default: `""`.
        ---@field symlink string The icon for symbolic link files, default: `""`.
        ---@field fifo string The icon for fifo files, default: `"|"`.
        ---@field socket string The icon for socket files, default: `""`.
        ---@field char string The icon for character device files, default: `""`.
        ---@field block string The icon for block device files, default: `""`.
        file = {
          default = "",
          symlink = "",
          fifo = "|",
          socket = "",
          char = "",
          block = "",
        },
      },

      ---@class Yat.Config.Renderers.Builtin.Name : Yat.Config.BaseRendererConfig
      ---@field padding string The padding to use to the left of the renderer, default: `" "`.
      ---@field root_folder_format string The root folder format as per `fnamemodify`, default: `":~"`.
      ---@field trailing_slash boolean Whether to show a trailing OS directory separator after directory names, default: `false`.
      ---@field use_git_status_colors boolean Whether to color the name with the git status color, default: `false`.
      name = {
        padding = " ",
        root_folder_format = ":~",
        trailing_slash = false,
        use_git_status_colors = false,
      },

      ---@class Yat.Config.Renderers.Builtin.Modified : Yat.Config.BaseRendererConfig
      ---@field padding string The padding to use to the left of the renderer, default: `" "`.
      ---@field icon string The icon for modified files, default: `"[+]"`.
      modified = {
        padding = " ",
        icon = "[+]",
      },

      ---@class Yat.Config.Renderers.Builtin.Repository : Yat.Config.BaseRendererConfig
      ---@field padding string The padding to use to the left of the renderer, default: `" "`.
      ---@field show_status boolean Whether to show repository status on the repository toplevel directory, default: `true`.
      ---@field icons Yat.Config.Renderers.Repository.Icons Repository icons, setting an icon to an empty string will disabled that particular status information.
      repository = {
        padding = " ",
        show_status = true,

        ---@class Yat.Config.Renderers.Repository.Icons
        ---@field behind string The icon for the behind count, default: `"⇣"`.
        ---@field ahead string The icon for the ahead count, default: `"⇡"`.
        ---@field stashed string The icon for the stashed count, default: `"*"`.
        ---@field unmerged string The icon for the unmerged count, default: `"~"`.
        ---@field staged string The icon for the staged count, default: `"+"`.
        ---@field unstaged string The icon for the unstaged count, default: `"!"`.
        ---@field untracked string The icon for the untracked count, default: `"?"`.
        ---@field remote Yat.Config.Renderers.Repository.Icons.Remote Repository remote host icons.
        icons = {
          behind = "⇣",
          ahead = "⇡",
          stashed = "*",
          unmerged = "~",
          staged = "+",
          unstaged = "!",
          untracked = "?",

          ---@class Yat.Config.Renderers.Repository.Icons.Remote : { [string]: string }
          ---@field default string The default icon for marking the git toplevel directory, default: `""`.
          remote = {
            default = "",
            ["://github.com/"] = "",
            ["://gitlab.com/"] = "",
          },
        },
      },

      ---@class Yat.Config.Renderers.Builtin.SymlinkTarget : Yat.Config.BaseRendererConfig
      ---@field padding string The padding to use to the left of the renderer, default: `" "`.
      ---@field arrow_icon string The icon to use before the symbolic link target, default: `"➛"`.
      symlink_target = {
        padding = " ",
        arrow_icon = "➛",
      },

      ---@class Yat.Config.Renderers.Builtin.GitStatus : Yat.Config.BaseRendererConfig
      ---@field padding string The padding to use to the left of the renderer, default: `" "`.
      ---@field icons Yat.Config.Renderers.GitStatus.Icons Git status icon configuration.
      git_status = {
        padding = " ",

        ---@class Yat.Config.Renderers.GitStatus.Icons
        ---@field staged string The icon for staged changes, default: `""`.
        ---@field type_changed string The icon for a type-changed file, default: `""`.
        ---@field added string The icon for an added file, default: `"✚"`.
        ---@field deleted string The icon for a deleted file, default: `"✖"`.
        ---@field renamed string The icon for a renamed file, default: `"➜"`.
        ---@field copied string The icon for a copied file, default: `""`.
        ---@field modified string The icon for modified changes, default: `""`.
        ---@field unmerged string The icon for unmerged changes, default: `""`.
        ---@field ignored string The icon for an ignored file, default: `""`.
        ---@field untracked string The icon for an untracked file, default: `, default: `""`.
        ---@field merge Yat.Config.Renderers.GitStatus.Icons.Merge Git status icons for merge information.
        icons = {
          staged = "",
          type_changed = "",
          added = "✚",
          deleted = "✖",
          renamed = "➜",
          copied = "",
          modified = "",
          unmerged = "",
          ignored = "",
          untracked = "",

          ---@class Yat.Config.Renderers.GitStatus.Icons.Merge
          ---@field us string The icon for added/deleted/modified by `us`, default: `"➜"`.
          ---@field them string The icon for added/deleted/modified by `them`, default: `""`.
          ---@field both string The icon for added/deleted/modified by `both`, default: `""`.
          merge = {
            us = "➜",
            them = "",
            both = "",
          },
        },
      },

      ---@class Yat.Config.Renderers.Builtin.Diagnostics : Yat.Config.BaseRendererConfig
      ---@field padding string The padding to use to the left of the renderer, default: `" "`.
      ---@field directory_min_severity integer The minimum severity necessary to show for directories, see `|vim.diagnostic.severity|`, default: `vim.diagnostic.severity.ERROR`.
      ---@field file_min_severity integer The minimum severity necessary to show for files, see `|vim.diagnostic.severity|`, default: `vim.diagnostic.severity.HINT`.
      diagnostics = {
        padding = " ",
        directory_min_severity = vim.diagnostic.severity.ERROR,
        file_min_severity = vim.diagnostic.severity.HINT,
      },

      ---@class Yat.Config.Renderers.Builtin.BufferInfo : Yat.Config.BaseRendererConfig
      ---@field padding string The padding to use to the left of the renderer, default: `" "`.
      ---@field hidden_icon string The icon for hidden buffers, default: `""`.
      buffer_info = {
        padding = " ",
        hidden_icon = "",
      },

      ---@class Yat.Config.Renderers.Builtin.Clipboard : Yat.Config.BaseRendererConfig
      ---@field padding string The padding to use to the left of the renderer, default: `" "`.
      clipboard = {
        padding = " ",
      },
    },
  },
}
```

</details>

## Trees

ya-tree uses trees to display each section in the sidebar. The builtin trees are:

- `filesystem`
- `git`
- `search`
- `buffers`

## Mappings & Actions

Mappings are constructed by associating the key(s) in question with an `action`.

`?` toggles the help, showing the keymap.

The actions supported by the trees are:

<details>

<summary><b>All builtin actions:</b></summary>

```lua
---@alias Yat.Actions.Name
---| "close_window"
---| "system_open"
---| "open_help"
---| "show_node_info"
---| "close_tree"
---| "delete_tree"
---| "focus_prev_tree"
---| "focus_next_tree"
---| "open_git_tree"
---| "open_buffers_tree"
---| "open"
---| "vsplit"
---| "split"
---| "tabnew"
---| "preview"
---| "preview_and_focus"
---| "copy_name_to_clipboard"
---| "copy_root_relative_path_to_clipboard"
---| "copy_absolute_path_to_clipboard"
---| "close_node"
---| "close_all_nodes"
---| "close_all_child_nodes"
---| "expand_all_nodes"
---| "expand_all_child_nodes"
---| "refresh_tree"
---| "focus_parent"
---| "focus_prev_sibling"
---| "focus_next_sibling"
---| "focus_first_sibling"
---| "focus_last_sibling"
---
---| "add"
---| "rename"
---| "delete"
---| "trash"
---| "copy_node"
---| "cut_node"
---| "paste_nodes"
---| "clear_clipboard"
---| "cd_to"
---| "cd_up"
---| "toggle_ignored"
---| "toggle_filter"
---
---| "search_for_node_in_tree"
---| "search_interactively"
---| "search_once"
---
---| "goto_node_in_filesystem_tree"
---
---| "check_node_for_git"
---| "focus_prev_git_item"
---| "focus_next_git_item"
---| "git_stage"
---| "git_unstage"
---| "git_revert"
---
---| "focus_prev_diagnostic_item"
---| "focus_next_diagnostic_item"
```

</details>

<details>

<summary><b>Actions supported by all builtin trees:</b></summary>

```lua
---@alias Yat.Trees.Tree.SupportedActions
---| "close_window"
---| "system_open"
---| "open_help"
---| "show_node_info"
---| "close_tree"
---| "delete_tree"
---| "focus_prev_tree"
---| "focus_next_tree"
---
---| "open_git_tree"
---| "open_buffers_tree"
---
---| "open"
---| "vsplit"
---| "split"
---| "tabnew"
---| "preview"
---| "preview_and_focus"
---
---| "copy_name_to_clipboard"
---| "copy_root_relative_path_to_clipboard"
---| "copy_absolute_path_to_clipboard"
---
---| "close_node"
---| "close_all_nodes"
---| "close_all_child_nodes"
---| "expand_all_nodes"
---| "expand_all_child_nodes"
---
---| "refresh_tree"
---
---| "focus_parent"
---| "focus_prev_sibling"
---| "focus_next_sibling"
---| "focus_first_sibling"
---| "focus_last_sibling"
```

</details>

<details>

<summary><b>Files tree actions:</b></summary>

```lua
---@alias Yat.Trees.Filesystem.SupportedActions
---| "add"
---| "rename"
---| "delete"
---| "trash"
---
---| "copy_node"
---| "cut_node"
---| "paste_nodes"
---| "clear_clipboard"
---
---| "cd_to"
---| "cd_up"
---
---| "toggle_ignored"
---| "toggle_filter"
---
---| "search_for_node_in_tree"
---| "search_interactively"
---| "search_once"
---
---| "check_node_for_git"
---| "focus_prev_git_item"
---| "focus_next_git_item"
---| "git_stage"
---| "git_unstage"
---| "git_revert"
---
---| "focus_prev_diagnostic_item"
---| "focus_next_diagnostic_item"
---
---| Yat.Trees.Tree.SupportedActions
```

</details>

<details>

<summary><b>Git tree actions:</b></summary>

```lua
---@alias Yat.Trees.Git.SupportedActions
---| "rename"
---
---| "cd_to"
---| "toggle_ignored"
---| "toggle_filter"
---
---| "search_for_node_in_tree"
---
---| "goto_node_in_filesystem_tree"
---
---| "focus_prev_git_item"
---| "focus_next_git_item"
---| "git_stage"
---| "git_unstage"
---| "git_revert"
---
---| "focus_prev_diagnostic_item"
---| "focus_next_diagnostic_item"
---
---| Yat.Trees.Tree.SupportedActions
```

</details>

<details>

<summary><b>Search tree actions:</b></summary>

```lua
---@alias Yat.Trees.Search.SupportedActions
---| "cd_to"
---| "toggle_ignored"
---| "toggle_filter"
---
---| "search_for_node_in_tree"
---| "search_interactively"
---| "search_once"
---
---| "goto_node_in_filesystem_tree"
---
---| "check_node_for_git"
---| "focus_prev_git_item"
---| "focus_next_git_item"
---| "git_stage"
---| "git_unstage"
---| "git_revert"
---
---| "focus_prev_diagnostic_item"
---| "focus_next_diagnostic_item"
---
---| Yat.Trees.Tree.SupportedActions
```

</details>

<details>

<summary><b>Buffers tree actions:</b></summary>

```lua
---@alias Yat.Trees.Buffers.SupportedActions
---| "cd_to"
---| "toggle_ignored"
---| "toggle_filter"
---
---| "search_for_node_in_tree"
---
---| "goto_node_in_filesystem_tree"
---
---| "check_node_for_git"
---| "focus_prev_git_item"
---| "focus_next_git_item"
---| "git_stage"
---| "git_unstage"
---| "git_revert"
---
---| "focus_prev_diagnostic_item"
---| "focus_next_diagnostic_item"
---
---| Yat.Trees.Tree.SupportedActions
```

</details>

### Custom actions

Custom actions can easily be created using the config helper:

```lua

---@async
---@param tree Yat.Tree
---@param node Yat.Node
---@param sidebar Yat.Sidebar
local function special_action(tree, node, sidebar)
  -- this is what the "git_stage" action does
  if node.repo then
    local err = node.repo:index():add(node.path)
    if not err then
      sidebar:update()
    end
  end
end

---@async
---@param tree Yat.Tree
---@param node Yat.Node
---@param sidebar Yat.Sidebar
local function print_tree_and_node(tree, node, sidebar)
  print(tree.TYPE)
  vim.pretty_print(node:get_debug_info())
end

local utils = require("ya-tree.config.utils")
require("ya-tree").setup({
  actions = {
    special_action = utils.create_action(special_action, "Add node to git", true, { "n" }, { "filesystem", "search", "buffers", "git" }),
    print_tree = utils.create_action(print_tree_and_node, "Print tree and node", true, { "n" }, { "filesystem", "search", "buffers", "git" }),
  },
  trees = {
    global_mappings = {
      ["A"] = "special_action",
    },
    filesystem = {
      mappings = {
        ["T"] = "print_tree_and_node",
      },
    },
    git = {
      mappings = {
        ["t"] = "print_tree_and_node",
      },
    },
  },
})
```

## Async

Git and file system operations are wrapped with the `plenary.nvim` `plenary.async.wrap` function,
turning callbacks into regular return values. The consequence of this is that calling those functions
must be done in a coroutine. This bubbles up all the way, so all entry points to the plugin are done
using the `plenary.async.void` function.

For actions, this conceptually translates to:

```lua
local function rhs(key)
  local sidebar = ...
  local tree, node = ...
  local action = ...
  require("plenary.async").void(action)(tree, node, sidebar)
end
```

This means that all actions are running inside a coroutine and special care has to be taken to handle
`vim.api` functions calls, since they cannot be called from a `vim.loop` callback. The is remedied by
by using `vim.schedule(...)`, `plenary` variant:
```lua
  tree.root:refresh()
  require("plenary.async.util").scheduler()
   -- this can cause E5560 without the call to scheduler above
  local height, width = sidebar:size()
```

The `vim.ui.input` and `vim.ui.select` functions are also `wrap`ped to make them easier to use:
```lua
  local ui = require("ya-tree.ui")
  local response = ui.input({ promt = "My prompt", deault = "My value" })
  local choice = ui.select({ "Yes", "No" }, { kind = "confirmation", prompt = "Choose" })
```

The `nui.nvim` `Input` class is extended with completion using
[`completefunc`](https://neovim.io/doc/user/options.html#'completefunc') and initialization parameters
specific to `ya-tree`, in the `ya-tree.ui.nui` package. It is also `wrap`ped for when only a simple 
result is needed:
```lua
  local ui = require("ya-tree.ui")
  local reponse = ui.nui_input({ title = "My Title", default = "some default", completion = "file" })
```

## Renderers

A custom renderer component can be created using the config helper:

```lua
---@class Yat.Ui.RenderContext
---@field tree_type Yat.Trees.Type
---@field config Yat.Config
---@field depth integer
---@field last_child boolean
---@field indent_markers table<integer, boolean>

---@class Yat.Ui.RenderResult
---@field padding string
---@field text string
---@field highlight string

---@param node Yat.Node
---@param context Yat.Ui.RenderContext
---@param renderer Yat.Config.BaseRendererConfig
---@return Yat.Ui.RenderResult[]|nil result
local function renderer(node, context, renderer)
  -- the renderer parameter is the merged table of the second argument to utils.create_renderer
  -- and the `override` table in the tree's renderers table
  if renderer.prop and vim.startswith(node.name, "A") then
    return {
      {
        padding = renderer.padding,
        text = "WOO",
        highlight = hl.ERROR_FILE_NAME,
      },
    }
  end
end

local utils = require("ya-tree.config.utils")
local hl = require("ya-tree.ui.highlights")
require("ya-tree").setup({
  renderers = {
    example_renderer = utils.create_renderer(renderer, { padding = " ", prop = false }),
  },
  trees = {
    filesystem = {
      renderers = {
        file = {
          { name = "indentation" },
          { name = "icon" },
          { name = "name", override = { use_git_status_colors = true } },
          { name = "example_renderer", override = { prop = true } },
          { name = "symlink_target" },
          { name = "modified" },
          { name = "git_status" },
          { name = "diagnostics" },
        },
      },
    },
  },
})
```

Renderers should only access already availble data on the `node` in question,
or special helper functions in the `ya-tree.ui.renderers` module, and **not**
initiate any further calls, if possible.

## Highlight Groups

<details>

<summary><b>Ya-Tree defines the following highligh groups:</b></summary>

| Highlight Group                   | Default Group                     | Values                                |
| --------------------------------- | --------------------------------- | ------------------------------------- |
|YaTreeRootName                     |                                   | `{ fg = "#ddc7a1", bold = true }`     |
|YaTreeIndentMarker                 |                                   | `{ fg = "#5a524c" }`                  |
|YaTreeIndentExpander               | YaTreeDirectoryIcon               |                                       |
|YaTreeDirectoryIcon                | Directory                         |                                       |
|YaTreeSymbolicDirectoryIcon        | YaTreeDirectoryIcon               |                                       |
|YaTreeDirectoryName                | Directory                         |                                       |
|YaTreeEmptyDirectoryName           | YaTreeDirectoryName               |                                       |
|YaTreeSymbolicDirectoryName        | YaTreeDirectoryName               |                                       |
|YaTreeEmptySymbolicDirectoryName   | YaTreeDirectoryName               |                                       |
|YaTreeDefaultFileIcon              | Normal                            |                                       |
|YaTreeSymbolicFileIcon             | YaTreeDefaultFileIcon             |                                       |
|YaTreeFifoFileIcon                 |                                   | `{ fg = "#af0087" }`                  |
|YaTreeSocketFileIcon               |                                   | `{ fg = "#ff005f" }`                  |
|YaTreeCharDeviceFileIcon           |                                   | `{ fg = "#87d75f" }`                  |
|YaTreeBlockDeviceFileIcon          |                                   | `{ fg = "#5f87d7" }`                  |
|YaTreeFileName                     | Normal                            |                                       |
|YaTreeSymbolicFileName             | YaTreeFileName                    |                                       |
|YaTreeFifoFileName                 | YaTreeFifoFileIcon                |                                       |
|YaTreeSocketFileName               | YaTreeSocketFileIcon              |                                       |
|YaTreeCharDeviceFileName           | YaTreeCharDeviceFileIcon          |                                       |
|YaTreeBlockDeviceFileName          | YaTreeBlockDeviceFileIcon         |                                       |
|YaTreeExecutableFileName           | YaTreeFileName                    |                                       |
|YaTreeErrorFileName                |                                   | `{ fg = "#080808", bg = "#ff0000" }`  |
|YaTreeFileModified                 |                                   | `{ fg = normal_fg, bold = true }`     |
|YaTreeSymbolicLinkTarget           |                                   | `{ fg = "#7daea3", italic = true }`   |
|YaTreeBufferNumber                 | SpecialChar                       |                                       |
|YaTreeBufferHidden                 | WarningMsg                        |                                       |
|YaTreeClipboardStatus              | Comment                           |                                       |
|YaTreeText                         | Normal                            |                                       |
|YaTreeDimText                      | Comment                           |                                       |
|YaTreeSearchTerm                   | SpecialChar                       |                                       |
|YaTreeNormal                       | Normal                            |                                       |
|YaTreeNormalNC                     | NormalNC                          |                                       |
|YaTreeCursorLine                   | CursorLine                        |                                       |
|YaTreeVertSplit                    | VertSplit                         |                                       |
|YaTreeWinSeparator                 | WinSeparator                      |                                       |
|YaTreeStatusLine                   | StatusLine                        |                                       |
|YaTreeStatusLineNC                 | StatusLineNC                      |                                       |
|YaTreeFloatNormal                  | NormalFloat                       |                                       |
|YaTreeGitRepoToplevel              | Character                         | fallack: `"#a9b665"`                  |
|YaTreeGitUnmergedCount             | GitSignsDelete, GitGutterDelete   | fallack: `"#ea6962"`                  |
|YaTreeGitStashCount                | Character                         | fallack: `"#a9b665"`                  |
|YaTreeGitAheadCount                | Character                         | fallack: `"#a9b665"`                  |
|YaTreeGitBehindCount               | Character                         | fallack: `"#a9b665"`                  |
|YaTreeGitStagedCount               | Type                              | fallack: `"#d8a657"`                  |
|YaTreeGitUnstagedCount             | Type                              | fallack: `"#d8a657"`                  |
|YaTreeGitUntrackedCount            | Title                             | fallack: `"#7daea3"`                  |
|YaTreeGitStaged                    | Character                         | fallack: `"#a9b665"`                  |
|YaTreeGitDirty                     | GitSignsChange, GitGutterChange   | fallack: `"#cb8327"`                  |
|YaTreeGitNew                       | GitSignsAdd, GitGutterAdd         | fallack: `"#6f8352"`                  |
|YaTreeGitMerge                     | Statement                         | fallack: `"#d3869b"`                  |
|YaTreeGitRenamed                   | Title                             | fallack: `"#7daea3"`                  |
|YaTreeGitDeleted                   | GitSignsDelete, GitGutterDelete   | fallack: `"#ea6962"`                  |
|YaTreeGitIgnored                   | Comment                           |                                       |
|YaTreeGitUntracked                 | Type                              | fallack: `"#d8a657"`                  |
|YaTreeInfoSize                     | TelescopePreviewSize              |                                       |
|YaTreeInfoUser                     | TelescopePreviewUser              |                                       |
|YaTreeInfoGroup                    | TelescopePreviewGroup             |                                       |
|YaTreeInfoPermissionNone           | TelescopePreviewHyphen            |                                       |
|YaTreeInfoPermissionRead           | TelescopePreviewRead              |                                       |
|YaTreeInfoPermissionWrite          | TelescopePreviewWrite             |                                       |
|YaTreeInfoPermissionExecute        | TelescopePreviewExecute           |                                       |
|YaTreeInfoDate                     | TelescopePreviewDate              |                                       |
|YaTreeUiCurrentTab                 |                                   | `{ fg = "#080808", bg = "#5f87d7" }`  |
|YaTreeUiOhterTab                   |                                   | `{ fg = "#080808", bg = "#5a524c" }`  |
|YaTreeSectionIcon                  | YaTreeSectionName                 |                                       |
|YaTreeSectionName                  |                                   | `{ fg = "#5f87d7" }`                  |
|YaTreeSecionSeparator              | YaTreeDimText                     |                                       |

</details>

## Acknowlegdements

 - [gitsigns.nvim](https://github.com/lewis6991/gitsigns.nvim) for Git integration in Lua.
 - [plenary.nvim](https://github.com/nvim-lua/plenary.nvim) for async.
 - [nvim-tree.lua](https://github.com/nvim-tree/nvim-tree.lua) for tree plugin ideas.
 - [neo-tree.nvim](https://github.com/nvim-neo-tree/neo-tree.nvim) for tree plugin ideas, and renderers.
 - [yanil](https://github.com/Xuyuanp/yanil) for tree plugin ideas.
 - [sidebar.nvim](https://github.com/sidebar-nvim/sidebar.nvim/) for the sidebar idea.
 - [nui.nvim](https://github.com/MunifTanjim/nui.nvim)
