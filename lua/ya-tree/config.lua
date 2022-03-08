local M = {
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
      command = nil,
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

function M.setup(opts)
  local utils = require("ya-tree.utils")
  M.config = vim.tbl_deep_extend("keep", opts or {}, M.default)

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
