local void = require("plenary.async").void

local Trees = require("ya-tree.trees")
local ui = require("ya-tree.ui")
local utils = require("ya-tree.utils")
local log = require("ya-tree.log")("actions")

local api = vim.api

---@alias Yat.Actions.Mode "n" | "v" | "V"

---@class Yat.Action
---@field fn async fun(tree: Yat.Tree, node: Yat.Node)
---@field desc string
---@field trees Yat.Trees.Type[]
---@field modes Yat.Actions.Mode[]

local M = {
  ---@private
  ---@type table<Yat.Actions.Name, Yat.Action>
  actions = {},
}

---@param name Yat.Actions.Name
---@param fn async fun(tree: Yat.Tree, node: Yat.Node)
---@param desc string
---@param modes Yat.Actions.Mode[]
---@param trees? Yat.Trees.Type[]
function M.define_action(name, fn, desc, modes, trees)
  local action = {
    fn = fn,
    desc = desc,
    modes = modes,
    trees = trees or Trees.actions_supported_by_trees()[name] or {},
  }
  if M.actions[name] then
    log.info("overriding action %q with %s", name, action)
  end
  M.actions[name] = action
end

---@param mapping table<Yat.Trees.Type, Yat.Actions.Name|Yat.Config.Mapping.Custom>
---@return function handler
local function create_keymap_function(mapping)
  return function()
    local action = mapping[ui.get_tree_type()]
    if action then
      local tabpage = api.nvim_get_current_tabpage()
      local node = ui.get_current_node()
      local tree = Trees.current_tree(tabpage) --[[@as Yat.Tree]]
      tree.current_node = node
      if type(action) == "string" then
        void(M.actions[action].fn)(tree, node)
      else
        ---@cast action Yat.Config.Mapping.Custom
        void(action.fn)(tree, node)
      end
    end
  end
end

---@param bufnr number
function M.apply_mappings(bufnr)
  for key, mapping in pairs(M.mappings) do
    local opts = { buffer = bufnr, silent = true, nowait = true, desc = mapping.desc }
    local rhs = create_keymap_function(mapping)

    ---@type table<string, boolean>
    local modes = {}
    for _, action in pairs(mapping) do
      if type(action) == "string" then
        for _, mode in ipairs(M.actions[action].modes) do
          modes[mode] = true
        end
      else
        ---@cast action Yat.Config.Mapping.Custom
        for _, mode in ipairs(action.modes) do
          modes[mode] = true
        end
      end
    end
    for mode in pairs(modes) do
      if not pcall(vim.keymap.set, mode, key, rhs, opts) then
        utils.warn(string.format("Cannot construct mapping for key %q!", key))
      end
    end
  end
end

local function define_builtin_actions()
  local builtin = require("ya-tree.actions.builtin")
  local lib = require("ya-tree.lib")
  local help = require("ya-tree.ui.help")
  local clipboard = require("ya-tree.actions.clipboard")
  local files = require("ya-tree.actions.files")
  local nodes = require("ya-tree.actions.nodes")
  local popups = require("ya-tree.actions.popups")
  local search = require("ya-tree.actions.search")

  M.define_action(builtin.general.close_window, lib.close_window, "Close the tree window", { "n" })
  M.define_action(builtin.general.system_open, files.system_open, "Open the node with the default system application", { "n" })
  M.define_action(builtin.general.show_node_info, popups.show_node_info, "Show node info in popup", { "n" })
  M.define_action(builtin.general.open_help, help.open, "Open keybindings help", { "n" })

  M.define_action(builtin.general.toggle_git_tree, lib.toggle_git_tree, "Open or close the current git status tree", { "n" })
  M.define_action(builtin.general.toggle_buffers_tree, lib.toggle_buffers_tree, "Open or close the current buffers tree", { "n" })

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

  M.define_action(builtin.general.refresh_tree, lib.refresh_tree, "Refresh the tree", { "n" })

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

  M.define_action(builtin.files.toggle_ignored, lib.toggle_ignored, "Toggle git ignored files and directories", { "n" })
  M.define_action(builtin.files.toggle_filter, lib.toggle_filter, "Toggle filtered files and directories", { "n" })

  M.define_action(builtin.search.search_for_node_in_tree, search.search_for_node_in_tree, "Go to entered path in tree", { "n" })
  M.define_action(builtin.search.search_interactively, search.search_interactively, "Search as you type", { "n" })
  M.define_action(builtin.search.search_once, search.search_once, "Search", { "n" })
  M.define_action(builtin.search.show_last_search, lib.show_last_search, "Show last search result", { "n" })

  M.define_action(
    builtin.tree_specific.goto_node_in_files_tree,
    nodes.goto_node_in_files_tree,
    "Close current tree and go to node in the file tree",
    { "n" }
  )
  M.define_action(builtin.tree_specific.show_files_tree, lib.show_file_tree, "Show the file tree", { "n" })

  M.define_action(builtin.git.rescan_dir_for_git, lib.rescan_dir_for_git, "Rescan directory for git repo", { "n" })
  M.define_action(builtin.git.focus_prev_git_item, ui.focus_prev_git_item, "Go to previous git item", { "n" })
  M.define_action(builtin.git.focus_next_git_item, ui.focus_next_git_item, "Go to next git item", { "n" })

  M.define_action(
    builtin.diagnostics.focus_prev_diagnostic_item,
    ui.focus_prev_diagnostic_item,
    "Go to the previous diagnostic item",
    { "n" }
  )
  M.define_action(builtin.diagnostics.focus_next_diagnostic_item, ui.focus_next_diagnostic_item, "Go to the next diagnostic item", { "n" })
end

---@param actions Yat.Config.Actions
local function define_user_action(actions)
  for name, action in pairs(actions) do
    log.debug("defining user action %q", name)
    M.define_action(name, action.fn, action.desc, action.modes, action.trees)
  end
end

---@param trees Yat.Config.Trees
---@return table<string, table<Yat.Trees.Type, Yat.Actions.Name|Yat.Config.Mapping.Custom>>
local function validate_and_create_mappings(trees)
  ---@type table<string, boolean>
  local keys = {}
  for key, value in pairs(trees.global_mappings.list) do
    if value ~= "" then
      keys[key] = true
    end
  end

  ---@type table<Yat.Trees.Type, table<string, Yat.Actions.Name|""|Yat.Config.Mapping.Custom>>
  M.tree_mappings = {}
  for name, tree in pairs(trees) do
    if name ~= "global_mappings" then
      M.tree_mappings[name] = vim.tbl_deep_extend("force", trees.global_mappings.list, tree.mappings.list)
      for key, value in pairs(tree.mappings.list) do
        if value ~= "" then
          keys[key] = true
        end
      end
    end
  end

  ---@type table<string, table<Yat.Trees.Type, Yat.Actions.Name|Yat.Config.Mapping.Custom>>
  local mappings = {}
  for key in pairs(keys) do
    ---@type table<Yat.Trees.Type, Yat.Actions.Name|Yat.Config.Mapping.Custom>
    local entry = {}
    for tree_type, list in pairs(M.tree_mappings) do
      local mapping = list[key]
      if type(mapping) == "string" then
        if mapping == "" then
          log.debug("key %q is disabled by user config", key)
        elseif not M.actions[mapping] then
          log.error("key %q is mapped to 'action' %q, which does not exist, mapping ignored", key, mapping)
          utils.warn(string.format("Key %q is mapped to 'action' %q, which does not exist, mapping ignored!", key, mapping))
        elseif not vim.tbl_contains(M.actions[mapping].trees, tree_type) then
          log.error(
            "key %q is mapped to 'action' %q, which does not support tree type %q, mapping %s ignored",
            key,
            tree_type,
            mapping,
            M.actions[mapping]
          )
          utils.warn(
            string.format("Key %q is mapped to 'action' %q, which does not support tree type %q, mapping ignored!", key, tree_type, mapping)
          )
        else
          entry[tree_type] = mapping
        end
      elseif type(mapping) == "table" then
        ---@cast mapping Yat.Config.Mapping.Custom
        if type(mapping.fn) ~= "function" then
          log.error("key %q is mapped to 'fn' %s, which is not a function, mapping %s ignored", key, mapping.fn, mapping)
          utils.warn(string.format("Key %q is mapped to 'fn' %s, which is not a function, mapping ignored!", key, mapping.fn))
        elseif mapping.trees == nil or #mapping.trees == 0 then
          log.error("key %q has no trees associanted with it, mapping %s ignored", key, mapping)
          utils.warn(string.format("Key %q has no trees associanted with it, mapping ignored!", key))
        else
          entry[tree_type] = mapping
        end
      end
    end
    mappings[key] = entry
  end

  return mappings
end

---@param config Yat.Config
function M.setup(config)
  define_builtin_actions()
  define_user_action(config.actions)

  M.mappings = validate_and_create_mappings(config.trees)
end

return M
