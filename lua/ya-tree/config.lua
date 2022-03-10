---@class YaTreeConfig
---@field log_level string
---@field log_to_console boolean
---@field log_to_file boolean
---@field auto_close boolean
---@field auto_reload_on_write boolean
---@field follow_focused_file boolean
---@field hijack_cursor boolean
---@field replace_netrw boolean
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
---@field follow boolean
---@field update_from_tree boolean

---@class YaTreeConfig.Search
---@field max_results number
---@field cmd string|nil
---@field args string[]|nil

---@class YaTreeConfig.Filters
---@field enable boolean
---@field dotfiles boolean
---@field custom string[]

---@class YaTreeConfig.Git
---@field enable boolean
---@field show_ignored boolean
---@field yadm YaTreeConfig.Git.Yadm

---@class YaTreeConfig.Git.Yadm
---@field enable boolean

---@class YaTreeConfig.Diagnostics
---@field enable boolean
---@field debounce_time number
---@field propagate_to_parents boolean

---@class YaTreeConfig.SystemOpen
---@field cmd string
---@field args string[]

---@class YaTreeConfig.Trash
---@field enable boolean
---@field require_confirm boolean

---@class YaTreeConfig.View
---@field width number
---@field side string
---@field number boolean
---@field relativenumber boolean
---@field renderers YaTreeConfig.View.Renderers

---@class YaTreeConfig.View.Renderers
---@field directory YaTreeConfig.View.Renderers.DirectoryRenderer[]
---@field file YaTreeConfig.View.Renderers.FileRenderer[]

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
---@field padding string

---@class YaTreeConfig.Renderers.Indentation : YaTreeRendererConfig
---@field use_marker boolean
---@field indent_marker string
---@field last_indent_marker string

---@class YaTreeConfig.Renderers.Icon : YaTreeRendererConfig
---@field directory YaTreeConfig.Renderers.Icon.Directory
---@field file YaTreeConfig.Renderers.Icon.File

---@class YaTreeConfig.Renderers.Icon.Directory
---@field default string
---@field expanded string
---@field empty string
---@field empty_expanded string
---@field symlink string
---@field symlink_expanded string
---@field custom table<string, string>

---@class YaTreeConfig.Renderers.Icon.File
---@field default string
---@field symlink string

---@class YaTreeConfig.Renderers.Filter : YaTreeRendererConfig

---@class YaTreeConfig.Renderers.Name : YaTreeRendererConfig
---@field trailing_slash boolean
---@field use_git_status_colors boolean
---@field root_folder_format string

---@class YaTreeConfig.Renderers.Repository : YaTreeRendererConfig
---@field icon string

---@class YaTreeConfig.Renderers.SymlinkTarget : YaTreeRendererConfig
---@field arrow_icon string

---@class YaTreeConfig.Renderers.GitStatus : YaTreeRendererConfig
---@field icons YaTreeConfig.Renderers.GitStatus.Icons

---@class YaTreeConfig.Renderers.GitStatus.Icons
---@field unstaged string
---@field staged string
---@field unmerged string
---@field renamed string
---@field untracked string
---@field deleted string
---@field ignored string

---@class YaTreeConfig.Renderers.Diagnostics : YaTreeRendererConfig
---@field min_severity number

---@class YaTreeConfig.Renderers.Clipboard : YaTreeRendererConfig

---@class YaTreeConfig.Mappings.Action
---@field mode string|string[]
---@field action? string
---@field func? function(node: Node, config: YaTreeConfig)
---@field command? string

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
      ["<Tab>"] = { action = "preview" },
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
  ---@type table<string, boolean>
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
