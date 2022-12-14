local log = require("ya-tree.log")("actions")

local M = {
  ---@type table<Yat.Actions.Name, Yat.Action>
  actions = {},
}

---@class Yat.Action
---@field name Yat.Actions.Name|string
---@field fn Yat.Action.Fn
---@field desc string
---@field modes Yat.Actions.Mode[]
---@field node_independent boolean
---@field user_defined boolean

---@param name Yat.Actions.Name|string
---@param fn Yat.Action.Fn
---@param desc string
---@param modes Yat.Actions.Mode[]
---@param node_independent? boolean
---@param user_defined? boolean
function M.define_action(name, fn, desc, modes, node_independent, user_defined)
  ---@type Yat.Action
  local action = {
    name = name,
    fn = fn,
    desc = desc,
    modes = modes,
    node_independent = node_independent == true,
    user_defined = user_defined == true,
  }
  if M.actions[name] then
    log.info("overriding action %q with %s", name, action)
  end
  M.actions[name] = action
end

---@param config Yat.Config
local function define_actions(config)
  M.actions = {}

  local builtin = require("ya-tree.actions.builtin")
  local lib = require("ya-tree.lib")
  local clipboard = require("ya-tree.actions.clipboard")
  local files = require("ya-tree.actions.files")
  local git = require("ya-tree.actions.git")
  local help = require("ya-tree.actions.help")
  local nodes = require("ya-tree.actions.nodes")
  local popups = require("ya-tree.actions.popups")
  local search = require("ya-tree.actions.search")
  local trees = require("ya-tree.actions.trees")
  local ui = require("ya-tree.actions.ui")

  M.define_action(builtin.general.close_window, ui.close_window, "Close the tree window", { "n" }, true)
  M.define_action(builtin.general.system_open, files.system_open, "Open the node with the default system application", { "n" })
  M.define_action(builtin.general.open_help, help.open_help, "Open keybindings help", { "n" }, true)
  M.define_action(builtin.general.show_node_info, popups.show_node_info, "Show node info in popup", { "n" })
  M.define_action(builtin.general.close_tree, trees.close_tree, "Close the current tree", { "n" }, true)
  M.define_action(builtin.general.delete_tree, trees.delete_tree, "Delete the current tree", { "n" }, true)
  M.define_action(builtin.general.focus_prev_tree, trees.focus_prev_tree, "Go to previous tree", { "n" }, true)
  M.define_action(builtin.general.focus_next_tree, trees.focus_next_tree, "Go to next tree", { "n" }, true)

  M.define_action(builtin.general.open_symbols_tree, trees.open_symbols_tree, "Open the Symbols tree", { "n" }, false)
  if config.git.enable then
    M.define_action(builtin.general.open_git_tree, trees.open_git_tree, "Open the Git tree", { "n" }, true)
  end
  M.define_action(builtin.general.open_buffers_tree, trees.open_buffers_tree, "Open the Buffers tree", { "n" }, true)

  M.define_action(builtin.general.open, files.open, "Open file or directory", { "n", "v" })
  M.define_action(builtin.general.vsplit, files.vsplit, "Open file in a vertical split", { "n" })
  M.define_action(builtin.general.split, files.split, "Open file in a split", { "n" })
  M.define_action(builtin.general.tabnew, files.tabnew, "Open file in a new tabpage", { "n" })
  M.define_action(builtin.general.preview, files.preview, "Preview file (keep cursor in tree)", { "n" })
  M.define_action(builtin.general.preview_and_focus, files.preview_and_focus, "Preview file", { "n" })

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

  M.define_action(builtin.general.focus_parent, nodes.focus_parent, "Go to parent directory", { "n" })
  M.define_action(builtin.general.focus_prev_sibling, nodes.focus_prev_sibling, "Go to previous sibling node", { "n" })
  M.define_action(builtin.general.focus_next_sibling, nodes.focus_next_sibling, "Go to next sibling node", { "n" })
  M.define_action(builtin.general.focus_first_sibling, nodes.focus_first_sibling, "Go to first sibling node", { "n" })
  M.define_action(builtin.general.focus_last_sibling, nodes.focus_last_sibling, "Go to last sibling node", { "n" })

  M.define_action(builtin.files.add, files.add, "Add file or directory", { "n" })
  M.define_action(builtin.files.rename, files.rename, "Rename file or directory", { "n" })
  M.define_action(builtin.files.delete, files.delete, "Delete files and directories", { "n", "v" })
  if config.trash.enable then
    M.define_action(builtin.files.trash, files.trash, "Trash files and directories", { "n", "v" })
  end

  M.define_action(builtin.files.copy_node, clipboard.copy_node, "Select files and directories for copy", { "n", "v" })
  M.define_action(builtin.files.cut_node, clipboard.cut_node, "Select files and directories for cut", { "n", "v" })
  M.define_action(builtin.files.paste_nodes, clipboard.paste_nodes, "Paste files and directories", { "n" })
  M.define_action(builtin.files.clear_clipboard, clipboard.clear_clipboard, "Clear selected files and directories", { "n" })

  M.define_action(builtin.files.cd_to, lib.cd_to, "Set tree root to directory", { "n" })
  M.define_action(builtin.files.cd_up, lib.cd_up, "Set tree root one level up", { "n" })

  if config.git.enable then
    M.define_action(builtin.files.toggle_ignored, lib.toggle_ignored, "Toggle git ignored files and directories", { "n" }, true)
  end
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

  if config.git.enable then
    M.define_action(builtin.git.check_node_for_git, git.check_node_for_git, "Check node for Git repo", { "n" })
    M.define_action(builtin.git.focus_prev_git_item, nodes.focus_prev_git_item, "Go to previous Git item", { "n" })
    M.define_action(builtin.git.focus_next_git_item, nodes.focus_next_git_item, "Go to next Git item", { "n" })
    M.define_action(builtin.git.git_stage, git.stage, "Stage file/directory", { "n" })
    M.define_action(builtin.git.git_unstage, git.unstage, "Unstage file/directory", { "n" })
    M.define_action(builtin.git.git_revert, git.revert, "Revert file/directory", { "n" })
  end

  if config.diagnostics.enable then
    M.define_action(
      builtin.diagnostics.focus_prev_diagnostic_item,
      nodes.focus_prev_diagnostic_item,
      "Go to the previous diagnostic item",
      { "n" }
    )
    M.define_action(
      builtin.diagnostics.focus_next_diagnostic_item,
      nodes.focus_next_diagnostic_item,
      "Go to the next diagnostic item",
      { "n" }
    )
  end

  for name, action in pairs(config.actions) do
    log.debug("defining user action %q", name)
    M.define_action(name, action.fn, action.desc, action.modes, action.node_independent, true)
  end
end

---@param config Yat.Config
function M.setup(config)
  define_actions(config)
end

return M
