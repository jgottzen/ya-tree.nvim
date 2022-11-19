local fn = vim.fn

local M = {
  ---@class Yat.Config
  ---@field close_if_last_window boolean Force closing Neovim when YaTree is the last window, default: `false`.
  ---@field update_on_buffer_saved boolean Update the tree and the directory of the file changed, default: `true`.
  ---@field follow_focused_file boolean Update the focused file in the tree on `BufEnter`, default: `false`.
  ---@field move_cursor_to_name boolean Keep the cursor on the name in tree, default: `false`.
  ---@field move_buffers_from_tree_window boolean Move buffers from the tree window to the last used window, default: `true`.
  ---@field hijack_netrw boolean Replace the `netrw` file explorer, default: `true`.
  ---@field expand_all_nodes_max_depth integer The maximum depth to expand when expanding nodes, default: 5.
  ---@field load_sidebar_on_setup boolean Whether to load the sidebar and it's trees on setup, which can make the subsequent open faster, default: `false`.
  ---@field log Yat.Config.Log Logging configuration.
  ---@field auto_open Yat.Config.AutoOpen Auto-open configuration.
  ---@field cwd Yat.Config.Cwd Current working directory configuration.
  ---@field dir_watcher Yat.Config.DirWatcher Directory watching configuration.
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
  default = {
    close_if_last_window = false,
    update_on_buffer_saved = true,

    follow_focused_file = false,
    move_cursor_to_name = false,
    move_buffers_from_tree_window = true,

    hijack_netrw = true,

    expand_all_nodes_max_depth = 5,

    load_sidebar_on_setup = false,

    ---@class Yat.Config.Log
    ---@field level Yat.Logger.Level The logging level used, default: `"warn"`.
    ---@field to_console boolean Whether to log to the console, default: `false`.
    ---@field to_file boolean Whether to log the the log file, default: `false`.
    ---@field namespaces string[] For which namespaces logging is enabled, default: `{ "ya-tree", "actions", "events", "fs", "nodes", "trees", "ui", "git", "job", "sidebar", "lib" }`.
    log = {
      level = "warn",
      to_console = false,
      to_file = false,
      namespaces = { "ya-tree", "actions", "events", "fs", "nodes", "trees", "ui", "git", "job", "sidebar", "lib" },
    },

    ---@class Yat.Config.AutoOpen
    ---@field on_setup boolean Automatically open the tree when running setup, default: `false`.
    ---@field on_new_tab boolean Automatically open the tree when opening a new tabpage, default: `false`.
    ---@field focus_tree boolean Wether to focus the tree when automatically opened, default: `false`.
    auto_open = {
      on_setup = false,
      on_new_tab = false,
      focus_tree = false,
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
    ---@field exclude string[] The directory names to exclude from watching, ".git" directories are always excluded.
    dir_watcher = {
      enable = true,
      exclude = {},
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
      ---@field enable boolean Wether yadm is enabled, requires git to be enabled, default: `false`.
      yadm = {
        enable = false,
      },
    },

    ---@class Yat.Config.Diagnostics
    ---@field enable boolean Show lsp diagnostics in the tree, default: `true`.
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
    ---@field enable boolean Wether to enable trashing in the tree (`trash-cli must be installed`), default: `true`.
    ---@field require_confirm boolean Confirm before trashing file(s), default: `false`.
    trash = {
      enable = true,
      require_confirm = false,
    },

    ---@class Yat.Config.View
    ---@field size integer Size of the tree panel, default: `40`.
    ---@field position Yat.Ui.Position Where the tree panel is placed, default: `"left"`.
    ---@field number boolean Wether to show the number column, default: `false`.
    ---@field relativenumber boolean Wether to show relative numbers, default: `false`.
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
          empty_line_before_tree = true
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

    ---@class Yat.Config.Actions : { [Yat.Actions.Name]: Yat.Action }
    actions = {},

    ---@class Yat.Config.Mapping.Custom Key mapping for user functions configuration.
    ---@field modes Yat.Actions.Mode[] The mode(s) for the keybinding.
    ---@field fn Yat.Action.Fn User function.
    ---@field desc? string Description of what the mapping does.
    ---@field node_independent? boolean If the action can be invoked without a `node`.

    ---@class Yat.Config.Trees.GlobalMappings
    ---@field disable_defaults boolean Whether to diasble all default mappings, default: `false`.
    ---@field list table<string, Yat.Trees.Tree.SupportedActions|Yat.Actions.Name|""|Yat.Config.Mapping.Custom> Map of key mappings, an empty string, `""`, disables the mapping.

    ---@class Yat.Config.Trees.Mappings
    ---@field disable_defaults boolean Whether to diasble all default mappings, default: `false`.
    ---@field list table<string, Yat.Actions.Name|""|Yat.Config.Mapping.Custom> Map of key mappings, an empty string, `""`, disables the mapping.

    ---@class Yat.Config.Trees.Renderer
    ---@field name Yat.Ui.Renderer.Name The name of the renderer.
    ---@field override Yat.Config.BaseRendererConfig The renderer specific configuration.

    ---@class Yat.Config.Trees.Renderers
    ---@field directory Yat.Config.Trees.Renderer[] Which renderers to use for directories, in order.
    ---@field file Yat.Config.Trees.Renderer[] Which renderers to use for files, in order

    ---@class Yat.Config.Trees.Tree
    ---@field section_icon string The icon for the tree in the sidebar.
    ---@field section_name string The name of the the in the sidebar.
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
      ---@field section_icon string The icon for the tree in the sidebar, default: `""`.
      ---@field section_name string The name of the the in the sidebar, default: `"Files"`.
      ---@field completion Yat.Config.Trees.Filesystem.Completion Path completion for tree search.
      ---@field mappings Yat.Config.Trees.Filesystem.Mappings Tree specific mappings.
      ---@field renderers Yat.Config.Trees.Renderers Tree specific renderers.
      filesystem = {
        section_name = "Files",
        section_icon = "",
        ---@class Yat.Config.Trees.Filesystem.Completion
        ---@field on "root" | "node" Wether to complete on the tree root directory or the current node, ignored if `setup` is set, default: `"root"`.
        ---@field setup? fun(self: Yat.Trees.Filesystem, node: Yat.Node): string function for setting up completion, the returned string will be set as `completefunc`, default: `nil`.
        completion = {
          on = "root",
          setup = nil,
        },
        ---@class Yat.Config.Trees.Filesystem.Mappings : Yat.Config.Trees.Mappings
        ---@field disable_defaults boolean Whether to diasble all default mappings, default: `false`.
        ---@field list table<string, Yat.Trees.Filesystem.SupportedActions|""|Yat.Config.Mapping.Custom> Map of key mappings, an empty string, `""`, disables the mapping.
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
      ---@field section_icon string The icon for the tree in the sidebar, default" `""`.
      ---@field section_name string The name of the the in the sidebar, default: `"Search"`.
      ---@field mappings Yat.Config.Trees.Search.Mappings Tree specific mappings.
      ---@field renderers Yat.Config.Trees.Renderers Tree specific renderers.
      search = {
        section_name = "Search",
        section_icon = "",
        ---@class Yat.Config.Trees.Search.Mappings : Yat.Config.Trees.Mappings
        ---@field disable_defaults boolean Whether to diasble all default mappings, default: `false`.
        ---@field list table<string, Yat.Trees.Search.SupportedActions|""|Yat.Config.Mapping.Custom> Map of key mappings, an empty string, `""`, disables the mapping.
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
      ---@field section_icon string The icon for the tree in the sidebar, default: `""`.
      ---@field section_name string The name of the the in the sidebar, default: `"Git"`.
      ---@field mappings Yat.Config.Trees.Git.Mappings Tree specific mappings.
      ---@field renderers? Yat.Config.Trees.Renderers Tree specific renderers.
      git = {
        section_name = "Git",
        section_icon = "",
        ---@class Yat.Config.Trees.Git.Mappings : Yat.Config.Trees.Mappings
        ---@field disable_defaults boolean Whether to diasble all default mappings, default: `false`.
        ---@field list table<string, Yat.Trees.Git.SupportedActions|""|Yat.Config.Mapping.Custom> Map of key mappings, an empty string, `""`, disables the mapping.
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
      ---@field section_icon string The icon for the tree in the sidebar, default: `""`.
      ---@field section_name string The name of the the in the sidebar, default: `"Buffers"`.
      ---@field mappings Yat.Config.Trees.Buffers.Mappings Tree specific mappings.
      ---@field renderers Yat.Config.Trees.Renderers Tree specific renderers.
      buffers = {
        section_name = "Buffers",
        section_icon = "",
        ---@class Yat.Config.Trees.Buffers.Mappings: Yat.Config.Trees.Mappings
        ---@field disable_defaults boolean Whether to diasble all default mappings, default: `false`.
        ---@field list table<string, Yat.Trees.Buffers.SupportedActions|""|Yat.Config.Mapping.Custom> Map of key mappings, an empty string, `""`, disables the mapping.
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
        ---@field use_indent_marker boolean Wether to show indent markers, default: `false`.
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
        ---@field trailing_slash boolean Wether to show a trailing OS directory separator after directory names, default: `false`.
        ---@field use_git_status_colors boolean Wether to color the name with the git status color, default: `false`.
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
          ---@field untracked string The icon for the untracked cound, default: `"?"`.
          ---@field remote Yat.Config.Renderers.Repository.Icons.Remote Repository remote host icons.
          icons = {
            behind = "⇣",
            ahead = "⇡",
            stashed = "*",
            unmerged = "~",
            staged = "+",
            unstaged = "!",
            untracked = "?",

            ---@class Yat.Config.Renderers.Repository.Icons.Remote
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
        ---@field arrow_icon string The icon to use before the sybolic link target, default: `"➛"`.
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
  },
}

M.config = vim.deepcopy(M.default) --[[@as Yat.Config]]

---@param opts? Yat.Config
---@return Yat.Config config
function M.setup(opts)
  opts = opts or {}
  M.config = vim.tbl_deep_extend("force", M.default, opts) --[[@as Yat.Config]]

  local utils = require("ya-tree.utils")

  -- make sure any custom tree configs have the required shape
  for name, tree in pairs(M.config.trees) do
    if name ~= "global_mappings" then
      if not tree.mappings then
        tree.mappings = {}
      end
      if not tree.mappings.list then
        tree.mappings.list = {}
      end
    end
  end
  if opts.trees then
    if opts.trees.global_mappings and opts.trees.global_mappings.disable_defaults then
      M.config.trees.global_mappings.list = opts.trees.global_mappings.list or {}
    end
    for name, tree in pairs(opts.trees) do
      if name ~= "global_mappings" then
        if tree.mappings and tree.mappings.disable_defaults then
          M.config.trees[name].mappings.list = opts.trees[name].mappings.list or {}
        end
      end
    end
  end

  if not M.config.system_open.cmd then
    if utils.is_linux then
      M.config.system_open.cmd = "xdg-open"
    elseif utils.is_macos then
      M.config.system_open.cmd = "open"
    elseif utils.is_windows then
      M.config.system_open = {
        cmd = "cmd",
        args = { "/c", "start" },
      }
    end
  end

  if M.config.git.enable and fn.executable("git") == 0 then
    utils.notify("git is not detected in the PATH. Disabling 'git.enable' in the configuration.")
    M.config.git.enable = false
  end
  if M.config.git.yadm.enable then
    if not M.config.git.enable then
      utils.notify("git is not enabled. Disabling 'git.yadm.enable' in the configuration.")
      M.config.git.yadm.enable = false
    elseif fn.executable("yadm") == 0 then
      utils.notify("yadm not in the PATH. Disabling 'git.yadm.enable' in the configuration.")
      M.config.git.yadm.enable = false
    end
  end

  if M.config.trash.enable and fn.executable("trash") == 0 then
    utils.notify("trash is not in the PATH. Disabling 'trash.enable' in the configuration.")
    M.config.trash.enable = false
  end

  if not M.config.search.cmd then
    if fn.executable("fd") == 1 then
      M.config.search.cmd = "fd"
    elseif fn.executable("fdfind") == 1 then
      M.config.search.cmd = "fdfind"
    elseif fn.executable("find") == 1 and not fn.has("win32") == 1 then
      M.config.search.cmd = "find"
    elseif fn.executable("where") == 1 then
      M.config.search.cmd = "where"
    else
      utils.warn("None of the default search programs was found in the PATH!\nSearching will not be possible.")
    end
  end
  if M.config.search.max_results == 0 then
    utils.warn("'search.max_results' is set to 0, disabling it, this can cause performance issues!")
  end

  return M.config
end

return M
