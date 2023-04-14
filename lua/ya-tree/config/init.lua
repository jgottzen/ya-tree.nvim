local fn = vim.fn

local M = {
  ---@class Yat.Config
  ---@field close_if_last_window boolean Close the sidebar when it is the last window in the tabpage, default: `false`.
  ---@field follow_focused_file boolean Update the focused file in the panel on `BufEnter`, default: `false`.
  ---@field move_cursor_to_name boolean Keep the cursor on the name in panel, default: `false`.
  ---@field move_buffers_from_sidebar_window boolean Move buffers from the sidebar window to the last used window, default: `true`.
  ---@field hijack_netrw boolean Replace the `netrw` file explorer, default: `true`.
  ---@field expand_all_nodes_max_depth integer The maximum depth to expand when expanding nodes, default: 5.
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
  ---@field popups Yat.Config.Popups Popup window configuration.
  ---@field sidebar Yat.Config.Sidebar Sidebar configuration.
  ---@field actions Yat.Config.Actions User actions.
  ---@field panels Yat.Config.Panels Panel configurations.
  ---@field renderers Yat.Config.Renderers Renderer configurations.
  default = {
    close_if_last_window = false,

    follow_focused_file = false,
    move_cursor_to_name = false,
    move_buffers_from_sidebar_window = true,

    hijack_netrw = true,

    expand_all_nodes_max_depth = 5,

    ---@alias Yat.Logger.Level "trace"|"debug"|"info"|"warn"|"error"
    ---@alias Yat.Logger.Namespace "all"|"ya-tree"|"actions"|"events"|"fs"|"lsp"|"nodes"|"panels"|"sidebar"|"ui"|"git"|"job"|string

    ---@class Yat.Config.Log
    ---@field level Yat.Logger.Level The logging level used, default: `"warn"`.
    ---@field to_console boolean Whether to log to the console, default: `false`.
    ---@field to_file boolean Whether to log to the log file, default: `false`.
    ---@field namespaces Yat.Logger.Namespace[] For which namespaces logging is enabled, default: `{ "all" }`.
    log = {
      level = "warn",
      to_console = false,
      to_file = false,
      namespaces = { "all" },
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
    ---@field follow boolean Update the Files panel root directory on `DirChanged`, default: `false`.
    ---@field update_from_panel boolean Update the *tabpage* cwd when changing root directory in a panel, default: `false`.
    cwd = {
      follow = false,
      update_from_panel = false,
    },

    ---@class Yat.Config.DirWatcher
    ---@field enable boolean Whether directory watching is enabled, default: `true`.
    ---@field exclude string[] The directory names to exclude from watching, `".git"` directories are always excluded.
    dir_watcher = {
      enable = true,
      exclude = {},
    },

    ---@alias Yat.Node.SortBy "name"|"type"|"extension"

    ---@class Yat.Config.Sorting
    ---@field directories_first boolean Whether to sort directories first, default: `true`.
    ---@field case_sensitive boolean Whether to use case sensitive sort, default: `false`.
    ---@field sort_by Yat.Node.SortBy|fun(a: Yat.Node, b: Yat.Node):boolean What to sort by, or a user specified function, default: `"name"`.
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
    ---@field show_ignored boolean Whether to show git ignored files in panels, toggleable, default: `true`.
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
    ---@field enable boolean Show lsp diagnostics in panels, default: `true`.
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

    ---@class Yat.Config.Popups
    ---@field border string|string[] The border type for floating windows, default: `"rounded"`.
    popups = {
      border = "rounded",
    },

    ---@alias Yat.Panel.Type "files"|"git_status"|"symbols"|"call_hierarchy"|"buffers"|string

    ---@class Yat.Config.Sidebar
    ---@field layout Yat.Config.Sidebar.Layout The layout configuration for the sidebar.
    sidebar = {
      ---@class Yat.Config.Sidebar.PanelLayout.Panel
      ---@field panel Yat.Panel.Type The panel type.
      ---@field show? boolean Whether the panel is shown, a `nil` value is treated as `true`, default: `true`.
      ---@field height? integer|string The height of the panel, in rows or percent.

      ---@class Yat.Config.Sidebar.PanelLayout
      ---@field panels Yat.Config.Sidebar.PanelLayout.Panel[] Which panels to show on this side.
      ---@field width integer The width of the panels.

      ---@class Yat.Config.Sidebar.Layout
      ---@field left Yat.Config.Sidebar.PanelLayout The panels on the left side.
      ---@field right Yat.Config.Sidebar.PanelLayout The panels on the right side.
      layout = {
        left = {
          panels = { { panel = "files", height = 30 } },
          width = 40,
        },
        right = {
          panels = {},
          width = 40,
        },
      },
    },

    ---@alias Yat.Action.TreePanelFn async fun(panel: Yat.Panel.Tree, node: Yat.Node)

    ---@alias Yat.Actions.Mode "n"|"v"

    ---@class Yat.Config.Action
    ---@field fn Yat.Action.TreePanelFn The function implementing the action.
    ---@field desc string The description of the action.
    ---@field modes Yat.Actions.Mode[] Which modes the action is available in.
    ---@field node_independent boolean Whether the action can be called without a `Yat.Node`, e.g. the `"open_help"` action.

    ---@class Yat.Config.Actions : { [string]: Yat.Config.Action }
    actions = {},

    ---@class Yat.Config.Panels.Mappings
    ---@field disable_defaults boolean Whether to disable all default mappings, default: `false`.
    ---@field list table<string, Yat.Actions.Name|string> Map of key mappings, an empty string, `""`, disables the mapping.

    ---@class Yat.Config.Panels.TreeRenderer
    ---@field name Yat.Ui.Renderer.Name The name of the renderer.
    ---@field override Yat.Config.BaseRendererConfig The renderer specific configuration.

    ---@class Yat.Config.Panels.TreeRenderers
    ---@field directory Yat.Config.Panels.TreeRenderer[] Which renderers to use for directories, in order.
    ---@field file Yat.Config.Panels.TreeRenderer[] Which renderers to use for files, in order

    ---@class Yat.Config.Panels.Panel
    ---@field title string The name of panel.
    ---@field icon string The icon for the panel.
    ---@field mappings Yat.Config.Panels.Mappings The panel specific mappings.
    ---@field renderers Yat.Config.Panels.TreeRenderers The panel specific renderers.

    ---@class Yat.Config.Panels
    ---@field files Yat.Config.Panels.Files Files panel configuration.
    ---@field symbols Yat.Config.Panels.Symbols Lsp Symbols panel configuration.
    ---@field call_hierarchy Yat.Config.Panels.CallHierarchy Call hierarchy panel configuration.
    ---@field git_status Yat.Config.Panels.GitStatus Git Status panel configuration.
    ---@field buffers Yat.Config.Panels.Buffers Buffers panel configuration.
    ---@field [Yat.Panel.Type] Yat.Config.Panels.Panel
    panels = {
      ---@class Yat.Config.Panels.Files : Yat.Config.Panels.Panel
      ---@field title string The name of the panel, default: `"Files"`.
      ---@field icon string The icon for the panel, default: `""`.
      ---@field mappings Yat.Config.Panels.Files.Mappings Panel specific mappings.
      ---@field renderers Yat.Config.Panels.Files.Renderers Panel specific renderers.
      files = {
        title = "Files",
        icon = "",
        ---@class Yat.Config.Panels.Files.Completion
        ---@field on "root"|"node" Whether to complete on the panel root directory or the current node, ignored if `setup` is set, default: `"root"`.
        ---@field setup? fun(panel: Yat.Panel.Files, node: Yat.Node): string function for setting up completion, the returned string will be set as `completefunc`, default: `nil`.
        completion = {
          on = "root",
          setup = nil,
        },
        ---@class Yat.Config.Panels.Files.Mappings : Yat.Config.Panels.Mappings
        ---@field disable_defaults boolean Whether to disable all default mappings, default: `false`.
        ---@field list table<string, Yat.Panel.Files.SupportedActions|string> Map of key mappings, an empty string, `""`, disables the mapping.
        mappings = {
          disable_defaults = false,
          list = {
            ["q"] = "close_sidebar",
            ["?"] = "open_help",
            ["gs"] = "open_symbols_panel",
            ["<C-g>"] = "open_git_status_panel",
            ["b"] = "open_buffers_panel",
            ["gc"] = "open_call_hierarchy_panel",
            ["gx"] = "system_open",
            ["<C-i>"] = "show_node_info",
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
            ["R"] = "refresh_panel",
            ["P"] = "focus_parent",
            ["<"] = "focus_prev_sibling",
            [">"] = "focus_next_sibling",
            ["K"] = "focus_first_sibling",
            ["J"] = "focus_last_sibling",
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
            ["S"] = "search_for_node_in_panel",
            ["/"] = "search_interactively",
            ["f"] = "search_once",
            ["<C-x>"] = "close_search",
            ["gn"] = "goto_node_in_files_panel",
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
        ---@alias Yat.Config.Panels.Files.DirectoryRendererName "indentation"|"icon"|"name"|"repository"|"symlink_target"|"git_status"|"diagnostics"|"clipboard"|string
        ---@alias Yat.Config.Panels.Files.FileRendererName "indentation"|"icon"|"name"|"symlink_target"|"modified"|"git_status"|"diagnostics"|"clipboard"|string

        ---@class Yat.Config.Panels.Files.Renderers : Yat.Config.Panels.TreeRenderers
        ---@field directory { name : Yat.Config.Panels.Files.DirectoryRendererName, override : Yat.Config.BaseRendererConfig }[]
        ---@field file { name : Yat.Config.Panels.Files.FileRendererName, override : Yat.Config.BaseRendererConfig }[]
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

      ---@class Yat.Config.Panels.GitStatus : Yat.Config.Panels.Panel
      ---@field title string The name of the panel, default: `"Git"`.
      ---@field icon string The icon for the panel, default: `""`.
      ---@field mappings Yat.Config.Panels.GitStatus.Mappings Panel specific mappings.
      ---@field renderers Yat.Config.Panels.GitStatus.Renderers Panel specific renderers.
      git_status = {
        title = "Git Status",
        icon = "",
        ---@class Yat.Config.Panels.GitStatus.Mappings : Yat.Config.Panels.Mappings
        ---@field disable_defaults boolean Whether to disable all default mappings, default: `false`.
        ---@field list table<string, Yat.Panel.GitStatus.SupportedActions|string> Map of key mappings, an empty string, `""`, disables the mapping.
        mappings = {
          disable_defaults = false,
          list = {
            ["q"] = "close_sidebar",
            ["<C-x>"] = "close_panel",
            ["?"] = "open_help",
            ["gs"] = "open_symbols_panel",
            ["b"] = "open_buffers_panel",
            ["gc"] = "open_call_hierarchy_panel",
            ["gx"] = "system_open",
            ["<C-i>"] = "show_node_info",
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
            ["R"] = "refresh_panel",
            ["P"] = "focus_parent",
            ["<"] = "focus_prev_sibling",
            [">"] = "focus_next_sibling",
            ["K"] = "focus_first_sibling",
            ["J"] = "focus_last_sibling",
            ["<C-]>"] = "cd_to",
            ["."] = "cd_to",
            ["I"] = "toggle_ignored",
            ["H"] = "toggle_filter",
            ["S"] = "search_for_node_in_panel",
            ["gn"] = "goto_node_in_files_panel",
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
        ---@alias Yat.Config.Panels.GitStatus.DirectoryRendererName "indentation"|"icon"|"name"|"repository"|"symlink_target"|"git_status"|"diagnostics"|string
        ---@alias Yat.Config.Panels.GitStatus.FileRendererName "indentation"|"icon"|"name"|"symlink_target"|"modified"|"git_status"|"diagnostics"|string

        ---@class Yat.Config.Panels.GitStatus.Renderers : Yat.Config.Panels.TreeRenderers
        ---@field directory { name : Yat.Config.Panels.GitStatus.DirectoryRendererName, override : Yat.Config.BaseRendererConfig }[]
        ---@field file { name : Yat.Config.Panels.GitStatus.FileRendererName, override : Yat.Config.BaseRendererConfig }[]
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

      ---@class Yat.Config.Panels.Symbols : Yat.Config.Panels.Panel
      ---@field title string The name of the panel, default: `"Lsp Symbols"`.
      ---@field icon string The icon for the panel, default" `""`.
      ---@field scroll_buffer_to_symbol boolean Whether to scroll the file to the current symbol, default: `true`.
      ---@field mappings Yat.Config.Panels.Symbols.Mappings Panel specific mappings.
      ---@field renderers Yat.Config.Panels.Symbols.Renderers Panel specific renderers.
      symbols = {
        title = "Lsp Symbols",
        icon = "",
        scroll_buffer_to_symbol = true,
        ---@class Yat.Config.Panels.Symbols.Mappings : Yat.Config.Panels.Mappings
        ---@field disable_defaults boolean Whether to disable all default mappings, default: `false`.
        ---@field list table<string, Yat.Panel.Symbols.SupportedActions|string> Map of key mappings, an empty string, `""`, disables the mapping.
        mappings = {
          disable_defaults = false,
          list = {
            ["q"] = "close_sidebar",
            ["<C-x>"] = "close_panel",
            ["?"] = "open_help",
            ["<C-g>"] = "open_git_status_panel",
            ["b"] = "open_buffers_panel",
            ["gc"] = "open_call_hierarchy_panel",
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
            ["R"] = "refresh_panel",
            ["P"] = "focus_parent",
            ["<"] = "focus_prev_sibling",
            [">"] = "focus_next_sibling",
            ["K"] = "focus_first_sibling",
            ["J"] = "focus_last_sibling",
            ["S"] = "search_for_node_in_panel",
            ["[e"] = "focus_prev_diagnostic_item",
            ["]e"] = "focus_next_diagnostic_item",
          },
        },
        ---@alias Yat.Config.Panels.Symbols.DirectoryRendererName "indentation"|"icon"|"name"|"modified"|"symbol_details"|"diagnostics"|string
        ---@alias Yat.Config.Panels.Symbols.FileRendererName "indentation"|"icon"|"name"|"symbol_details"|"diagnostics"|string

        ---@class Yat.Config.Panels.Symbols.Renderers : Yat.Config.Panels.TreeRenderers
        ---@field directory { name : Yat.Config.Panels.Symbols.DirectoryRendererName, override : Yat.Config.BaseRendererConfig }[]
        ---@field file { name : Yat.Config.Panels.Symbols.FileRendererName, override : Yat.Config.BaseRendererConfig }[]
        renderers = {
          directory = {
            { name = "indentation" },
            { name = "icon" },
            { name = "name" },
            { name = "symbol_details" },
            { name = "diagnostics" },
          },
          file = {
            { name = "indentation" },
            { name = "icon" },
            { name = "name" },
            { name = "symbol_details" },
            { name = "diagnostics" },
          },
        },
      },

      ---@class Yat.Config.Panels.CallHierarchy : Yat.Config.Panels.Panel
      ---@field title string The name of the panel, default: `"Call Hierarchy"`.
      ---@field icon string The icon for the panel, default" `""`.
      ---@field mappings Yat.Config.Panels.CallHierarchy.Mappings Panel specific mappings.
      ---@field renderers Yat.Config.Panels.CallHierarchy.Renderers Panel specific renderers.
      call_hierarchy = {
        title = "Call Hierarchy",
        icon = "", --  , ,
        ---@class Yat.Config.Panels.CallHierarchy.Mappings : Yat.Config.Panels.Mappings
        ---@field disable_defaults boolean Whether to disable all default mappings, default: `false`.
        ---@field list table<string, Yat.Panel.CallHierarchy.SupportedActions|string> Map of key mappings, an empty string, `""`, disables the mapping.
        mappings = {
          disable_defaults = false,
          list = {
            ["q"] = "close_sidebar",
            ["<C-x>"] = "close_panel",
            ["?"] = "open_help",
            ["gs"] = "open_symbols_panel",
            ["<C-g>"] = "open_git_status_panel",
            ["b"] = "open_buffers_panel",
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
            ["R"] = "refresh_panel",
            ["P"] = "focus_parent",
            ["<"] = "focus_prev_sibling",
            [">"] = "focus_next_sibling",
            ["K"] = "focus_first_sibling",
            ["J"] = "focus_last_sibling",
            ["S"] = "search_for_node_in_panel",
            ["gt"] = "toggle_call_direction",
            ["gc"] = "create_call_hierarchy_from_buffer_position",
          },
        },
        ---@alias Yat.Config.Panels.CallHierarchy.DirectoryRendererName "indentation"|"icon"|"name"|"symbol_details"|string
        ---@alias Yat.Config.Panels.CallHierarchy.FileRendererName "indentation"|"icon"|"name"|"symbol_details"|string

        ---@class Yat.Config.Panels.CallHierarchy.Renderers : Yat.Config.Panels.TreeRenderers
        ---@field directory { name : Yat.Config.Panels.CallHierarchy.DirectoryRendererName, override : Yat.Config.BaseRendererConfig }[]
        ---@field file { name : Yat.Config.Panels.CallHierarchy.FileRendererName, override : Yat.Config.BaseRendererConfig }[]
        renderers = {
          directory = {
            { name = "indentation" },
            { name = "icon" },
            { name = "name" },
            { name = "symbol_details" },
          },
          file = {
            { name = "indentation" },
            { name = "icon" },
            { name = "name" },
            { name = "symbol_details" },
          },
        },
      },

      ---@class Yat.Config.Panels.Buffers : Yat.Config.Panels.Panel
      ---@field title string The name of the panel, default: `"Buffers"`.
      ---@field icon string The icon for the panel, default: `""`.
      ---@field mappings Yat.Config.Panels.Buffers.Mappings Panel specific mappings.
      ---@field renderers Yat.Config.Panels.Buffers.Renderers Panel specific renderers.
      buffers = {
        title = "Buffers",
        icon = "",

        ---@class Yat.Config.Panels.Buffers.Mappings: Yat.Config.Panels.Mappings
        ---@field disable_defaults boolean Whether to disable all default mappings, default: `false`.
        ---@field list table<string, Yat.Panel.Buffers.SupportedActions|string> Map of key mappings, an empty string, `""`, disables the mapping.
        mappings = {
          disable_defaults = false,
          list = {
            ["q"] = "close_sidebar",
            ["<C-x>"] = "close_panel",
            ["?"] = "open_help",
            ["gs"] = "open_symbols_panel",
            ["<C-g>"] = "open_git_status_panel",
            ["gc"] = "open_call_hierarchy_panel",
            ["gx"] = "system_open",
            ["<C-i>"] = "show_node_info",
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
            ["R"] = "refresh_panel",
            ["P"] = "focus_parent",
            ["<"] = "focus_prev_sibling",
            [">"] = "focus_next_sibling",
            ["K"] = "focus_first_sibling",
            ["J"] = "focus_last_sibling",
            ["<C-]>"] = "cd_to",
            ["."] = "cd_to",
            ["I"] = "toggle_ignored",
            ["H"] = "toggle_filter",
            ["S"] = "search_for_node_in_panel",
            ["gn"] = "goto_node_in_files_panel",
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
        ---@alias Yat.Config.Panels.Buffers.DirectoryRendererName "indentation"|"icon"|"name"|"repository"|"symlink_target"|"git_status"|"diagnostics"|string
        ---@alias Yat.Config.Panels.Buffers.FileRendererName "indentation"|"icon"|"name"|"symlink_target"|"modified"|"git_status"|"diagnostics"|"buffer_info"|string

        ---@class Yat.Config.Panels.Buffers.Renderers : Yat.Config.Panels.TreeRenderers
        ---@field directory { name : Yat.Config.Panels.Buffers.DirectoryRendererName, override : Yat.Config.BaseRendererConfig }[]
        ---@field file { name : Yat.Config.Panels.Buffers.FileRendererName, override : Yat.Config.BaseRendererConfig }[]
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

    ---@alias Yat.Ui.Renderer.Name "indentation"|"icon"|"name"|"modified"|"repository"|"symlink_target"|"git_status"|"diagnostics"|"buffer_info"|"clipboard"|"symbol_details"|string

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
      ---@field symbol_details Yat.Config.Renderers.Builtin.SymbolDetails Symbol details rendering configuration.
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
        ---@field directory_min_severity DiagnosticSeverity The minimum severity necessary to show for directories, see `|vim.diagnostic.severity|`, default: `vim.diagnostic.severity.ERROR`.
        ---@field file_min_severity DiagnosticSeverity The minimum severity necessary to show for files, see `|vim.diagnostic.severity|`, default: `vim.diagnostic.severity.HINT`.
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

        ---@class Yat.Config.Renderers.Builtin.SymbolDetails : Yat.Config.BaseRendererConfig
        ---@field padding string The padding to use to the left of the renderer, default: `" "`.
        symbol_details = {
          padding = " ",
        },
      },
    },
  },
}

M.config = vim.deepcopy(M.default) --[[@as Yat.Config]]
M.setup_called = false

---@param opts? Yat.Config
---@return Yat.Config config
function M.setup(opts)
  opts = opts or {}
  M.config = vim.tbl_deep_extend("force", M.default, opts) --[[@as Yat.Config]]
  M.setup_called = true

  local utils = require("ya-tree.utils")

  -- make sure any custom panel configs have the required shape
  for _, panel in pairs(M.config.panels) do
    if not panel.mappings then
      panel.mappings = {}
    end
    if not panel.mappings.list then
      panel.mappings.list = {}
    end
  end
  if opts.panels then
    for name, panel in pairs(opts.panels) do
      if panel.mappings and panel.mappings.disable_defaults then
        M.config.panels[name].mappings.list = opts.panels[name].mappings.list or {}
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
    if fn.executable("yadm") == 0 then
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
    elseif fn.executable("find") == 1 and fn.has("win32") == 0 then
      M.config.search.cmd = "find"
    elseif fn.executable("where") == 1 then
      M.config.search.cmd = "where"
    else
      utils.warn("None of the default search programs was found in the PATH!\nSearching will not be possible.")
    end
  else
    if fn.executable(M.config.search.cmd) == 0 then
      utils.warn(
        string.format("'search.cmd' is set to %q, which cannot be found in PATH!\nSearching will not be possible", M.config.search.cmd)
      )
      M.config.search.cmd = nil
    end
  end
  if M.config.search.max_results == 0 then
    utils.warn("'search.max_results' is set to 0, disabling it, this can cause performance issues!")
  end

  local sorting = M.config.sorting
  if not (sorting.directories_first and not sorting.case_sensitive and sorting.sort_by == "name") then
    local Node = require("ya-tree.nodes.node")
    local sort_by = sorting.sort_by
    if type(sort_by) == "function" then
      Node.node_comparator = sort_by
    else
      Node.static.create_comparator(sorting.directories_first, sorting.case_sensitive, sort_by)
    end
  end

  return M.config
end

return M
