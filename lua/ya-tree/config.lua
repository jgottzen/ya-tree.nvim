local fn = vim.fn

local M = {
  ---@class YaTreeConfig
  ---@field auto_close boolean Force closing Neovim when YaTree is the last window, default: `false`.
  ---@field auto_reload_on_write boolean Reloads the tree and the directory of the file changed, default: `true`.
  ---@field follow_focused_file boolean Update the focused file in the tree on `BufEnter`, default: `false`.
  ---@field hijack_cursor boolean Keep the cursor on the name in tree, default: `false`.
  ---@field move_buffers_from_tree_window boolean Move buffers from the tree window to the last used window, default: `true`.
  ---@field replace_netrw boolean Replace `netrw` windows, default: `true`.
  ---@field log YaTreeConfig.Log Logging configuration.
  ---@field auto_open YaTreeConfig.AutoOpen Auto-open configuration.
  ---@field cwd YaTreeConfig.Cwd Cwd configuration.
  ---@field search YaTreeConfig.Search Search configuration.
  ---@field filters YaTreeConfig.Filters Filters configuration.
  ---@field git YaTreeConfig.Git Git configuration.
  ---@field diagnostics YaTreeConfig.Diagnostics Lsp diagnostics configuration.
  ---@field system_open YaTreeConfig.SystemOpen Open file with system command configuration.
  ---@field trash YaTreeConfig.Trash `trash-cli` configuration.
  ---@field view YaTreeConfig.View Tree view configuration.
  ---@field renderers YaTreeConfig.Renderers Renderer configurations.
  ---@field mappings YaTreeConfig.Mappings Key mapping configuration.
  default = {
    auto_close = false,
    auto_reload_on_write = true,

    follow_focused_file = false,
    hijack_cursor = false,
    move_buffers_from_tree_window = true,

    replace_netrw = true,

    expand_all_nodes_max_depth = 5,

    ---@class YaTreeConfig.Log
    ---@field level LogLevel The logging level used, default `"warn"`.
    ---@field to_console boolean Whether to log to the console, default: `false`.
    ---@field to_file boolean Whether to log the the log file, default: `false`.
    log = {
      level = "warn",
      to_console = false,
      to_file = false,
    },

    ---@class YaTreeConfig.AutoOpen
    ---@field on_setup boolean Automatically open the tree when running setup, default: `false`.
    ---@field on_new_tab boolean Automatically open the tree when opening a new tabpage, default: `false`.
    ---@field focus_tree boolean Wether to focus the tree when automatically opened, default: `false`.
    auto_open = {
      on_setup = false,
      on_new_tab = false,
      focus_tree = false,
    },

    ---@class YaTreeConfig.Cwd
    ---@field follow boolean Update the tree root directory on `DirChanged`, default: `false`.
    ---@field update_from_tree boolean Update the tab cwd when changing root directory in the tree, default: `false`.
    cwd = {
      follow = false,
      update_from_tree = false,
    },

    ---@class YaTreeConfig.Search
    ---@field max_results number Max number of search results, only `fd` supports it, setting to 0 will disable it, default: `200`.
    ---@field cmd? string Override the search command to use, default: `nil`.
    ---@field args? string[]|fun(cmd: string, term: string, path:string, config: YaTreeConfig):string[] Override the search command arguments to use, default: `nil`.
    search = {
      max_results = 200,
      cmd = nil,
      args = nil,
    },

    ---@class YaTreeConfig.Filters
    ---@field enable boolean If filters are enabled, toggleable, default: `true`.
    ---@field dotfiles boolean If dotfiles should be hidden, default: `true`.
    ---@field custom string[] Custom file/directory names to hide, default: `{}`.
    filters = {
      enable = true,
      dotfiles = true,
      custom = {},
    },

    ---@class YaTreeConfig.Git
    ---@field enable boolean If git should be enabled, default: `true`.
    ---@field show_ignored boolean Whether to show git ignored files in the tree, toggleable, default: `true`.
    ---@field watch_git_dir boolean Whether to watch the repository `.git` directory for changes, using `fs_poll`, default: `true`.
    ---@field watch_git_dir_interval number Interval for polling, in milliseconds, default `1000`.
    ---@field yadm YaTreeConfig.Git.Yadm `yadm` configuration.
    git = {
      enable = true,
      show_ignored = true,
      watch_git_dir = true,
      watch_git_dir_interval = 1000,

      ---@class YaTreeConfig.Git.Yadm
      ---@field enable boolean Wether yadm is enabled, requires git to be enabled, default: `false`.
      yadm = {
        enable = false,
      },
    },

    ---@class YaTreeConfig.Diagnostics
    ---@field enable boolean Show lsp diagnostics in the tree, default: `true`.
    ---@field debounce_time number Debounce time in ms, for how often `DiagnosticChanged` are processed, default: `300`.
    ---@field propagate_to_parents boolean If the diagnostic status should be propagated to parents, default: `true`.
    diagnostics = {
      enable = true,
      debounce_time = 300,
      propagate_to_parents = true,
    },

    ---@class YaTreeConfig.SystemOpen
    ---@field cmd? string The system open command, if unspecified the detected OS determines the default, Linux: `xdg-open`, OS X: `open`, Windows: `cmd`.
    ---@field args string[] Any arguments for the system open command, default: `{}` for Linux and OS X, `{"/c", "start"}` for Windows.
    system_open = {
      cmd = nil,
      args = {},
    },

    ---@class YaTreeConfig.Trash
    ---@field enable boolean Wether to enable trashing in the tree (`trash-cli must be installed`), default: `true`.
    ---@field require_confirm boolean Confirm before trashing file(s), default: `false`.
    trash = {
      enable = true,
      require_confirm = false,
    },

    ---@class YaTreeConfig.View
    ---@field width number Widht of the tree panel, default: `40`.
    ---@field side "left"|"right" Where the tree panel is placed, default: `"left"`.
    ---@field number boolean Wether to show the number column, default: `false`.
    ---@field relativenumber boolean Wether to show relative numbers, default: `false`.
    ---@field on_open? fun(config: YaTreeConfig) Callback function when the tree view is opened, default: `nil`.
    ---@field on_close? fun(config: YaTreeConfig) Callback function when the tree view is closed, default: `nil`.
    ---@field barbar YaTreeConfig.View.Barbar `romgrk/barbar.nvim` integration configuration.
    ---@field popups YaTreeConfig.View.Popups Popup window configuration.
    ---@field renderers YaTreeConfig.View.Renderers Which renderers to use in the tree view.
    view = {
      width = 40,
      side = "left",
      number = false,
      relativenumber = false,
      on_open = nil,
      on_close = nil,

      ---@class YaTreeConfig.View.Barbar
      ---@field enable boolean Integrate with `romgrk/barbar.nvim` and adjust the tabline, default: `false`.
      ---@field title? string Buffer line title, default: `nil`.
      barbar = {
        enable = false,
        title = nil,
      },

      ---@class YaTreeConfig.View.Popups
      ---@field border string|string[] The border type for floating windows, default: `"rounded"`.
      popups = {
        border = "rounded",
      },

      ---@class YaTreeConfig.View.Renderers.DirectoryRenderer : YaTreeRendererConfig
      ---@field [1] string
      ---@class YaTreeConfig.View.Renderers.FileRenderer : YaTreeRendererConfig
      ---@field [1] string

      ---@class YaTreeConfig.View.Renderers
      ---@field directory YaTreeConfig.View.Renderers.DirectoryRenderer[] Which renderers to use for directories, in order.
      ---@field file YaTreeConfig.View.Renderers.FileRenderer[] Which renderers to use for files, in order.
      renderers = {
        directory = {
          { "indentation" },
          { "icon" },
          { "name" },
          { "repository" },
          { "symlink_target" },
          { "git_status" },
          { "diagnostics", min_severity = vim.diagnostic.severity.ERROR },
          { "clipboard" },
        },
        file = {
          { "indentation" },
          { "icon" },
          { "name", use_git_status_colors = true },
          { "modified" },
          { "symlink_target" },
          { "git_status" },
          { "diagnostics" },
          { "buffer_info" },
          { "clipboard" },
        },
      },
    },

    ---@class YaTreeRendererConfig
    ---@field padding string The padding to use to the left of the renderer.
    ---@field tree_types YaTreeType[]|string[] Which tree types the renderer should display in.

    ---@class YaTreeConfig.Renderers
    ---@field indentation YaTreeConfig.Renderers.Indentation Indentation rendering configuration.
    ---@field icon YaTreeConfig.Renderers.Icon Icon rendering configuration.
    ---@field name YaTreeConfig.Renderers.Name File and directory name rendering configuration.
    ---@field modified YaTreeConfig.Renderers.Modified Modified file rendering configurations.
    ---@field repository YaTreeConfig.Renderers.Repository Repository rendering configuration.
    ---@field symlink_target YaTreeConfig.Renderers.SymlinkTarget Symbolic link rendering configuration.
    ---@field git_status YaTreeConfig.Renderers.GitStatus Git status rendering configuration.
    ---@field diagnostics YaTreeConfig.Renderers.Diagnostics Lsp diagnostics rendering configuration.
    ---@field buffer_info YaTreeConfig.Renderers.BufferInfo Buffer info rendering configuration.
    ---@field clipboard YaTreeConfig.Renderers.Clipboard Clipboard rendering configuration.
    renderers = {
      ---@class YaTreeConfig.Renderers.Indentation : YaTreeRendererConfig
      ---@field padding string The padding to use to the left of the renderer, default: `""`.
      ---@field tree_types YaTreeType[]|string[] Which tree types the renderer should display in, default: `{ "files", "search", "buffers", "git" }`.
      ---@field use_indent_marker boolean Wether to show indent markers, default: `false`.
      ---@field indent_marker string The icon for the indentation marker, default: `"│"`.
      ---@field last_indent_marker string The icon for the last indentation marker, default: `"└"`.
      ---@field use_expander_marker boolean Whether to show expanded and collapsed markers, default: `false`.
      ---@field expanded_marker string The icon for expanded directories/containers, default `""`.
      ---@field collapsed_marker string The icon for collapsed directories/containers, default `""`.
      indentation = {
        padding = "",
        tree_types = { "files", "search", "buffers", "git" },
        use_indent_marker = false,
        indent_marker = "│",
        last_indent_marker = "└",
        use_expander_marker = false,
        expanded_marker = "",
        collapsed_marker = "",
      },

      ---@class YaTreeConfig.Renderers.Icon : YaTreeRendererConfig
      ---@field padding string The padding to use to the left of the renderer, default: `""`.
      ---@field tree_types YaTreeType[]|string[] Which tree types the renderer should display in, default: `{ "files", "search", "buffers", "git" }`.
      ---@field directory YaTreeConfig.Renderers.Icon.Directory Directory icon rendering configuration.
      ---@field file YaTreeConfig.Renderers.Icon.File File icon rendering configuration.
      icon = {
        padding = "",
        tree_types = { "files", "search", "buffers", "git" },

        ---@class YaTreeConfig.Renderers.Icon.Directory
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

        ---@class YaTreeConfig.Renderers.Icon.File
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

      ---@class YaTreeConfig.Renderers.Name : YaTreeRendererConfig
      ---@field padding string The padding to use to the left of the renderer, default: `" "`.
      ---@field tree_types YaTreeType[]|string[] Which tree types the renderer should display in, default: `{ "files", "search", "buffers", "git" }`.
      ---@field root_folder_format string The root folder format as per `fnamemodify`, default: `":~"`.
      ---@field trailing_slash boolean Wether to show a trailing os directory separator after directory names, default: `false`.
      ---@field use_git_status_colors boolean Wether to color the name with the git status color, default: `false`.
      ---@field highlight_open_file boolean Wether to highlight the name if it's open in a buffer, default: `false`.
      name = {
        padding = " ",
        tree_types = { "files", "search", "buffers", "git" },
        root_folder_format = ":~",
        trailing_slash = false,
        use_git_status_colors = false,
        highlight_open_file = false,
      },

      ---@class YaTreeConfig.Renderers.Modified : YaTreeRendererConfig
      ---@field padding string The padding to use to the left of the renderer, default: `" "`.
      ---@field tree_types YaTreeType[]|string[] Which tree types the renderer should display in, default: `{ "files", "search", "buffers", "git" }`.
      ---@field icon string The icon for modified files.
      modified = {
        padding = " ",
        tree_types = { "files", "search", "buffers", "git" },
        icon = "[+]",
      },

      ---@class YaTreeConfig.Renderers.Repository : YaTreeRendererConfig
      ---@field padding string The padding to use to the left of the renderer, default: `" "`.
      ---@field tree_types YaTreeType[]|string[] Which tree types the renderer should display in, default: `{ "files", "search", "buffers", "git" }`.
      ---@field show_status boolean Whether to show repository status on the repository toplevel directory, default: `true`.
      ---@field icons YaTreeConfig.Renderers.Repository.Icons Repository icons, setting an icon to an empty string will disabled that particular status information.
      repository = {
        padding = " ",
        tree_types = { "files", "search", "buffers", "git" },
        show_status = true,

        ---@class YaTreeConfig.Renderers.Repository.Icons
        ---@field behind string The icon for the behind count, default: `"⇣"`.
        ---@field ahead string The icon for the ahead count, default: `"⇡"`.
        ---@field stashed string The icon for the stashed count, default: `"*"`.
        ---@field unmerged string The icon for the unmerged count, default: `"~"`.
        ---@field staged string The icon for the staged count, default: `"+"`.
        ---@field unstaged string The icon for the unstaged count, default: `"!"`.
        ---@field untracked string The icon for the untracked cound, default: `"?"`.
        ---@field remote YaTreeConfig.Renderers.Repository.Icons.Remote Repository remote host icons.
        icons = {
          behind = "⇣",
          ahead = "⇡",
          stashed = "*",
          unmerged = "~",
          staged = "+",
          unstaged = "!",
          untracked = "?",

          ---@class YaTreeConfig.Renderers.Repository.Icons.Remote
          ---@field default string The default icon for marking the git toplevel directory, default: `""`.
          remote = {
            default = "",
            ["://github.com/"] = "",
            ["://gitlab.com/"] = "",
          },
        },
      },

      ---@class YaTreeConfig.Renderers.SymlinkTarget : YaTreeRendererConfig
      ---@field padding string The padding to use to the left of the renderer, default: `" "`.
      ---@field tree_types YaTreeType[]|string[] Which tree types the renderer should display in, default: `{ "files", "search", "buffers", "git" }`.
      ---@field arrow_icon string The icon to use before the sybolic link target, default: `"➛"`.
      symlink_target = {
        padding = " ",
        tree_types = { "files", "search", "buffers", "git" },
        arrow_icon = "➛",
      },

      ---@class YaTreeConfig.Renderers.GitStatus : YaTreeRendererConfig
      ---@field padding string The padding to use to the left of the renderer, default: `" "`.
      ---@field tree_types YaTreeType[]|string[] Which tree types the renderer should display in, default: `{ "files", "search", "buffers", "git" }`.
      ---@field icons YaTreeConfig.Renderers.GitStatus.Icons Git status icon configuration.
      git_status = {
        padding = " ",
        tree_types = { "files", "search", "buffers", "git" },

        ---@class YaTreeConfig.Renderers.GitStatus.Icons
        ---@field staged string The icon for staged changes, default: `""`.
        ---@field type_changed string The icon for a type-changed file, default: `""`.
        ---@field added string The icon for an added file, default: `"✚"`.
        ---@field deleted string The icon for a deleted file, default: `""`.
        ---@field renamed string The icon for a renamed file, default: `"➜"`.
        ---@field copied string The icon for a copied file, default: `""`.
        ---@field modified string The icon for modified changes, default: `""`.
        ---@field unmerged string The icon for unmerged changes, default: `""`.
        ---@field ignored string The icon for an ignored file, default: `""`.
        ---@field untracked string The icon for an untracked file, default: `, default: `""`.
        ---@field merge YaTreeConfig.Renderers.GitStatus.Icons.Merge Git status icons for merge information.
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

          ---@class YaTreeConfig.Renderers.GitStatus.Icons.Merge
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

      ---@class YaTreeConfig.Renderers.Diagnostics : YaTreeRendererConfig
      ---@field padding string The padding to use to the left of the renderer, default: `" "`.
      ---@field tree_types YaTreeType[]|string[] Which tree types the renderer should display in, default: `{ "files", "search", "buffers", "git" }`.
      ---@field min_severity number The minimum severity necessary to show, see `|vim.diagnostic.severity|`, default: `vim.diagnostic.severity.HINT`.
      diagnostics = {
        padding = " ",
        tree_types = { "files", "search", "buffers", "git" },
        min_severity = vim.diagnostic.severity.HINT,
      },

      ---@class YaTreeConfig.Renderers.BufferInfo : YaTreeRendererConfig
      ---@field padding string The padding to use to the left of the renderer, default: `" "`.
      ---@field tree_types YaTreeType[]|string[] Which tree types the renderer should display in, default: `{ "buffers" }`.
      buffer_info = {
        padding = " ",
        tree_types = { "buffers" },
        hidden_icon = "",
      },

      ---@class YaTreeConfig.Renderers.Clipboard : YaTreeRendererConfig
      ---@field padding string The padding to use to the left of the renderer, default: `" "`.
      ---@field tree_types YaTreeType[]|string[] Which tree types the renderer should display in, default: `{ "files" }`.
      clipboard = {
        padding = " ",
        tree_types = { "files" },
      },
    },

    ---@class YaTreeConfig.CustomMapping Key mapping for user functions configuration.
    ---@field modes YaTreeActionMode[] The mode(s) for the keybinding.
    ---@field tree_types YaTreeType[]|string[] The tree types the mapping is available for.
    ---@field fn async fun(tree: YaTree, node: YaTreeNode) User function.
    ---@field desc? string Description of what the mapping does.

    ---@class YaTreeConfig.Mappings
    ---@field disable_defaults boolean Whether to diasble all default mappigns, default `true`.
    ---@field list table<string, YaTreeActionName|YaTreeConfig.CustomMapping> Map of key mappings.
    mappings = {
      disable_defaults = false,
      list = {
        ["q"] = "close_window",
        ["<CR>"] = "open",
        ["o"] = "open",
        ["<2-LeftMouse>"] = "open",
        ["<C-v>"] = "vsplit",
        ["<C-s>"] = "split",
        ["t"] = "tabnew",
        ["<Tab>"] = "preview",
        ["<C-Tab>"] = "preview_and_focus",
        ["<BS>"] = "close_node",
        ["Z"] = "close_all_nodes",
        ["z"] = "close_all_child_nodes",
        ["E"] = "expand_all_nodes",
        ["e"] = "expand_all_child_nodes",
        ["<2-RightMouse>"] = "cd_to",
        ["<C-]>"] = "cd_to",
        ["."] = "cd_to",
        ["-"] = "cd_up",
        ["P"] = "focus_parent",
        ["<"] = "focus_prev_sibling",
        [">"] = "focus_next_sibling",
        ["K"] = "focus_first_sibling",
        ["J"] = "focus_last_sibling",
        ["[c"] = "focus_prev_git_item",
        ["]c"] = "focus_next_git_item",
        ["[e"] = "focus_prev_diagnostic_item",
        ["]e"] = "focus_next_diagnostic_item",
        ["I"] = "toggle_ignored",
        ["H"] = "toggle_filter",
        ["R"] = "refresh_tree",
        ["/"] = "search_interactively",
        ["f"] = "search_once",
        ["S"] = "search_for_path_in_tree",
        ["gn"] = "goto_node_in_tree",
        ["<C-x>"] = "close_search",
        ["F"] = "show_last_search",
        ["<C-r>"] = "rescan_dir_for_git",
        ["a"] = "add",
        ["r"] = "rename",
        ["d"] = "delete",
        ["D"] = "trash",
        ["c"] = "copy_node",
        ["x"] = "cut_node",
        ["p"] = "paste_nodes",
        ["<C-c>"] = "clear_clipboard",
        ["y"] = "copy_name_to_clipboard",
        ["Y"] = "copy_root_relative_path_to_clipboard",
        ["gy"] = "copy_absolute_path_to_clipboard",
        ["?"] = "open_help",
        ["gx"] = "system_open",
        ["b"] = "toggle_buffers_view",
        ["<C-g>"] = "toggle_git_view",
        ["<C-i>"] = "show_node_info",
      },
    },
  },
}

---@type YaTreeConfig
M.config = vim.deepcopy(M.default)

---@param opts? YaTreeConfig
---@return YaTreeConfig config
function M.setup(opts)
  opts = opts or {}
  M.config = vim.tbl_deep_extend("force", M.default, opts) --[[@as YaTreeConfig]]

  local utils = require("ya-tree.utils")

  if opts.mappings and opts.mappings.disable_defaults then
    if not opts.mappings.list then
      utils.warn("Default mappings has been disabled, but there are not configured mappings in 'mappings.list.\nUsing default mappings!")
    else
      M.config.mappings.list = opts.mappings.list
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
