local void = require("plenary.async").void

local lib = require("ya-tree.lib")
local ui = require("ya-tree.ui")
local clipboard = require("ya-tree.actions.clipboard")
local files = require("ya-tree.actions.files")
local search = require("ya-tree.actions.search")
local utils = require("ya-tree.utils")
local log = require("ya-tree.log")

local M = {}

---@alias YaTreeActionName
---| "open"
---| "vsplit"
---| "split"
---| "tabnew"
---| "preview"
---| "add"
---| "rename"
---| "delete"
---| "trash"
---| "system_open"
---| "copy_node"
---| "cut_node"
---| "paste_nodes"
---| "clear_clipboard"
---| "copy_name_to_clipboard"
---| "copy_root_relative_path_to_clipboard"
---| "copy_absolute_path_to_clipboard"
---| "search_interactively"
---| "search_once"
---| "search_for_path_in_tree"
---| "goto_node_in_tree"
---| "close_search"
---| "show_last_search"
---| "close_window"
---| "close_node"
---| "close_all_nodes"
---| "close_all_child_nodes"
---| "expand_all_nodes"
---| "expand_all_child_nodes"
---| "cd_to"
---| "cd_up"
---| "toggle_ignored"
---| "toggle_filter"
---| "refresh_tree"
---| "rescan_dir_for_git"
---| "toggle_git_view"
---| "toggle_buffers_view"
---| "focus_parent"
---| "focus_prev_sibling"
---| "focus_next_sibling"
---| "focus_first_sibling"
---| "focus_last_sibling"
---| "focus_prev_git_item"
---| "focus_next_git_item"
---| "focus_prev_diagnostic_item"
---| "focus_next_diagnostic_item"
---| "open_help"
---| "show_node_info"

---@alias YaTreeActionMode "n" | "v" | "V"

---@class YaTreeAction
---@field fn async fun(node: YaTreeNode)
---@field desc string
---@field views YaTreeCanvasViewMode[]
---@field modes YaTreeActionMode[]

---@param fn async fun(node: YaTreeNode)
---@param desc string
---@param views YaTreeCanvasViewMode[]
---@param modes YaTreeActionMode[]
---@return YaTreeAction
local function create_action(fn, desc, views, modes)
  return {
    fn = fn,
    desc = desc,
    views = views,
    modes = modes,
  }
end

---@type table<YaTreeActionName, YaTreeAction>
local actions = {
  open = create_action(files.open, "Open file or directory", { "files", "search", "buffers", "git" }, { "n", "v" }),
  vsplit = create_action(files.vsplit, "Open file in a vertical split", { "files", "search", "git" }, { "n" }),
  split = create_action(files.split, "Open file in a split", { "files", "search", "git" }, { "n" }),
  tabnew = create_action(files.tabnew, "Open file in a new tabpage", { "files", "search", "git" }, { "n" }),
  preview = create_action(files.preview, "Open file (keep cursor in tree)", { "files", "search", "git" }, { "n" }),
  add = create_action(files.add, "Add file or directory", { "files" }, { "n" }),
  rename = create_action(files.rename, "Rename file or directory", { "files" }, { "n" }),
  delete = create_action(files.delete, "Delete files and directories", { "files" }, { "n", "v" }),
  trash = create_action(files.trash, "Trash files and directories", { "files" }, { "n", "v" }),
  system_open = create_action(
    files.system_open,
    "Open the node with the default system application",
    { "files", "search", "buffers", "git" },
    { "n" }
  ),

  copy_node = create_action(clipboard.copy_node, "Select files and directories for copy", { "files" }, { "n", "v" }),
  cut_node = create_action(clipboard.cut_node, "Select files and directories for cut", { "files" }, { "n", "v" }),
  paste_nodes = create_action(clipboard.paste_nodes, "Paste files and directories", { "files" }, { "n" }),
  clear_clipboard = create_action(clipboard.clear_clipboard, "Clear selected files and directories", { "files" }, { "n" }),
  copy_name_to_clipboard = create_action(
    clipboard.copy_name_to_clipboard,
    "Copy node name to system clipboard",
    { "files", "search", "buffers", "git" },
    { "n" }
  ),
  copy_root_relative_path_to_clipboard = create_action(
    clipboard.copy_root_relative_path_to_clipboard,
    "Copy root-relative path to system clipboard",
    { "files", "search", "buffers", "git" },
    { "n" }
  ),
  copy_absolute_path_to_clipboard = create_action(
    clipboard.copy_absolute_path_to_clipboard,
    "Copy absolute path to system clipboard",
    { "files", "search", "buffers", "git" },
    { "n" }
  ),

  search_interactively = create_action(search.search_interactively, "Search as you type", { "files", "search" }, { "n" }),
  search_once = create_action(search.search_once, "Search", { "files", "search" }, { "n" }),
  search_for_path_in_tree = create_action(
    search.search_for_path_in_tree,
    "Go to entered path in tree",
    { "files", "search", "buffers", "git" },
    { "n" }
  ),
  close_search = create_action(lib.close_search, "Close the search result", { "search" }, { "n" }),
  show_last_search = create_action(lib.show_last_search, "Show last search result", { "files" }, { "n" }),

  close_window = create_action(lib.close_window, "Close the tree window", { "files", "search", "buffers", "git" }, { "n" }),
  close_node = create_action(lib.close_node, "Close directory", { "files", "search", "buffers", "git" }, { "n" }),
  close_all_nodes = create_action(lib.close_all_nodes, "Close all directories", { "files", "search", "buffers", "git" }, { "n" }),
  close_all_child_nodes = create_action(
    lib.close_all_child_nodes,
    "Close all child directories",
    { "files", "search", "buffers", "git" },
    { "n" }
  ),
  expand_all_nodes = create_action(
    lib.expand_all_nodes,
    "Recursively expand all directories",
    { "files", "search", "buffers", "git" },
    { "n" }
  ),
  expand_all_child_nodes = create_action(
    lib.expand_all_child_nodes,
    "Recursively expand all child directories",
    { "files", "search", "buffers", "git" },
    { "n" }
  ),
  goto_node_in_tree = create_action(
    lib.goto_node_in_tree,
    "Close view and go to node in tree view",
    { "search", "buffers", "git" },
    { "n" }
  ),
  cd_to = create_action(lib.cd_to, "Set tree root to directory", { "files", "search", "buffers", "git" }, { "n" }),
  cd_up = create_action(lib.cd_up, "Set tree root one level up", { "files" }, { "n" }),
  toggle_ignored = create_action(
    lib.toggle_ignored,
    "Toggle git ignored files and directories",
    { "files", "search", "buffers", "git" },
    { "n" }
  ),
  toggle_filter = create_action(
    lib.toggle_filter,
    "Toggle filtered files and directories",
    { "files", "search", "buffers", "git" },
    { "n" }
  ),
  refresh_tree = create_action(lib.refresh_tree, "Refresh the tree", { "files", "search", "buffers", "git" }, { "n" }),
  rescan_dir_for_git = create_action(lib.rescan_dir_for_git, "Rescan directory for git repo", { "files" }, { "n" }),

  toggle_git_view = create_action(lib.toggle_git_view, "Open or close the current git status view", { "files", "git" }, { "n" }),
  toggle_buffers_view = create_action(lib.toggle_buffers_view, "Open or close the current buffers view", { "files", "buffers" }, { "n" }),

  focus_parent = create_action(ui.focus_parent, "Go to parent directory", { "files", "search", "buffers", "git" }, { "n" }),
  focus_prev_sibling = create_action(
    ui.focus_prev_sibling,
    "Go to previous sibling node",
    { "files", "search", "buffers", "git" },
    { "n" }
  ),
  focus_next_sibling = create_action(
    ui.focus_next_sibling,
    "Go to next sibling node",
    { "files", "search", "buffers", "git" },
    { "n" }
  ),
  focus_first_sibling = create_action(
    ui.focus_first_sibling,
    "Go to first sibling node",
    { "files", "search", "buffers", "git" },
    { "n" }
  ),
  focus_last_sibling = create_action(
    ui.focus_last_sibling,
    "Go to last sibling node",
    { "files", "search", "buffers", "git" },
    { "n" }
  ),
  focus_prev_git_item = create_action(
    ui.focus_prev_git_item,
    "Go to previous git item",
    { "files", "search", "buffers", "git" },
    { "n" }
  ),
  focus_next_git_item = create_action(
    ui.focus_next_git_item,
    "Go to next git item",
    { "files", "search", "buffers", "git" },
    { "n" }
  ),
  focus_prev_diagnostic_item = create_action(
    ui.focus_prev_diagnostic_item,
    "Go to the previous diagnostic item",
    { "files", "search", "buffers", "git" },
    { "n" }
  ),
  focus_next_diagnostic_item = create_action(
    ui.focus_next_diagnostic_item,
    "Go to the next diagnostic item",
    { "files", "search", "buffers", "git" },
    { "n" }
  ),
  open_help = create_action(ui.open_help, "Open keybindings help", { "files", "search", "buffers", "git" }, { "n" }),
  show_node_info = create_action(files.show_node_info, "Show node info in popup", { "files", "search", "buffers", "git" }, { "n" }),
}

---@param mapping YaTreeActionMapping
---@return function|nil handler
local function create_keymap_function(mapping)
  ---@type fun(node: YaTreeNode)
  local fn
  if mapping.action then
    local action = actions[mapping.action]
    if action and action.fn then
      fn = void(action.fn)
    else
      log.error("action %q has no mapping", mapping.action)
      return nil
    end
  elseif mapping.fn then
    fn = void(mapping.fn)
  else
    log.error("cannot create keymap function for mappings %s", mapping)
    return nil
  end

  return function()
    if vim.tbl_contains(mapping.views, ui.get_view_mode()) then
      fn(ui.get_current_node())
    end
  end
end

---@param bufnr number
function M.apply_mappings(bufnr)
  for _, mapping in pairs(M.mappings) do
    local opts = { remap = false, silent = true, nowait = true, buffer = bufnr, desc = mapping.desc }
    local rhs = create_keymap_function(mapping)

    if not rhs or not pcall(vim.keymap.set, mapping.mode, mapping.key, rhs, opts) then
      utils.warn(string.format("Cannot construct mapping for key %q!", mapping.key))
    end
  end
end

---@class YaTreeActionMapping
---@field views YaTreeCanvasViewMode[]
---@field mode YaTreeActionMode
---@field key string
---@field desc string
---@field action? YaTreeActionName
---@field fn? async fun(node: YaTreeNode)

---@param mappings YaTreeConfig.Mappings
---@return YaTreeActionMapping[]
local function validate_and_create_mappings(mappings)
  ---@type YaTreeActionMapping[]
  local action_mappings = {}

  for key, mapping in pairs(mappings.list) do
    if type(mapping) == "string" then
      ---@type YaTreeActionName
      local name = mapping
      if #name == 0 then
        log.debug("key %s is disabled by user config", key)
      elseif not actions[name] then
        log.error("Key %s is mapped to 'action' %q, which does not exist, mapping ignored!", vim.inspect(key), name)
        utils.warn(string.format("Key %s is mapped to 'action' %q, which does not exist, mapping ignored!", vim.inspect(key), name))
      else
        local action = actions[name]
        for _, mode in ipairs(action.modes) do
          action_mappings[#action_mappings + 1] = {
            views = action.views,
            mode = mode,
            key = key,
            desc = action.desc,
            action = name,
          }
        end
      end
    elseif type(mapping) == "table" then
      ---@cast mapping YaTreeConfig.CustomMapping
      local fn = mapping.fn
      if type(fn) == "function" then
        for _, mode in ipairs(mapping.modes) do
          action_mappings[#action_mappings + 1] = {
            views = mapping.views,
            mode = mode,
            key = key,
            desc = mapping.desc or "User '<function>'",
            fn = fn,
          }
        end
      else
        utils.warn(string.format("Key %s is mapped to 'fn' %s, which is not a function, mapping ignored!", vim.inspect(key), fn))
      end
    end
  end

  return action_mappings
end

function M.setup()
  M.mappings = validate_and_create_mappings(require("ya-tree.config").config.mappings)
end

return M
