---@class YaTreeConfig
---@field log_level "'trace'"|"'debug'"|"'info'"|"'warn'"|"'error'" the logging level used.
---@field log_to_console boolean whether to log to the console.
---@field log_to_file boolean whether to log the the log file.
---@field auto_close boolean force closing Neovim when YaTree is the last window.
---@field auto_reload_on_write boolean reloads the tree and the directory of the file changed.
---@field follow_focused_file boolean update the focused file in the tree on `BufEnter`.
---@field hijack_cursor boolean keep the cursor on the name in tree.
---@field move_buffers_from_tree_window boolean move buffers from the tree window to the last used window.
---@field replace_netrw boolean replace `netrw` windows.
---@field cwd YaTreeConfig.Cwd
---@field search YaTreeConfig.Search
---@field filters YaTreeConfig.Filters
---@field git YaTreeConfig.Git
---@field diagnostics YaTreeConfig.Diagnostics
---@field system_open YaTreeConfig.SystemOpen
---@field trash YaTreeConfig.Trash
---@field view YaTreeConfig.View
---@field renderers YaTreeConfig.Renderers
---@field mappings table<string|string[], YaTreeConfig.Mappings.Action>

---@class YaTreeConfig.Cwd
---@field follow boolean update the tree root directory on `DirChanged`.
---@field update_from_tree boolean update the tab cwd when changing root directory in the tree.

---@class YaTreeConfig.Search
---@field max_results number max number of search results.
---@field cmd string|nil override the search command to use.
---@field args string[]|fun(cmd: string, term: string, path:string, config: YaTreeConfig):string[]|nil override the search command arguments to use.

---@class YaTreeConfig.Filters
---@field enable boolean if filters are enabled, toggleable.
---@field dotfiles boolean if dotfiles should be hidden.
---@field custom string[] custom file/directory names to hide.

---@class YaTreeConfig.Git
---@field enable boolean if git should be enabled.
---@field show_ignored boolean whethet to show git ignored files in the tree, toggleable.
---@field yadm YaTreeConfig.Git.Yadm

---@class YaTreeConfig.Git.Yadm
---@field enable boolean whether yadm is enabled, requires git to be enabled.

---@class YaTreeConfig.Diagnostics
---@field enable boolean show lsp diagnostics in the tree.
---@field debounce_time number debounce time for how often `DiagnosticChanged` are processed.
---@field propagate_to_parents boolean if the diagnostic status should be propagated to parents.

---@class YaTreeConfig.SystemOpen
---@field cmd string|nil the system open command.
---@field args string[]|nil any arguments for the system open command.

---@class YaTreeConfig.Trash
---@field enable boolean the command used to trash items (must be installed), default: `trash`.
---@field require_confirm boolean confirm before `trash`ing file(s), default: `false`.

---@class YaTreeConfig.View
---@field width number widht of the tree panel, default: `40`.
---@field side "'left'"|"'right'" where the tree panel is placed, default: `left`.
---@field number boolean whether to show the number column, default: `false`.
---@field relativenumber boolean whether to show relative numbers, default: `false`.
---@field renderers YaTreeConfig.View.Renderers

---@class YaTreeConfig.View.Renderers
---@field directory YaTreeConfig.View.Renderers.DirectoryRenderer[] which renderers to use for directories.
---@field file YaTreeConfig.View.Renderers.FileRenderer[] which renderers to use for files.

---@alias YaTreeConfig.View.Renderers.DirectoryRenderer table
---@alias YaTreeConfig.View.Renderers.FileRenderer table

---@class YaTreeConfig.Renderers
---@field indentation YaTreeConfig.Renderers.Indentation
---@field icon YaTreeConfig.Renderers.Icon
---@field filter YaTreeConfig.Renderers.Filter
---@field name YaTreeConfig.Renderers.Name
---@field repository YaTreeConfig.Renderers.Repository
---@field symlink_target YaTreeConfig.Renderers.SymlinkTarget
---@field git_status YaTreeConfig.Renderers.GitStatus
---@field diagnostics YaTreeConfig.Renderers.Diagnostics
---@field clipboard YaTreeConfig.Renderers.Clipboard

---@class YaTreeRendererConfig
---@field padding string the padding to use to the left of the renderer.

---@class YaTreeConfig.Renderers.Indentation : YaTreeRendererConfig
---@field use_marker boolean whether to show indent markers, default: `false`.
---@field indent_marker string
---@field last_indent_marker string

---@class YaTreeConfig.Renderers.Icon : YaTreeRendererConfig
---@field directory YaTreeConfig.Renderers.Icon.Directory
---@field file YaTreeConfig.Renderers.Icon.File

---@class YaTreeConfig.Renderers.Icon.Directory
---@field default string the icon for closed directories.
---@field expanded string the icon for openned directories.
---@field empty string the icon for closed empty directories.
---@field empty_expanded string the icon for openned empty directories.
---@field symlink string the icon for closed symbolic link directories.
---@field symlink_expanded string the icon for openned symbolic link directories.
---@field custom table<string, string> map of directory names to custom icons.

---@class YaTreeConfig.Renderers.Icon.File
---@field default string the default icon for files.
---@field symlink string the icon for symbolic link files.

---@class YaTreeConfig.Renderers.Filter : YaTreeRendererConfig

---@class YaTreeConfig.Renderers.Name : YaTreeRendererConfig
---@field trailing_slash boolean whether to show a trailing os directory separator after directory names.
---@field use_git_status_colors boolean whether to color the name with the git status color.
---@field root_folder_format string the root folder format as per `fnamemodify`.

---@class YaTreeConfig.Renderers.Repository : YaTreeRendererConfig
---@field icon string the icon for marking the git toplevel directory.

---@class YaTreeConfig.Renderers.SymlinkTarget : YaTreeRendererConfig
---@field arrow_icon string the icon to use before the sybolic link target.

---@class YaTreeConfig.Renderers.GitStatus : YaTreeRendererConfig
---@field icons YaTreeConfig.Renderers.GitStatus.Icons

---@class YaTreeConfig.Renderers.GitStatus.Icons
---@field unstaged string the icon for unstaged changes.
---@field staged string the icon for staged changes.
---@field unmerged string the icon for unmerged changes.
---@field renamed string the icon for a renamed file/directory.
---@field untracked string the icon for untracked changes.
---@field deleted string the icon for a deleted file/directory.
---@field ignored string the icon for an ignored file/directory.

---@class YaTreeConfig.Renderers.Diagnostics : YaTreeRendererConfig
---@field min_severity number the minimum severity necessary to show, see `|vim.diagnostic.severity|`.

---@class YaTreeConfig.Renderers.Clipboard : YaTreeRendererConfig

---@class YaTreeConfig.Mappings.Action
---@field mode? string|string[] the mode(s) for the keybinding.
---@field action? string the YaTree action to bind to.
---@field func? fun(node: Node, config: YaTreeConfig) custom function.
---@field command? string lua command string.

local M = {
  ---@type YaTreeConfig
  default = {
    log_level = "warn",
    log_to_console = false,
    log_to_file = false,

    auto_close = false,
    auto_reload_on_write = true,

    follow_focused_file = false,
    hijack_cursor = false,
    move_buffers_from_tree_window = true,

    replace_netrw = true,
    cwd = {
      follow = false,
      update_from_tree = false,
    },
    search = {
      max_results = 200,
      cmd = nil,
      args = nil,
    },
    filters = {
      enable = true,
      dotfiles = true,
      custom = {},
    },
    git = {
      enable = true,
      show_ignored = true,
      yadm = {
        enable = false,
      },
    },
    diagnostics = {
      enable = true,
      debounce_time = 300,
      propagate_to_parents = true,
    },
    system_open = {
      cmd = nil,
      args = {},
    },
    trash = {
      enable = true,
      require_confirm = false,
    },
    view = {
      width = 40,
      side = "left",
      number = false,
      relativenumber = false,
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
          { "name", use_git_status_colors = true },
          { "symlink_target" },
          { "git_status" },
          { "diagnostics" },
          { "clipboard" },
        },
      },
    },
    renderers = {
      indentation = {
        padding = "",
        use_marker = false,
        indent_marker = "│",
        last_indent_marker = "└",
      },
      icon = {
        padding = "",
        directory = {
          default = "",
          expanded = "",
          empty = "",
          empty_expanded = "",
          symlink = "",
          symlink_expanded = "",
          custom = {},
        },
        file = {
          default = "",
          symlink = "",
        },
      },
      filter = {
        padding = "",
      },
      name = {
        padding = " ",
        trailing_slash = false,
        use_git_status_colors = false,
        root_folder_format = ":~",
      },
      repository = {
        padding = " ",
        icon = "",
      },
      symlink_target = {
        padding = " ",
        arrow_icon = "➛",
      },
      git_status = {
        padding = " ",
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
      diagnostics = {
        padding = " ",
        min_severity = vim.diagnostic.severity.HINT,
      },
      clipboard = {
        padding = " ",
      },
    },
    mappings = {
      ["q"] = { action = "close_window" },
      [{ "<CR>", "o", "<2-LeftMouse>" }] = { action = "open" },
      ["<C-v>"] = { action = "vsplit" },
      ["<C-s>"] = { action = "split" },
      ["<Tab>"] = { mode = { "n", "v" }, action = "preview" },
      ["<BS>"] = { action = "close_node" },
      ["z"] = { action = "close_all_nodes" },
      [{ "<2-RightMouse>", "<C-]>", "." }] = { action = "cd_to" },
      ["-"] = { action = "cd_up" },
      ["P"] = { action = "parent_node" },
      ["<"] = { action = "prev_sibling" },
      [">"] = { action = "next_sibling" },
      ["K"] = { action = "first_sibling" },
      ["J"] = { action = "last_sibling" },
      ["I"] = { action = "toggle_ignored" },
      ["H"] = { action = "toggle_filter" },
      ["R"] = { action = "refresh" },
      ["/"] = { action = "live_search" },
      ["f"] = { action = "search" },
      ["<C-x>"] = { action = "clear_search" },
      ["G"] = { action = "rescan_dir_for_git" },
      ["a"] = { action = "add" },
      ["r"] = { action = "rename" },
      ["d"] = { mode = { "n", "v" }, action = "delete" },
      ["D"] = { mode = { "n", "v" }, action = "trash" },
      ["c"] = { mode = { "n", "v" }, action = "copy_node" },
      ["x"] = { mode = { "n", "v" }, action = "cut_node" },
      ["p"] = { action = "paste_from_clipboard" },
      ["C"] = { action = "show_clipboard" },
      ["<C-c>"] = { action = "clear_clipboard" },
      ["y"] = { action = "copy_name_to_clipboard" },
      ["Y"] = { action = "copy_root_relative_path_to_clipboard" },
      ["gy"] = { action = "copy_absolute_path_to_clipboard" },
      ["?"] = { action = "toggle_help" },
      ["gx"] = { action = "system_open" },
    },
  },
}

---@param opts YaTreeConfig?
---@return YaTreeConfig
function M.setup(opts)
  local utils = require("ya-tree.utils")
  ---@type YaTreeConfig
  M.config = vim.tbl_deep_extend("force", M.default, opts or {})

  -- convert the list of custom filters to a table for quicker lookups

  M.config.filters.custom = M.default.filters.custom
  local custom_filters = (opts and opts.filters and opts.filters.custom) or {}
  for _, v in ipairs(custom_filters) do
    M.config.filters.custom[v] = true
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

  return M.config
end

return M
