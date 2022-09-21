local void = require("plenary.async").void

local lib = require("ya-tree.lib")
local ui = require("ya-tree.ui")
local help = require("ya-tree.ui.help")
local clipboard = require("ya-tree.actions.clipboard")
local files = require("ya-tree.actions.files")
local nodes = require("ya-tree.actions.nodes")
local popups = require("ya-tree.actions.popups")
local search = require("ya-tree.actions.search")
local Trees = require("ya-tree.trees")
local utils = require("ya-tree.utils")
local log = require("ya-tree.log")("actions")

local api = vim.api

local M = {}

---@alias Yat.Action.Name
---| "open"
---| "vsplit"
---| "split"
---| "tabnew"
---| "preview"
---| "preview_and_focus"
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
---| "toggle_git_tree"
---| "toggle_buffers_tree"
---| "show_file_tree"
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

---@alias Yat.Action.Mode "n" | "v" | "V"

---@class Yat.Action
---@field fn async fun(tree: Yat.Tree, node: Yat.Node)
---@field desc string
---@field tree_types Yat.Trees.Type[]|string[]
---@field modes Yat.Action.Mode[]

---@param fn async fun(tree: Yat.Tree, node: Yat.Node)
---@param desc string
---@param tree_types Yat.Trees.Type[]|string[]
---@param modes Yat.Action.Mode[]
---@return Yat.Action
local function create_action(fn, desc, tree_types, modes)
  return {
    fn = fn,
    desc = desc,
    tree_types = tree_types,
    modes = modes,
  }
end

---@type table<Yat.Action.Name, Yat.Action>
local actions = {
  open = create_action(files.open, "Open file or directory", { "files", "search", "buffers", "git" }, { "n", "v" }),
  vsplit = create_action(files.vsplit, "Open file in a vertical split", { "files", "search", "git" }, { "n" }),
  split = create_action(files.split, "Open file in a split", { "files", "search", "git" }, { "n" }),
  tabnew = create_action(files.tabnew, "Open file in a new tabpage", { "files", "search", "git" }, { "n" }),
  preview = create_action(files.preview, "Open file (keep cursor in tree)", { "files", "search", "git" }, { "n" }),
  preview_and_focus = create_action(files.preview_and_focus, "Open file (keep cursor in tree)", { "files", "search", "git" }, { "n" }),
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

  close_node = create_action(nodes.close_node, "Close directory", { "files", "search", "buffers", "git" }, { "n" }),
  close_all_nodes = create_action(nodes.close_all_nodes, "Close all directories", { "files", "search", "buffers", "git" }, { "n" }),
  close_all_child_nodes = create_action(
    nodes.close_all_child_nodes,
    "Close all child directories",
    { "files", "search", "buffers", "git" },
    { "n" }
  ),
  expand_all_nodes = create_action(
    nodes.expand_all_nodes,
    "Recursively expand all directories",
    { "files", "search", "buffers", "git" },
    { "n" }
  ),
  expand_all_child_nodes = create_action(
    nodes.expand_all_child_nodes,
    "Recursively expand all child directories",
    { "files", "search", "buffers", "git" },
    { "n" }
  ),
  goto_node_in_tree = create_action(
    nodes.goto_node_in_tree,
    "Close current tree and go to node in the file tree",
    { "search", "buffers", "git" },
    { "n" }
  ),

  show_node_info = create_action(popups.show_node_info, "Show node info in popup", { "files", "search", "buffers", "git" }, { "n" }),

  search_interactively = create_action(search.search_interactively, "Search as you type", { "files", "search" }, { "n" }),
  search_once = create_action(search.search_once, "Search", { "files", "search" }, { "n" }),
  search_for_path_in_tree = create_action(
    search.search_for_path_in_tree,
    "Go to entered path in tree",
    { "files", "search", "buffers", "git" },
    { "n" }
  ),
  show_last_search = create_action(lib.show_last_search, "Show last search result", { "files" }, { "n" }),

  close_window = create_action(lib.close_window, "Close the tree window", { "files", "search", "buffers", "git" }, { "n" }),
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
  rescan_dir_for_git = create_action(lib.rescan_dir_for_git, "Rescan directory for git repo", { "files", "search", "buffers" }, { "n" }),

  toggle_git_tree = create_action(
    lib.toggle_git_tree,
    "Open or close the current git status tree",
    { "files", "search", "buffers", "git" },
    { "n" }
  ),
  toggle_buffers_tree = create_action(
    lib.toggle_buffers_tree,
    "Open or close the current buffers tree",
    { "files", "search", "buffers", "git" },
    { "n" }
  ),
  show_file_tree = create_action(lib.show_file_tree, "Show the file tree", { "search", "buffers", "git" }, { "n" }),

  focus_parent = create_action(ui.focus_parent, "Go to parent directory", { "files", "search", "buffers", "git" }, { "n" }),
  focus_prev_sibling = create_action(
    ui.focus_prev_sibling,
    "Go to previous sibling node",
    { "files", "search", "buffers", "git" },
    { "n" }
  ),
  focus_next_sibling = create_action(ui.focus_next_sibling, "Go to next sibling node", { "files", "search", "buffers", "git" }, { "n" }),
  focus_first_sibling = create_action(ui.focus_first_sibling, "Go to first sibling node", { "files", "search", "buffers", "git" }, { "n" }),
  focus_last_sibling = create_action(ui.focus_last_sibling, "Go to last sibling node", { "files", "search", "buffers", "git" }, { "n" }),
  focus_prev_git_item = create_action(ui.focus_prev_git_item, "Go to previous git item", { "files", "search", "buffers", "git" }, { "n" }),
  focus_next_git_item = create_action(ui.focus_next_git_item, "Go to next git item", { "files", "search", "buffers", "git" }, { "n" }),
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
  open_help = create_action(help.open, "Open keybindings help", { "files", "search", "buffers", "git" }, { "n" }),
}

---@param mapping Yat.Action.Mapping
---@return function|nil handler
local function create_keymap_function(mapping)
  local fn
  if mapping.action then
    local action = actions[mapping.action] --[[@as Yat.Action]]
    if action and action.fn then
      fn = void(action.fn) --[[@as fun(tree: Yat.Tree, node: Yat.Node)]]
    else
      log.error("action %q has no mapping", mapping.action)
      return nil
    end
  elseif mapping.fn then
    fn = void(mapping.fn) --[[@as fun(tree: Yat.Tree, node: Yat.Node)]]
  else
    log.error("cannot create keymap function for mappings %s", mapping)
    return nil
  end

  local tree_types = mapping.tree_types
  return function()
    if vim.tbl_contains(tree_types, ui.get_tree_type()) then
      local tabpage = api.nvim_get_current_tabpage()
      local node = ui.get_current_node() --[[@as Yat.Node]]
      local tree = Trees.current_tree(tabpage) --[[@as Yat.Tree]]
      tree.current_node = node
      fn(tree, node)
    end
  end
end

---@param bufnr number
function M.apply_mappings(bufnr)
  for _, mapping in pairs(M.mappings) do
    local opts = { buffer = bufnr, silent = true, nowait = true, desc = mapping.desc }
    local rhs = create_keymap_function(mapping)

    if not rhs or not pcall(vim.keymap.set, mapping.mode, mapping.key, rhs, opts) then
      utils.warn(string.format("Cannot construct mapping for key %q!", mapping.key))
    end
  end
end

---@class Yat.Action.Mapping
---@field tree_types Yat.Trees.Type[]|string[]
---@field mode Yat.Action.Mode
---@field key string
---@field desc string
---@field action? Yat.Action.Name
---@field fn? async fun(tree: Yat.Tree, node: Yat.Node)

---@param mappings Yat.Config.Mappings
---@return Yat.Action.Mapping[]
local function validate_and_create_mappings(mappings)
  ---@type Yat.Action.Mapping[]
  local action_mappings = {}

  for key, mapping in pairs(mappings.list) do
    if type(mapping) == "string" then
      local name = mapping --[[@as Yat.Action.Name]]
      if #name == 0 then
        log.debug("key %s is disabled by user config", key)
      elseif not actions[name] then
        log.error("Key %s is mapped to 'action' %q, which does not exist, mapping ignored!", vim.inspect(key), name)
        utils.warn(string.format("Key %s is mapped to 'action' %q, which does not exist, mapping ignored!", vim.inspect(key), name))
      else
        local action = actions[name]
        for _, mode in ipairs(action.modes) do
          action_mappings[#action_mappings + 1] = {
            tree_types = action.tree_types,
            mode = mode,
            key = key,
            desc = action.desc,
            action = name,
          }
        end
      end
    elseif type(mapping) == "table" then
      ---@cast mapping Yat.Config.Mapping.Custom
      local fn = mapping.fn
      if type(fn) == "function" then
        for _, mode in ipairs(mapping.modes) do
          action_mappings[#action_mappings + 1] = {
            tree_types = mapping.tree_types,
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
