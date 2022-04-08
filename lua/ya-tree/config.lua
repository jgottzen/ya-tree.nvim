local M = {
  ---@class YaTreeConfig
  ---@field auto_close boolean Force closing Neovim when YaTree is the last window, default: `false`.
  ---@field auto_reload_on_write boolean Reloads the tree and the directory of the file changed, default: `true`.
  ---@field follow_focused_file boolean Update the focused file in the tree on `BufEnter`, default: `false`.
  ---@field hijack_cursor boolean Keep the cursor on the name in tree, default: `false`.
  ---@field move_buffers_from_tree_window boolean Move buffers from the tree window to the last used window, default: `true`.
  ---@field replace_netrw boolean Replace `netrw` windows, default: `true`.
  ---@field mappings table<string|string[], YaTreeConfig.Mapping> Map of key mappings.
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

    ---@class YaTreeConfig.Cwd Cwd configuration.
    ---@field follow boolean Update the tree root directory on `DirChanged`, default: `false`.
    ---@field update_from_tree boolean Update the tab cwd when changing root directory in the tree, default: `false`.
    cwd = {
      follow = false,
      update_from_tree = false,
    },

    ---@class YaTreeConfig.Search Tree search configuration.
    ---@field max_results number Max number of search results, default: `200`.
    ---@field cmd string|nil Override the search command to use, default: `nil`.
    ---@field args string[]|fun(cmd: string, term: string, path:string, config: YaTreeConfig):string[]|nil Override the search command arguments to use, default: `nil`.
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
    git = {
      enable = true,
      show_ignored = true,

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
    ---@field side "'left'"|"'right'" Where the tree panel is placed, default: `"left"`.
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

      ---@alias YaTreeConfig.View.Renderers.DirectoryRenderer YaTreeRendererConfig
      ---@alias YaTreeConfig.View.Renderers.FileRenderer table

      ---@class YaTreeConfig.View.Renderers Which renderers to use in the tree view.
      ---@field directory YaTreeConfig.View.Renderers.DirectoryRenderer[] Which renderers to use for directories, in order.
      ---@field file YaTreeConfig.View.Renderers.FileRenderer[] Which renderers to use for files, in order.
      renderers = {
        directory = {
          { "indentation" },
          { "icon" },
          { "filter" },
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
          { "name" },
          { "symlink_target" },
          { "git_status" },
          { "diagnostics" },
          { "clipboard" },
        },
      },
    },

    ---@class YaTreeRendererConfig

    ---@class YaTreeConfig.Renderers Renderer configuration.
    renderers = {
      ---@class YaTreeConfig.Renderers.Indentation : YaTreeRendererConfig Indentation rendering configuration.
      ---@field padding string The padding to use to the left of the renderer, default: `""`.
      ---@field use_marker boolean Wether to show indent markers, default: `false`.
      ---@field indent_marker string Default: `"│"`.
      ---@field last_indent_marker string Default: `"└"`.
      indentation = {
        padding = "",
        use_marker = false,
        indent_marker = "│",
        last_indent_marker = "└",
      },

      ---@class YaTreeConfig.Renderers.Icon : YaTreeRendererConfig Icon rendering configuration.
      ---@field padding string The padding to use to the left of the renderer, default: `""`.
      icon = {
        padding = "",

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

      ---@class YaTreeConfig.Renderers.Filter : YaTreeRendererConfig Filter display configuration.
      ---@field padding string The padding to use to the left of the renderer, default: `""`.
      filter = {
        padding = "",
      },

      ---@class YaTreeConfig.Renderers.Name : YaTreeRendererConfig File and directory name rendering configuration.
      ---@field padding string The padding to use to the left of the renderer, default: `" "`.
      ---@field trailing_slash boolean Wether to show a trailing os directory separator after directory names, default: `false`.
      ---@field use_git_status_colors boolean Wether to color the name with the git status color, default: `false`.
      ---@field root_folder_format string The root folder format as per `fnamemodify`, default: `":~"`.
      ---@field highlight_open_file boolean Wether to highlight the name if it's open in a buffer, default: `true`.
      name = {
        padding = " ",
        trailing_slash = false,
        use_git_status_colors = false,
        root_folder_format = ":~",
        highlight_open_file = true,
      },

      ---@class YaTreeConfig.Renderers.Repository : YaTreeRendererConfig Repository rendering configuration.
      ---@field padding string The padding to use to the left of the renderer, default: `" "`.
      ---@field icon string The icon for marking the git toplevel directory, default: `""`.
      repository = {
        padding = " ",
        icon = "",
      },

      ---@class YaTreeConfig.Renderers.SymlinkTarget : YaTreeRendererConfig Symbolic link rendering configuration.
      ---@field padding string The padding to use to the left of the renderer, default: `" "`.
      ---@field arrow_icon string The icon to use before the sybolic link target, default: `"➛"`.
      symlink_target = {
        padding = " ",
        arrow_icon = "➛",
      },

      ---@class YaTreeConfig.Renderers.GitStatus : YaTreeRendererConfig Git status rendering configuration.
      ---@field padding string The padding to use to the left of the renderer, default: `" "`.
      git_status = {
        padding = " ",

        ---@class YaTreeConfig.Renderers.GitStatus.Icons Git status icon rendering configuration.
        ---@field unstaged string The icon for unstaged changes, default: `""`.
        ---@field staged string The icon for staged changes, default: `"✓"`.
        ---@field unmerged string The icon for unmerged changes, default: `""`.
        ---@field renamed string The icon for a renamed file/directory, default: `"➜"`.
        ---@field untracked string The icon for untracked changes, default: `, default: `"★"`.
        ---@field deleted string The icon for a deleted file/directory, default: `""`.
        ---@field ignored string The icon for an ignored file/directory, default: `"◌"`.
        icons = {
          unstaged = "",
          staged = "✓",
          unmerged = "",
          renamed = "➜",
          untracked = "★",
          deleted = "",
          ignored = "◌",
        },
      },

      ---@class YaTreeConfig.Renderers.Diagnostics : YaTreeRendererConfig Lsp diagnostics rendering configuration.
      ---@field padding string The padding to use to the left of the renderer, default: `" "`.
      ---@field min_severity number The minimum severity necessary to show, see `|vim.diagnostic.severity|`, default: `vim.diagnostic.severity.HINT`.
      diagnostics = {
        padding = " ",
        min_severity = vim.diagnostic.severity.HINT,
      },

      ---@class YaTreeConfig.Renderers.Clipboard : YaTreeRendererConfig Clipboard rendering configuration.
      ---@field padding string The padding to use to the left of the renderer, default: `" "`.
      clipboard = {
        padding = " ",
      },
    },

    ---@alias YaTreeViewMode YaTreeCanvasMode|'"all"'

    ---@class YaTreeConfig.Mapping Key mapping configuration.
    ---@field views YaTreeViewMode[] The view modes the mapping is available for.
    ---@field mode? string|string[] The mode(s) for the keybinding.
    ---@field action? string The YaTree action to bind to.
    ---@field func? fun(node: YaTreeNode, config: YaTreeConfig) Custom function.
    ---@field command? string Lua command string.

    mappings = {
      ["q"] = { action = "close_window", views = { "tree", "search" } },
      [{ "<CR>", "o", "<2-LeftMouse>" }] = { action = "open", views = { "tree", "search" } },
      ["<C-v>"] = { action = "vsplit", views = { "tree", "search" } },
      ["<C-s>"] = { action = "split", views = { "tree", "search" } },
      ["<Tab>"] = { mode = { "n", "v" }, action = "preview", views = { "tree", "search" } },
      ["<BS>"] = { action = "close_node", views = { "tree", "search" } },
      ["z"] = { action = "close_all_nodes", views = { "tree", "search" } },
      [{ "<2-RightMouse>", "<C-]>", "." }] = { action = "cd_to", views = { "tree" } },
      ["-"] = { action = "cd_up", views = { "tree" } },
      ["P"] = { action = "parent_node", views = { "tree", "search" } },
      ["<"] = { action = "prev_sibling", views = { "tree", "search" } },
      [">"] = { action = "next_sibling", views = { "tree", "search" } },
      ["K"] = { action = "first_sibling", views = { "tree", "search" } },
      ["J"] = { action = "last_sibling", views = { "tree", "search" } },
      ["[c"] = { action = "prev_git_item", views = { "tree", "search" } },
      ["]c"] = { action = "next_git_item", views = { "tree", "search" } },
      ["I"] = { action = "toggle_ignored", views = { "tree", "search" } },
      ["H"] = { action = "toggle_filter", views = { "tree", "search" } },
      ["R"] = { action = "refresh", views = { "tree" } },
      ["/"] = { action = "live_search", views = { "tree", "search" } },
      ["f"] = { action = "search", views = { "tree", "search" } },
      ["<C-x>"] = { action = "clear_search", views = { "search" } },
      ["<C-g>"] = { action = "rescan_dir_for_git", views = { "tree" } },
      ["a"] = { action = "add", views = { "tree" } },
      ["r"] = { action = "rename", views = { "tree" } },
      ["d"] = { mode = { "n", "v" }, action = "delete", views = { "tree" } },
      ["D"] = { mode = { "n", "v" }, action = "trash", views = { "tree" } },
      ["c"] = { mode = { "n", "v" }, action = "copy_node", views = { "tree" } },
      ["x"] = { mode = { "n", "v" }, action = "cut_node", views = { "tree" } },
      ["p"] = { action = "paste_nodes", views = { "tree" } },
      ["<C-c>"] = { action = "clear_clipboard", views = { "tree" } },
      ["y"] = { action = "copy_name_to_clipboard", views = { "tree", "search" } },
      ["Y"] = { action = "copy_root_relative_path_to_clipboard", views = { "tree", "search" } },
      ["gy"] = { action = "copy_absolute_path_to_clipboard", views = { "tree", "search" } },
      ["?"] = { action = "open_help", views = { "tree", "search" } },
      ["gx"] = { action = "system_open", views = { "tree", "search" } },
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
  ---@type string[]
  local custom_filters = opts.filters and opts.filters.custom or {}
  if not vim.tbl_islist(custom_filters) then
    utils.warn("filters.custom must be an array, ignoring the configuration.")
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

  if M.config.git.yadm.enable and not M.config.git.enable then
    utils.notify("git is not enabled. Disabling 'git.yadm.enable' in the configuration")
    M.config.git.yadm.enable = false
  elseif M.config.git.yadm.enable and vim.fn.executable("yadm") == 0 then
    utils.notify("yadm not in the PATH. Disabling 'git.yadm.enable' in the configuration")
    M.config.git.yadm.enable = false
  end

  if M.config.trash.enable and vim.fn.executable("trash") == 0 then
    utils.notify("trash is not in the PATH. Disabling 'trash.enable' in the configuration")
    M.config.trash.enable = false
  end

  return M.config
end

return M
