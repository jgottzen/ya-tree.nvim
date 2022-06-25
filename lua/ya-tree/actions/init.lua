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
---| "goto_path_in_tree"
---| "copy_node"
---| "cut_node"
---| "paste_nodes"
---| "clear_clipboard"
---| "copy_name_to_clipboard"
---| "copy_root_relative_path_to_clipboard"
---| "copy_absolute_path_to_clipboard"
---| "search_interactively"
---| "search_once"
---| "goto_node_in_tree"
---| "close_search"
---| "show_last_search"
---| "close_window"
---| "close_node"
---| "close_all_nodes"
---| "expand_all_nodes"
---| "cd_to"
---| "cd_up"
---| "toggle_ignored"
---| "toggle_filter"
---| "refresh_tree"
---| "rescan_dir_for_git"
---| "toggle_git_status"
---| "toggle_buffers"
---| "focus_parent"
---| "focus_prev_sibling"
---| "focus_next_sibling"
---| "focus_first_sibling"
---| "focus_last_sibling"
---| "focus_prev_git_item"
---| "focus_next_git_item"
---| "open_help"

---@alias YaTreeActionMode "n" | "v" | "V"

---@class YaTreeAction
---@field fn fun(node: YaTreeNode)
---@field desc string
---@field views YaTreeCanvasViewMode[]
---@field modes YaTreeActionMode[]

---@param fn fun(node: YaTreeNode)
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
  open = create_action(files.open, "Open file or directory", { "tree", "search", "buffers", "git_status" }, { "n", "v" }),
  vsplit = create_action(files.vsplit, "Open file in a vertical split", { "tree", "search", "git_status" }, { "n" }),
  split = create_action(files.split, "Open file in a split", { "tree", "search", "git_status" }, { "n" }),
  tabnew = create_action(files.tabnew, "Open file in a new tabpage", { "tree", "search", "git_status" }, { "n" }),
  preview = create_action(files.preview, "Open file (keep cursor in tree)", { "tree", "search", "git_status" }, { "n" }),
  add = create_action(files.add, "Add file or directory", { "tree" }, { "n" }),
  rename = create_action(files.rename, "Rename file or directory", { "tree" }, { "n" }),
  delete = create_action(files.delete, "Delete files and directories", { "tree" }, { "n", "v" }),
  trash = create_action(files.trash, "Trash files and directories", { "tree" }, { "n", "v" }),
  system_open = create_action(
    files.system_open,
    "Open the node with the default system application",
    { "tree", "search", "buffers", "git_status" },
    { "n" }
  ),
  goto_path_in_tree = create_action(
    files.goto_path_in_tree,
    "Go to entered path in tree",
    { "tree", "search", "buffers", "git_status" },
    { "n" }
  ),

  copy_node = create_action(clipboard.copy_node, "Select files and directories for copy", { "tree" }, { "n", "v" }),
  cut_node = create_action(clipboard.cut_node, "Select files and directories for cut", { "tree" }, { "n", "v" }),
  paste_nodes = create_action(clipboard.paste_nodes, "Paste files and directories", { "tree" }, { "n" }),
  clear_clipboard = create_action(clipboard.clear_clipboard, "Clear selected files and directories", { "tree" }, { "n" }),
  copy_name_to_clipboard = create_action(
    clipboard.copy_name_to_clipboard,
    "Copy node name to system clipboard",
    { "tree", "search", "buffers", "git_status" },
    { "n" }
  ),
  copy_root_relative_path_to_clipboard = create_action(
    clipboard.copy_root_relative_path_to_clipboard,
    "Copy root-relative path to system clipboard",
    { "tree", "search", "buffers", "git_status" },
    { "n" }
  ),
  copy_absolute_path_to_clipboard = create_action(
    clipboard.copy_absolute_path_to_clipboard,
    "Copy absolute path to system clipboard",
    { "tree", "search", "buffers", "git_status" },
    { "n" }
  ),

  search_interactively = create_action(search.search_interactively, "Search as you type", { "tree", "search" }, { "n" }),
  search_once = create_action(search.search_once, "Search", { "tree", "search" }, { "n" }),
  goto_node_in_tree = create_action(
    lib.goto_node_in_tree,
    "Close view and go to node in tree view",
    { "search", "buffers", "git_status" },
    { "n" }
  ),
  close_search = create_action(lib.close_search, "Close the search result", { "search" }, { "n" }),
  show_last_search = create_action(lib.show_last_search, "Show last search result", { "tree" }, { "n" }),

  close_window = create_action(lib.close_window, "Close the tree window", { "tree", "search", "buffers", "git_status" }, { "n" }),
  close_node = create_action(lib.close_node, "Close directory", { "tree", "search", "buffers", "git_status" }, { "n" }),
  close_all_nodes = create_action(lib.close_all_nodes, "Close all directories", { "tree", "search", "buffers", "git_status" }, { "n" }),
  expand_all_nodes = create_action(
    lib.expand_all_nodes,
    "Recursively expand all directories",
    { "tree", "search", "buffers", "git_status" },
    { "n" }
  ),
  cd_to = create_action(lib.cd_to, "Set tree root to directory", { "tree", "search", "buffers", "git_status" }, { "n" }),
  cd_up = create_action(lib.cd_up, "Set tree root one level up", { "tree" }, { "n" }),
  toggle_ignored = create_action(
    lib.toggle_ignored,
    "Toggle git ignored files and directories",
    { "tree", "search", "buffers", "git_status" },
    { "n" }
  ),
  toggle_filter = create_action(
    lib.toggle_filter,
    "Toggle filtered files and directories",
    { "tree", "search", "buffers", "git_status" },
    { "n" }
  ),
  refresh_tree = create_action(lib.refresh_tree, "Refresh the tree", { "tree", "search", "buffers", "git_status" }, { "n" }),
  rescan_dir_for_git = create_action(lib.rescan_dir_for_git, "Rescan directory for git repo", { "tree" }, { "n" }),

  toggle_git_status = create_action(lib.toggle_git_status, "Open or close the current git status view", { "tree", "git_status" }, { "n" }),
  toggle_buffers = create_action(lib.toggle_buffers, "Open or close the current buffers view", { "tree", "buffers" }, { "n" }),

  focus_parent = create_action(ui.focus_parent, "Go to parent directory", { "tree", "search", "buffers", "git_status" }, { "n" }),
  focus_prev_sibling = create_action(
    ui.focus_prev_sibling,
    "Go to previous sibling node",
    { "tree", "search", "buffers", "git_status" },
    { "n" }
  ),
  focus_next_sibling = create_action(
    ui.focus_next_sibling,
    "Go to next sibling node",
    { "tree", "search", "buffers", "git_status" },
    { "n" }
  ),
  focus_first_sibling = create_action(
    ui.focus_first_sibling,
    "Go to first sibling node",
    { "tree", "search", "buffers", "git_status" },
    { "n" }
  ),
  focus_last_sibling = create_action(
    ui.focus_last_sibling,
    "Go to last sibling node",
    { "tree", "search", "buffers", "git_status" },
    { "n" }
  ),
  focus_prev_git_item = create_action(
    ui.focus_prev_git_item,
    "Go to previous git item",
    { "tree", "search", "buffers", "git_status" },
    { "n" }
  ),
  focus_next_git_item = create_action(
    ui.focus_next_git_item,
    "Go to next git item",
    { "tree", "search", "buffers", "git_status" },
    { "n" }
  ),
  open_help = create_action(ui.open_help, "Open keybindings help", { "tree", "search", "buffers", "git_status" }, { "n" }),
}

---@param mapping YaTreeActionMapping
---@return function? handler
local function create_keymap_function(mapping)
  ---@type fun(node: YaTreeNode)
  local fn
  if mapping.action then
    local action = actions[mapping.action]
    if action and action.fn then
      fn = action.fn
    end
  elseif mapping.fn then
    fn = mapping.fn
  else
    log.error("cannot create keymap function for mappings %s", mapping)
    return nil
  end

  return function()
    if mapping.views[ui.get_view_mode()] then
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

---@param views_list YaTreeCanvasViewMode[]
---@return table<YaTreeCanvasViewMode, boolean>
local function create_views_map(views_list)
  ---@type table<YaTreeCanvasViewMode, boolean>
  local views = {}
  for _, view in ipairs(views_list) do
    views[view] = true
  end

  return views
end

---@class YaTreeActionMapping
---@field views table<YaTreeCanvasViewMode, boolean>
---@field mode YaTreeActionMode
---@field key string
---@field desc string
---@field action? YaTreeActionName
---@field fn? fun(node: YaTreeNode)

---@param mappings table<string, YaTreeActionName|YaTreeConfig.CustomMapping>
---@return YaTreeActionMapping[]
local function validate_and_create_mappings(mappings)
  ---@type YaTreeActionMapping[]
  local action_mappings = {}

  for key, mapping in pairs(mappings) do
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
            views = create_views_map(action.views),
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
            views = create_views_map(mapping.views),
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
