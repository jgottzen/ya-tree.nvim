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
---| "close_tree"
---| "close_node"
---| "close_all_nodes"
---| "cd_to"
---| "cd_up"
---| "toggle_ignored"
---| "toggle_filter"
---| "refresh_tree"
---| "rescan_dir_for_git"
---| "toggle_buffers"
---| "focus_parent"
---| "focus_prev_sibling"
---| "focus_next_sibling"
---| "focus_first_sibling"
---| "focus_last_sibling"
---| "focus_prev_git_item"
---| "focus_next_git_item"
---| "open_help"

---@class YaTreeAction
---@field fun fun(node: YaTreeNode)
---@field desc string
---@field views YaTreeCanvasDisplayMode[]
---@field modes string[]

---@type table<YaTreeActionName, YaTreeAction>
local actions = {
  open = { fun = files.open, desc = "Open file or directory", views = { "tree", "search", "buffers" }, modes = { "n", "v" } },
  vsplit = { fun = files.vsplit, desc = "Open file in a vertical split", views = { "tree", "search" }, modes = { "n" } },
  split = { fun = files.split, desc = "Open file in a split", views = { "tree", "search" }, modes = { "n" } },
  tabnew = { fun = files.tabnew, desc = "Open file in a new tabpage", views = { "tree", "search" }, modes = { "n" } },
  preview = { fun = files.preview, desc = "Open files (keep cursor in tree)", views = { "tree", "search", "buffers" }, modes = { "n" } },
  add = { fun = files.add, desc = "Add file or directory", views = { "tree" }, modes = { "n" } },
  rename = { fun = files.rename, desc = "Rename file or directory", views = { "tree" }, modes = { "n" } },
  delete = { fun = files.delete, desc = "Delete files and directories", views = { "tree" }, modes = { "n", "v" } },
  trash = { fun = files.trash, desc = "Trash files and directories", views = { "tree" }, modes = { "n", "v" } },
  system_open = {
    fun = files.system_open,
    desc = "Open the node with the default system application",
    views = { "tree", "search", "buffers" },
    modes = { "n" },
  },
  goto_path_in_tree = { fun = files.goto_path_in_tree, desc = "Go to entered path in tree", views = { "tree" }, modes = { "n" } },

  copy_node = { fun = clipboard.copy_node, desc = "Select files and directories for copy", views = { "tree" }, modes = { "n", "v" } },
  cut_node = { fun = clipboard.cut_node, desc = "Select files and directories for cut", views = { "tree" }, modes = { "n", "v" } },
  paste_nodes = { fun = clipboard.paste_nodes, desc = "Paste files and directories", views = { "tree" }, modes = { "n" } },
  clear_clipboard = { fun = clipboard.clear_clipboard, desc = "Clear selected files and directories", views = { "tree" }, modes = { "n" } },
  copy_name_to_clipboard = {
    fun = clipboard.copy_name_to_clipboard,
    desc = "Copy node name to system clipboard",
    views = { "tree", "search", "buffers" },
    modes = { "n" },
  },
  copy_root_relative_path_to_clipboard = {
    fun = clipboard.copy_root_relative_path_to_clipboard,
    desc = "Copy root-relative path to system clipboard",
    views = { "tree", "search", "buffers" },
    modes = { "n" },
  },
  copy_absolute_path_to_clipboard = {
    fun = clipboard.copy_absolute_path_to_clipboard,
    desc = "Copy absolute path to system clipboard",
    views = { "tree", "search", "buffers" },
    modes = { "n" },
  },

  search_interactively = { fun = search.search_interactively, desc = "Search as you type", views = { "tree", "search" }, modes = { "n" } },
  search_once = { fun = search.search_once, desc = "Search", views = { "tree", "search" }, modes = { "n" } },
  goto_node_in_tree = {
    fun = lib.goto_node_in_tree,
    desc = "Close view and go to node in tree view",
    views = { "search", "buffers" },
    modes = { "n" },
  },
  close_search = { fun = lib.close_search, desc = "Close the search result", views = { "search" }, modes = { "n" } },
  show_last_search = { fun = lib.show_last_search, desc = "Show last search result", views = { "tree" }, modes = { "n" } },

  close_tree = { fun = lib.close_tree, desc = "Close the tree window", views = { "tree", "search", "buffers" }, modes = { "n" } },
  close_node = { fun = lib.close_node, desc = "Close directory", views = { "tree", "search", "buffers" }, modes = { "n" } },
  close_all_nodes = {
    fun = lib.close_all_nodes,
    desc = "Close all directories",
    views = { "tree", "search", "buffers" },
    modes = { "n" },
  },
  cd_to = { fun = lib.cd_to, desc = "Set tree root to directory", views = { "tree", "search", "buffers" }, modes = { "n" } },
  cd_up = { fun = lib.cd_up, desc = "Set tree root one level up", views = { "tree" }, modes = { "n" } },
  toggle_ignored = {
    fun = lib.toggle_ignored,
    desc = "Toggle git ignored files and directories",
    views = { "tree", "search", "buffers" },
    modes = { "n" },
  },
  toggle_filter = {
    fun = lib.toggle_filter,
    desc = "Toggle filtered files and directories",
    views = { "tree", "search", "buffers" },
    modes = { "n" },
  },
  refresh_tree = { fun = lib.refresh_tree, desc = "Refresh the tree", views = { "tree", "search", "buffers" }, modes = { "n" } },
  rescan_dir_for_git = { fun = lib.rescan_dir_for_git, desc = "Rescan directory for git repo", views = { "tree" }, modes = { "n" } },
  toggle_buffers = {
    fun = lib.toggle_buffers,
    desc = "Show the current buffers in a tree view",
    views = { "tree", "buffers" },
    modes = { "n" },
  },

  focus_parent = { fun = ui.focus_parent, desc = "Go to parent directory", views = { "tree", "search", "buffers" }, modes = { "n" } },
  focus_prev_sibling = {
    fun = ui.focus_prev_sibling,
    desc = "Go to previous sibling node",
    views = { "tree", "search", "buffers" },
    modes = { "n" },
  },
  focus_next_sibling = {
    fun = ui.focus_next_sibling,
    desc = "Go to next sibling node",
    views = { "tree", "search", "buffers" },
    modes = { "n" },
  },
  focus_first_sibling = {
    fun = ui.focus_first_sibling,
    desc = "Go to first sibling node",
    views = { "tree", "search", "buffers" },
    modes = { "n" },
  },
  focus_last_sibling = {
    fun = ui.focus_last_sibling,
    desc = "Go to last sibling node",
    views = { "tree", "search", "buffers" },
    modes = { "n" },
  },
  focus_prev_git_item = {
    fun = ui.focus_prev_git_item,
    desc = "Go to previous git item",
    views = { "tree", "search", "buffers" },
    modes = { "n" },
  },
  focus_next_git_item = {
    fun = ui.focus_next_git_item,
    desc = "Go to next git item",
    views = { "tree", "search", "buffers" },
    modes = { "n" },
  },
  open_help = { fun = ui.open_help, desc = "Open keybindings help", views = { "tree", "search", "buffers" }, modes = { "n" } },
}

---@param mapping YaTreeActionMapping
---@return function handler
local function create_keymap_function(mapping)
  ---@type fun(node: YaTreeNode)
  local fun
  if mapping.action then
    local action = actions[mapping.action]
    if action and action.fun then
      fun = action.fun
    end
  elseif mapping.func then
    fun = mapping.func
  else
    log.error("cannot create keymap function for mappings %s", mapping)
    return nil
  end

  return function()
    if mapping.views[ui.get_current_view_mode()] then
      fun(ui.get_current_node())
    end
  end
end

---@param bufnr number
function M.apply_mappings(bufnr)
  for _, mapping in pairs(M.mappings) do
    local opts = { remap = false, silent = true, nowait = true, buffer = bufnr, desc = mapping.desc }
    local rhs = create_keymap_function(mapping)

    if not rhs or not pcall(vim.keymap.set, mapping.mode, mapping.key, rhs, opts) then
      utils.warn(string.format("cannot construct mapping for key %q", mapping.key))
    end
  end
end

---@param views_array YaTreeCanvasDisplayMode[]
---@return table<YaTreeCanvasDisplayMode, boolean>
local function create_views_map(views_array)
  ---@type table<YaTreeCanvasDisplayMode, boolean>
  local views = {}
  for _, view in ipairs(views_array) do
    views[view] = true
  end

  return views
end

---@class YaTreeActionMapping
---@field views table<YaTreeCanvasDisplayMode, boolean>
---@field mode string
---@field key string
---@field desc string
---@field action? YaTreeActionName
---@field func? fun(node: YaTreeNode)

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
        utils.warn(string.format("key %s is mapped to 'action' %q, which does not exist, mapping ignored!", vim.inspect(key), name))
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
      local func = mapping.func
      if type(func) == "function" then
        for _, mode in ipairs(mapping.modes) do
          action_mappings[#action_mappings + 1] = {
            views = create_views_map(mapping.views),
            mode = mode,
            key = key,
            desc = mapping.desc or "User '<function>'",
            func = func,
          }
        end
      elseif func then
        utils.warn(string.format("key %s is mapped to 'func' %s, which is not a function, mapping ignored!", vim.inspect(key), func))
      end
    end
  end

  return action_mappings
end

function M.setup()
  M.mappings = validate_and_create_mappings(require("ya-tree.config").config.mappings)
end

return M
