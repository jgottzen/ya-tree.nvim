local void = require("plenary.async").void

local Sidebar = require("ya-tree.sidebar")
local utils = require("ya-tree.utils")
local log = require("ya-tree.log")("actions")

local api = vim.api

---@class Yat.Action.FnContext
---@field tabpage integer
---@field sidebar Yat.Sidebar

---@alias Yat.Action.Fn async fun(tree: Yat.Tree, node: Yat.Node, context: Yat.Action.FnContext)

---@alias Yat.Actions.Mode "n" | "v" | "V"

---@class Yat.Action
---@field fn Yat.Action.Fn
---@field desc string
---@field trees Yat.Trees.Type[]
---@field modes Yat.Actions.Mode[]
---@field node_independent boolean

local M = {
  ---@private
  ---@type table<Yat.Actions.Name, Yat.Action>
  _actions = {},
  ---@private
  ---@type table<string, table<Yat.Trees.Type, Yat.Actions.Name|Yat.Config.Mapping.Custom>>
  _mappings = {},
  ---@private
  ---@type table<Yat.Trees.Type, table<string, Yat.Actions.Name|""|Yat.Config.Mapping.Custom>>
  _tree_mappings = {},
}

---@param name Yat.Actions.Name
---@param fn Yat.Action.Fn
---@param desc string
---@param modes Yat.Actions.Mode[]
---@param node_independent? boolean
---@param trees? Yat.Trees.Type[]
function M.define_action(name, fn, desc, modes, node_independent, trees)
  local Trees = require("ya-tree.trees")
  ---@type Yat.Action
  local action = {
    fn = fn,
    desc = desc,
    modes = modes,
    trees = trees or Trees.actions_supported_by_trees()[name] or {},
    node_independent = node_independent == true,
  }
  if M._actions[name] then
    log.info("overriding action %q with %s", name, action)
  end
  M._actions[name] = action
end

---@param mapping table<Yat.Trees.Type, Yat.Actions.Name|Yat.Config.Mapping.Custom>
---@return function handler
local function create_keymap_function(mapping)
  return function()
    local tabpage = api.nvim_get_current_tabpage()
    local sidebar = Sidebar.get_sidebar(tabpage)
    if not sidebar then
      return
    end
    local row = api.nvim_win_get_cursor(0)[1]
    local tree, node = sidebar:get_current_tree_and_node(row)
    if tree then
      local action = mapping[tree.TYPE]
      if action then
        local fn, node_independent
        if type(action) == "string" then
          local _action = M._actions[action]
          fn = void(_action.fn)
          node_independent = _action.node_independent
        else
          ---@cast action Yat.Config.Mapping.Custom
          fn = void(action.fn)
          node_independent = action.node_independent
        end
        if node or node_independent then
          if node then
            tree.current_node = node
          end
          ---@cast fn Yat.Action.Fn
          ---@diagnostic disable-next-line:param-type-mismatch
          fn(tree, node, { tabpage = tabpage, sidebar = sidebar })
        end
      end
    end
  end
end

---@param bufnr integer
function M.apply_mappings(bufnr)
  local opts = { buffer = bufnr, silent = true, nowait = true }
  for key, mapping in pairs(M._mappings) do
    local rhs = create_keymap_function(mapping)

    ---@type table<string, boolean>, string[]
    local modes, descriptions = {}, {}
    for _, action in pairs(mapping) do
      if type(action) == "string" then
        for _, mode in ipairs(M._actions[action].modes) do
          modes[mode] = true
        end
        descriptions[#descriptions + 1] = M._actions[action].desc
      else
        ---@cast action Yat.Config.Mapping.Custom
        for _, mode in ipairs(action.modes) do
          modes[mode] = true
        end
        descriptions[#descriptions + 1] = action.desc
      end
    end
    opts.desc = table.concat(utils.tbl_unique(descriptions), "/")
    for mode in pairs(modes) do
      if not pcall(vim.keymap.set, mode, key, rhs, opts) then
        utils.warn(string.format("Cannot construct mapping for key %q!", key))
      end
    end
  end
end

---@param actions Yat.Config.Actions
local function define_actions(actions)
  M._actions = {}

  local builtin = require("ya-tree.actions.builtin")
  local lib = require("ya-tree.lib")
  local clipboard = require("ya-tree.actions.clipboard")
  local files = require("ya-tree.actions.files")
  local git = require("ya-tree.actions.git")
  local nodes = require("ya-tree.actions.nodes")
  local popups = require("ya-tree.actions.popups")
  local search = require("ya-tree.actions.search")
  local trees = require("ya-tree.actions.trees")
  local ui = require("ya-tree.actions.ui")

  M.define_action(builtin.general.close_window, ui.close, "Close the tree window", { "n" }, true)
  M.define_action(builtin.general.system_open, files.system_open, "Open the node with the default system application", { "n" })
  M.define_action(builtin.general.open_help, ui.open_help, "Open keybindings help", { "n" }, true)
  M.define_action(builtin.general.show_node_info, popups.show_node_info, "Show node info in popup", { "n" })
  M.define_action(builtin.general.close_tree, trees.close_tree, "Close the current tree", { "n" }, true)
  M.define_action(builtin.general.delete_tree, trees.delete_tree, "Delete the current tree", { "n" }, true)
  M.define_action(builtin.general.focus_prev_tree, ui.focus_prev_tree, "Go to previous tree", { "n" }, true)
  M.define_action(builtin.general.focus_next_tree, ui.focus_next_tree, "Go to next tree", { "n" }, true)

  M.define_action(builtin.general.open_git_tree, trees.open_git_tree, "Open or close the current git status tree", { "n" }, true)
  M.define_action(builtin.general.open_buffers_tree, trees.open_buffers_tree, "Open or close the current buffers tree", { "n" }, true)

  M.define_action(builtin.general.open, files.open, "Open file or directory", { "n", "v" })
  M.define_action(builtin.general.vsplit, files.vsplit, "Open file in a vertical split", { "n" })
  M.define_action(builtin.general.split, files.split, "Open file in a split", { "n" })
  M.define_action(builtin.general.tabnew, files.tabnew, "Open file in a new tabpage", { "n" })
  M.define_action(builtin.general.preview, files.preview, "Open file (keep cursor in tree)", { "n" })
  M.define_action(builtin.general.preview_and_focus, files.preview_and_focus, "Open file (keep cursor in tree)", { "n" })

  M.define_action(builtin.general.copy_name_to_clipboard, clipboard.copy_name_to_clipboard, "Copy node name to system clipboard", { "n" })
  M.define_action(
    builtin.general.copy_root_relative_path_to_clipboard,
    clipboard.copy_root_relative_path_to_clipboard,
    "Copy root-relative path to system clipboard",
    { "n" }
  )
  M.define_action(
    builtin.general.copy_absolute_path_to_clipboard,
    clipboard.copy_absolute_path_to_clipboard,
    "Copy absolute path to system clipboard",
    { "n" }
  )

  M.define_action(builtin.general.close_node, nodes.close_node, "Close directory", { "n" })
  M.define_action(builtin.general.close_all_nodes, nodes.close_all_nodes, "Close all directories", { "n" })
  M.define_action(builtin.general.close_all_child_nodes, nodes.close_all_child_nodes, "Close all child directories", { "n" })
  M.define_action(builtin.general.expand_all_nodes, nodes.expand_all_nodes, "Recursively expand all directories", { "n" })
  M.define_action(builtin.general.expand_all_child_nodes, nodes.expand_all_child_nodes, "Recursively expand all child directories", { "n" })

  M.define_action(builtin.general.refresh_tree, trees.refresh_tree, "Refresh the tree", { "n" }, true)

  M.define_action(builtin.general.focus_parent, ui.focus_parent, "Go to parent directory", { "n" })
  M.define_action(builtin.general.focus_prev_sibling, ui.focus_prev_sibling, "Go to previous sibling node", { "n" })
  M.define_action(builtin.general.focus_next_sibling, ui.focus_next_sibling, "Go to next sibling node", { "n" })
  M.define_action(builtin.general.focus_first_sibling, ui.focus_first_sibling, "Go to first sibling node", { "n" })
  M.define_action(builtin.general.focus_last_sibling, ui.focus_last_sibling, "Go to last sibling node", { "n" })

  M.define_action(builtin.files.add, files.add, "Add file or directory", { "n" })
  M.define_action(builtin.files.rename, files.rename, "Rename file or directory", { "n" })
  M.define_action(builtin.files.delete, files.delete, "Delete files and directories", { "n", "v" })
  M.define_action(builtin.files.trash, files.trash, "Trash files and directories", { "n", "v" })

  M.define_action(builtin.files.copy_node, clipboard.copy_node, "Select files and directories for copy", { "n", "v" })
  M.define_action(builtin.files.cut_node, clipboard.cut_node, "Select files and directories for cut", { "n", "v" })
  M.define_action(builtin.files.paste_nodes, clipboard.paste_nodes, "Paste files and directories", { "n" })
  M.define_action(builtin.files.clear_clipboard, clipboard.clear_clipboard, "Clear selected files and directories", { "n" })

  M.define_action(builtin.files.cd_to, lib.cd_to, "Set tree root to directory", { "n" })
  M.define_action(builtin.files.cd_up, lib.cd_up, "Set tree root one level up", { "n" })

  M.define_action(builtin.files.toggle_ignored, lib.toggle_ignored, "Toggle git ignored files and directories", { "n" }, true)
  M.define_action(builtin.files.toggle_filter, lib.toggle_filter, "Toggle filtered files and directories", { "n" }, true)

  M.define_action(builtin.search.search_for_node_in_tree, search.search_for_node_in_tree, "Go to entered path in tree", { "n" }, true)
  M.define_action(builtin.search.search_interactively, search.search_interactively, "Search as you type", { "n" }, true)
  M.define_action(builtin.search.search_once, search.search_once, "Search", { "n" }, true)

  M.define_action(
    builtin.tree_specific.goto_node_in_filesystem_tree,
    nodes.goto_node_in_filesystem_tree,
    "Go to node in the filesystem tree",
    { "n" }
  )

  M.define_action(builtin.git.check_node_for_git, git.check_node_for_git, "Check node for Git repo", { "n" })
  M.define_action(builtin.git.focus_prev_git_item, ui.focus_prev_git_item, "Go to previous Git item", { "n" })
  M.define_action(builtin.git.focus_next_git_item, ui.focus_next_git_item, "Go to next Git item", { "n" })

  M.define_action(
    builtin.diagnostics.focus_prev_diagnostic_item,
    ui.focus_prev_diagnostic_item,
    "Go to the previous diagnostic item",
    { "n" }
  )
  M.define_action(builtin.diagnostics.focus_next_diagnostic_item, ui.focus_next_diagnostic_item, "Go to the next diagnostic item", { "n" })

  for name, action in pairs(actions) do
    log.debug("defining user action %q", name)
    M.define_action(name, action.fn, action.desc, action.modes, action.node_independent, action.trees)
  end
end

---@param trees Yat.Config.Trees
local function validate_and_create_mappings(trees)
  M._tree_mappings = {}
  ---@type table<string, boolean>
  local keys = {}
  for key, value in pairs(trees.global_mappings.list) do
    if value ~= "" then
      keys[key] = true
    end
  end

  for name, tree in pairs(trees) do
    if name ~= "global_mappings" then
      M._tree_mappings[name] = vim.tbl_deep_extend("force", trees.global_mappings.list, tree.mappings.list)
      for key, value in pairs(tree.mappings.list) do
        if value ~= "" then
          keys[key] = true
        end
      end
    end
  end

  M._mappings = {}
  for key in pairs(keys) do
    ---@type table<Yat.Trees.Type, Yat.Actions.Name|Yat.Config.Mapping.Custom>
    local entry = {}
    for tree_type, list in pairs(M._tree_mappings) do
      local mapping = list[key]
      if type(mapping) == "string" then
        if mapping == "" then
          log.debug("key %q is disabled by user config", key)
        elseif not M._actions[mapping] then
          log.error("key %q is mapped to 'action' %q, which does not exist, mapping ignored", key, mapping)
          utils.warn(string.format("Key %q is mapped to 'action' %q, which does not exist, mapping ignored!", key, mapping))
          list[key] = nil
        elseif not vim.tbl_contains(M._actions[mapping].trees, tree_type) then
          log.error(
            "key %q is mapped to 'action' %q, which does not support tree type %q, mapping %s ignored",
            key,
            mapping,
            tree_type,
            M._actions[mapping]
          )
          utils.warn(
            string.format("Key %q is mapped to 'action' %q, which does not support tree type %q, mapping ignored!", key, mapping, tree_type)
          )
          list[key] = nil
        else
          entry[tree_type] = mapping
        end
      elseif type(mapping) == "table" then
        ---@cast mapping Yat.Config.Mapping.Custom
        if type(mapping.fn) ~= "function" then
          log.error("key %q is mapped to 'fn' %s, which is not a function, mapping %s ignored", key, mapping.fn, mapping)
          utils.warn(string.format("Key %q is mapped to 'fn' %s, which is not a function, mapping ignored!", key, mapping.fn))
          list[key] = nil
        else
          if mapping.modes == nil or #mapping.modes == 0 then
            mapping.modes = { "n" }
          end
          entry[tree_type] = mapping
        end
      end
    end
    M._mappings[key] = entry
  end
end

---@param config Yat.Config
function M.setup(config)
  define_actions(config.actions)
  validate_and_create_mappings(config.trees)
end

return M
