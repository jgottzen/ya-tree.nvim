local fn = vim.fn

local M = {
  ---@class YaTreeConfig
  ---@field auto_close boolean Force closing Neovim when YaTree is the last window, default: `false`.
  ---@field auto_reload_on_write boolean Reloads the tree and the directory of the file changed, default: `true`.
  ---@field follow_focused_file boolean Update the focused file in the tree on `BufEnter`, default: `false`.
  ---@field hijack_cursor boolean Keep the cursor on the name in tree, default: `false`.
  ---@field move_buffers_from_tree_window boolean Move buffers from the tree window to the last used window, default: `true`.
  ---@field replace_netrw boolean Replace `netrw` windows, default: `true`.
  ---@field mappings table<string, YaTreeActionName|YaTreeConfig.CustomMapping> Map of key mappings.
  default = {
    auto_close = false,
    auto_reload_on_write = true,

    follow_focused_file = false,
    hijack_cursor = false,
    move_buffers_from_tree_window = true,

    replace_netrw = true,

    ---@class YaTreeConfig.Log Logging configuration.
    ---@field level LogLevel The logging level used, default `"warn"`.
    ---@field to_console boolean Whether to log to the console, default: `false`.
    ---@field to_file boolean Whether to log the the log file, default: `false`.
    log = {
      level = "warn",
      to_console = false,
      to_file = false,
    },

    ---@class YaTreeConfig.AutoOpen Auto-open configuration.
    ---@field on_setup boolean Automatically open the tree when running setup, default: `false`.
    ---@field on_new_tab boolean Automatically open the tree when opening a new tabpage, default: `false`.
    ---@field focus_tree boolean Wether to focus the tree when automatically opened, default: `false`.
    auto_open = {
      on_setup = false,
      on_new_tab = false,
      focus_tree = false,
    },

    ---@class YaTreeConfig.Cwd Cwd configuration.
    ---@field follow boolean Update the tree root directory on `DirChanged`, default: `false`.
    ---@field update_from_tree boolean Update the tab cwd when changing root directory in the tree, default: `false`.
    cwd = {
      follow = false,
      update_from_tree = false,
    },

    ---@class YaTreeConfig.Search Tree search configuration.
    ---@field max_results number Max number of search results, only `fd` supports it, setting to 0 will disable it, default: `200`.
    ---@field cmd string|nil Override the search command to use, default: `nil`.
    ---@field args string[]|fun(cmd: string, term: string, path:string, config: YaTreeConfig):string[] Override the search command arguments to use, default: `nil`.
    search = {
      max_results = 200,
      cmd = nil,
      args = nil,
    },

    ---@class YaTreeConfig.Filters Tree filters configuration.
    ---@field enable boolean If filters are enabled, toggleable, default: `true`.
    ---@field dotfiles boolean If dotfiles should be hidden, default: `true`.
    ---@field custom string[] Custom file/directory names to hide, default: `{}`.
    filters = {
      enable = true,
      dotfiles = true,
      custom = {},
    },

    ---@class YaTreeConfig.Git Git configuration.
    ---@field enable boolean If git should be enabled, default: `true`.
    ---@field show_ignored boolean Whether to show git ignored files in the tree, toggleable, default: `true`.
    ---@field watch_git_dir boolean Whether to watch the repository `.git` directory for changes, using `fs_poll`, default: `true`.
    ---@field watch_git_dir_interval number Interval for polling, in milliseconds, default `1000`.
    git = {
      enable = true,
      show_ignored = true,
      watch_git_dir = true,
      watch_git_dir_interval = 1000,

      ---@class YaTreeConfig.Git.Yadm `yadm` configuration.
      ---@field enable boolean Wether yadm is enabled, requires git to be enabled, default: `false`.
      yadm = {
        enable = false,
      },
    },

    ---@class YaTreeConfig.Diagnostics Lsp diagnostics configuration.
    ---@field enable boolean Show lsp diagnostics in the tree, default: `true`.
    ---@field debounce_time number Debounce time in ms, for how often `DiagnosticChanged` are processed, default: `300`.
    ---@field propagate_to_parents boolean If the diagnostic status should be propagated to parents, default: `true`.
    diagnostics = {
      enable = true,
      debounce_time = 300,
      propagate_to_parents = true,
    },

    ---@class YaTreeConfig.SystemOpen Open file with system command configuration.
    ---@field cmd string|nil The system open command, if unspecified the detected OS determines the default, Linux: `xdg-open`, OS X: `open`, Windows: `cmd`.
    ---@field args string[]|nil Any arguments for the system open command, default: `{}` for Linux and OS X, `{"/c", "start"}` for Windows.
    system_open = {
      cmd = nil,
      args = {},
    },

    ---@class YaTreeConfig.Trash `trash-cli` configuration.
    ---@field enable boolean Wether to enable trashing in the tree (`trash-cli must be installed`), default: `true`.
    ---@field require_confirm boolean Confirm before trashing file(s), default: `false`.
    trash = {
      enable = true,
      require_confirm = false,
    },

    ---@class YaTreeConfig.View Tree view configuration.
    ---@field width number Widht of the tree panel, default: `40`.
    ---@field side "left"|"right" Where the tree panel is placed, default: `"left"`.
    ---@field number boolean Wether to show the number column, default: `false`.
    ---@field relativenumber boolean Wether to show relative numbers, default: `false`.
    ---@field on_open fun(config: YaTreeConfig) Callback function when the tree view is opened, default: `nil`.
    ---@field on_close fun(config: YaTreeConfig) Callback function when the tree view is closed, default: `nil`.
    view = {
      width = 40,
      side = "left",
      number = false,
      relativenumber = false,
      on_open = nil,
      on_close = nil,

      ---@class YaTreeConfig.View.Barbar `romgrk/barbar.nvim` integration configuration.
      ---@field enable boolean Integrate with `romgrk/barbar.nvim` and adjust the tabline, default: `false`.
      ---@field title string|nil Buffer line title, default: `nil`.
      barbar = {
        enable = false,
        title = nil,
      },

      ---@class YaTreeConfig.View.Renderers.DirectoryRenderer : YaTreeRendererConfig
      ---@field [1] string
      ---@class YaTreeConfig.View.Renderers.FileRenderer : YaTreeRendererConfig
      ---@field [1] string

      ---@class YaTreeConfig.View.Renderers Which renderers to use in the tree view.
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
          { "symlink_target" },
          { "git_status" },
          { "diagnostics" },
          { "buffer_number" },
          { "clipboard" },
        },
      },
    },

    ---@class YaTreeRendererConfig
    ---@field padding string The padding to use to the left of the renderer.
    ---@field view_mode YaTreeCanvasDisplayMode[] Which view modes the renderer should display in.

    ---@class YaTreeConfig.Renderers Renderer configuration.
    renderers = {
      ---@class YaTreeConfig.Renderers.Indentation : YaTreeRendererConfig Indentation rendering configuration.
      ---@field padding string The padding to use to the left of the renderer, default: `""`.
      ---@field view_mode YaTreeCanvasDisplayMode[] Which view modes the renderer should display in, default: `{ "tree", "search", "buffers" }`.
      ---@field use_marker boolean Wether to show indent markers, default: `false`.
      ---@field indent_marker string Default: `"│"`.
      ---@field last_indent_marker string Default: `"└"`.
      indentation = {
        padding = "",
        view_mode = { "tree", "search", "buffers", "git_status" },
        use_marker = false,
        indent_marker = "│",
        last_indent_marker = "└",
      },

      ---@class YaTreeConfig.Renderers.Icon : YaTreeRendererConfig Icon rendering configuration.
      ---@field padding string The padding to use to the left of the renderer, default: `""`.
      ---@field view_mode YaTreeCanvasDisplayMode[] Which view modes the renderer should display in, default: `{ "tree", "search", "buffers" }`.
      icon = {
        padding = "",
        view_mode = { "tree", "search", "buffers", "git_status" },

        ---@class YaTreeConfig.Renderers.Icon.Directory Directory icon rendering configuration.
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

        ---@class YaTreeConfig.Renderers.Icon.File File icon rendering configuration.
        ---@field default string The default icon for files, default: `""`.
        ---@field symlink string The icon for symbolic link files, default: `""`.
        file = {
          default = "",
          symlink = "",
        },
      },

      ---@class YaTreeConfig.Renderers.Name : YaTreeRendererConfig File and directory name rendering configuration.
      ---@field padding string The padding to use to the left of the renderer, default: `" "`.
      ---@field view_mode YaTreeCanvasDisplayMode[] Which view modes the renderer should display in, default: `{ "tree", "search", "buffers" }`.
      ---@field root_folder_format string The root folder format as per `fnamemodify`, default: `":~"`.
      ---@field trailing_slash boolean Wether to show a trailing os directory separator after directory names, default: `false`.
      ---@field use_git_status_colors boolean Wether to color the name with the git status color, default: `false`.
      ---@field highlight_open_file boolean Wether to highlight the name if it's open in a buffer, default: `false`.
      name = {
        padding = " ",
        view_mode = { "tree", "search", "buffers", "git_status" },
        root_folder_format = ":~",
        trailing_slash = false,
        use_git_status_colors = false,
        highlight_open_file = false,
      },

      ---@class YaTreeConfig.Renderers.Repository : YaTreeRendererConfig Repository rendering configuration.
      ---@field padding string The padding to use to the left of the renderer, default: `" "`.
      ---@field view_mode YaTreeCanvasDisplayMode[] Which view modes the renderer should display in, default: `{ "tree", "search", "buffers" }`.
      ---@field show_status boolean Whether to show repository status on the repository toplevel directory, default: `true`.
      repository = {
        padding = " ",
        view_mode = { "tree", "search", "buffers", "git_status" },
        show_status = true,

        ---@class YaTreeConfig.Renderers.Repository.Icons Repository icons, setting an icon to an empty string will disabled that particular status information.
        ---@field behind string The icon for the behind count, default: `"⇣"`.
        ---@field ahead string The icon for the ahead count, default: `"⇡"`.
        ---@field stashed string The icon for the stashed count, default: `"*"`.
        ---@field unmerged string The icon for the unmerged count, default: `"~"`.
        ---@field staged string The icon for the staged count, default: `"+"`.
        ---@field unstaged string The icon for the unstaged count, default: `"!"`.
        ---@field untracked string The icon for the untracked cound, default: `"?"`.
        icons = {
          behind = "⇣",
          ahead = "⇡",
          stashed = "*",
          unmerged = "~",
          staged = "+",
          unstaged = "!",
          untracked = "?",

          ---@class YaTreeConfig.Renderers.Repository.Icons.Remote Repository remote host icons.
          ---@field default string The default icon for marking the git toplevel directory, default: `""`.
          ---@field github.com string The icon for github.com, default: `""`.
          ---@field gitlab.com string The icon for gitlab.com, default: `""`.
          remote = {
            default = "",
            ["://github.com/"] = "",
            ["://gitlab.com/"] = "",
          },
        },
      },

      ---@class YaTreeConfig.Renderers.SymlinkTarget : YaTreeRendererConfig Symbolic link rendering configuration.
      ---@field padding string The padding to use to the left of the renderer, default: `" "`.
      ---@field view_mode YaTreeCanvasDisplayMode[] Which view modes the renderer should display in, default: `{ "tree", "search", "buffers" }`.
      ---@field arrow_icon string The icon to use before the sybolic link target, default: `"➛"`.
      symlink_target = {
        padding = " ",
        view_mode = { "tree", "search", "buffers", "git_status" },
        arrow_icon = "➛",
      },

      ---@class YaTreeConfig.Renderers.GitStatus : YaTreeRendererConfig Git status rendering configuration.
      ---@field padding string The padding to use to the left of the renderer, default: `" "`.
      ---@field view_mode YaTreeCanvasDisplayMode[] Which view modes the renderer should display in, default: `{ "tree", "search", "buffers" }`.
      git_status = {
        padding = " ",
        view_mode = { "tree", "search", "buffers", "git_status" },

        ---@class YaTreeConfig.Renderers.GitStatus.Icons Git status icon configuration.
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

          ---@class YaTreeConfig.Renderers.GitStatus.Icons.Merge Git status icons for merge information.
          ---@field us string The icon for added/deleted/modified by `us`, default: `"➜"`.
          ---@field them string The icon for added/deleted/modified by `them`, default: `""`.
          ---@field both string The icon for added/deleted/modified by `both`, default: `""`.
          merge = {
            us = "➜",
            them = "",
            both = "",
          },
        },
      },

      ---@class YaTreeConfig.Renderers.Diagnostics : YaTreeRendererConfig Lsp diagnostics rendering configuration.
      ---@field padding string The padding to use to the left of the renderer, default: `" "`.
      ---@field view_mode YaTreeCanvasDisplayMode[] Which view modes the renderer should display in, default: `{ "tree", "search", "buffers" }`.
      ---@field min_severity number The minimum severity necessary to show, see `|vim.diagnostic.severity|`, default: `vim.diagnostic.severity.HINT`.
      diagnostics = {
        padding = " ",
        view_mode = { "tree", "search", "buffers", "git_status" },
        min_severity = vim.diagnostic.severity.HINT,
      },

      ---@class YaTreeConfig.Renderers.BufferNumber : YaTreeRendererConfig Buffer number rendering configuration.
      ---@field padding string The padding to use to the left of the renderer, default: `" "`.
      ---@field view_mode YaTreeCanvasDisplayMode[] Which view modes the renderer should display in, default: `{ "buffers" }`.
      buffer_number = {
        padding = " ",
        view_mode = { "buffers" },
      },

      ---@class YaTreeConfig.Renderers.Clipboard : YaTreeRendererConfig Clipboard rendering configuration.
      ---@field padding string The padding to use to the left of the renderer, default: `" "`.
      ---@field view_mode YaTreeCanvasDisplayMode[] Which view modes the renderer should display in, default: `{ "tree" }`.
      clipboard = {
        padding = " ",
        view_mode = { "tree" },
      },
    },

    ---@class YaTreeConfig.CustomMapping Key mapping for user functions configuration.
    ---@field modes string[] The mode(s) for the keybinding.
    ---@field views YaTreeCanvasDisplayMode[] The view modes the mapping is available for.
    ---@field fn fun(node: YaTreeNode) User function.
    ---@field desc? string Description of what the mapping does.

    mappings = {
      ["q"] = "close_window",
      ["<CR>"] = "open",
      ["o"] = "open",
      ["<2-LeftMouse>"] = "open",
      ["<C-v>"] = "vsplit",
      ["<C-s>"] = "split",
      ["t"] = "tabnew",
      ["<Tab>"] = "preview",
      ["<BS>"] = "close_node",
      ["z"] = "close_all_nodes",
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
      ["I"] = "toggle_ignored",
      ["H"] = "toggle_filter",
      ["R"] = "refresh_tree",
      ["/"] = "search_interactively",
      ["f"] = "search_once",
      ["gn"] = "goto_node_in_tree",
      ["gp"] = "goto_path_in_tree",
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
      ["b"] = "toggle_buffers",
      ["<C-g>"] = "toggle_git_status",
    },
  },
}

---@type YaTreeConfig
M.config = vim.deepcopy(M.default)

---@param opts? YaTreeConfig
---@return YaTreeConfig config
function M.setup(opts)
  opts = opts or {}
  M.config = vim.tbl_deep_extend("force", M.default, opts)

  local utils = require("ya-tree.utils")

  -- convert the list of custom filters to a table for quicker lookups

  M.config.filters.custom = {}
  local custom_filters = opts.filters and opts.filters.custom or {}
  if not vim.tbl_islist(custom_filters) then
    utils.warn("'filters.custom' must be an array, ignoring the configuration!")
  else
    for _, name in ipairs(custom_filters) do
      M.config.filters.custom[name] = true
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
