local lazy = require("ya-tree.lazy")

local Logger = lazy.require("ya-tree.log") ---@module "ya-tree.log"

local M = {
  ---@type table<Yat.Actions.Name, Yat.Action>
  actions = {},
}

---@class Yat.Action
---@field name Yat.Actions.Name|string
---@field fn Yat.Action.TreePanelFn
---@field desc string
---@field modes Yat.Actions.Mode[]
---@field node_independent boolean
---@field user_defined boolean

---@param name Yat.Actions.Name|string The name of the action.
---@param fn Yat.Action.TreePanelFn The function implementing the action.
---@param desc string The description of the action.
---@param modes? Yat.Actions.Mode[] The mode(s) the action handles, defaults to ``{ "n" }`.
---@param node_independent? boolean Whether the action can be called without a `Yat.Node`, e.g. the `"open_help"` action, defaults to `false`.
---@param user_defined? boolean If the action is user defined, defauts to `false`.
function M.define_action(name, fn, desc, modes, node_independent, user_defined)
  ---@type Yat.Action
  local action = {
    name = name,
    fn = fn,
    desc = desc,
    modes = modes or { "n" },
    node_independent = node_independent == true,
    user_defined = user_defined == true,
  }
  if M.actions[name] then
    Logger.get("actions").info("overriding action %q with %s", name, action)
  end
  M.actions[name] = action
end

---@param config Yat.Config
local function define_actions(config)
  M.actions = {}

  local builtin = require("ya-tree.actions.builtin")
  local call_hierarchy = require("ya-tree.actions.call_hierarchy")
  local clipboard = require("ya-tree.actions.clipboard")
  local files = require("ya-tree.actions.files")
  local git = require("ya-tree.actions.git")
  local help = require("ya-tree.actions.help")
  local nodes = require("ya-tree.actions.nodes")
  local panels = require("ya-tree.actions.panels")
  local popups = require("ya-tree.actions.popups")
  local search = require("ya-tree.actions.search")
  local sidebar = require("ya-tree.actions.sidebar")

  M.define_action(builtin.general.close_sidebar, sidebar.close_sidebar, "Close the sidebar", { "n" }, true)
  M.define_action(builtin.general.system_open, files.system_open, "Open the node with the default system application")
  M.define_action(builtin.general.open_help, help.open_help, "Open keybindings help", { "n" }, true)
  M.define_action(builtin.general.show_node_info, popups.show_node_info, "Show node info in popup")
  M.define_action(builtin.general.close_panel, panels.close_panel, "Close the current panel", { "n" }, true)

  M.define_action(builtin.general.open_symbols_panel, panels.open_symbols_panel, "Open the Symbols panel", { "n" }, true)
  if config.git.enable then
    M.define_action(builtin.general.open_git_status_panel, panels.open_git_status_panel, "Open the Git Status panel", { "n" }, true)
  end
  M.define_action(builtin.general.open_buffers_panel, panels.open_buffers_panel, "Open the Buffers panel", { "n" }, true)
  M.define_action(
    builtin.general.open_call_hierarchy_panel,
    panels.open_call_hierarchy_panel,
    "Open the Call Hierarchy panel",
    { "n" },
    true
  )

  M.define_action(builtin.general.open, files.open, "Open file or directory", { "n", "v" })
  M.define_action(builtin.general.vsplit, files.vsplit, "Open file in a vertical split")
  M.define_action(builtin.general.split, files.split, "Open file in a split")
  M.define_action(builtin.general.tabnew, files.tabnew, "Open file in a new tabpage")
  M.define_action(builtin.general.preview, files.preview, "Preview file (keep cursor in tree)")
  M.define_action(builtin.general.preview_and_focus, files.preview_and_focus, "Preview file")

  M.define_action(builtin.general.copy_name_to_clipboard, clipboard.copy_name_to_clipboard, "Copy node name to system clipboard")
  M.define_action(
    builtin.general.copy_root_relative_path_to_clipboard,
    clipboard.copy_root_relative_path_to_clipboard,
    "Copy root-relative path to system clipboard"
  )
  M.define_action(
    builtin.general.copy_absolute_path_to_clipboard,
    clipboard.copy_absolute_path_to_clipboard,
    "Copy absolute path to system clipboard"
  )

  M.define_action(builtin.general.close_node, nodes.close_node, "Close directory")
  M.define_action(builtin.general.close_all_nodes, nodes.close_all_nodes, "Close all directories")
  M.define_action(builtin.general.close_all_child_nodes, nodes.close_all_child_nodes, "Close all child directories")
  M.define_action(builtin.general.expand_all_nodes, nodes.expand_all_nodes, "Recursively expand all directories")
  M.define_action(builtin.general.expand_all_child_nodes, nodes.expand_all_child_nodes, "Recursively expand all child directories")

  M.define_action(builtin.general.refresh_panel, panels.refresh_panel, "Refresh the panel", { "n" }, true)

  M.define_action(builtin.general.focus_parent, nodes.focus_parent, "Go to parent directory")
  M.define_action(builtin.general.focus_prev_sibling, nodes.focus_prev_sibling, "Go to previous sibling node")
  M.define_action(builtin.general.focus_next_sibling, nodes.focus_next_sibling, "Go to next sibling node")
  M.define_action(builtin.general.focus_first_sibling, nodes.focus_first_sibling, "Go to first sibling node")
  M.define_action(builtin.general.focus_last_sibling, nodes.focus_last_sibling, "Go to last sibling node")

  M.define_action(builtin.files.add, files.add, "Add file or directory")
  M.define_action(builtin.files.rename, files.rename, "Rename file or directory")
  M.define_action(builtin.files.delete, files.delete, "Delete files and directories", { "n", "v" })
  if config.trash.enable then
    M.define_action(builtin.files.trash, files.trash, "Trash files and directories", { "n", "v" })
  end

  M.define_action(builtin.files.copy_node, clipboard.copy_node, "Select files and directories for copy", { "n", "v" })
  M.define_action(builtin.files.cut_node, clipboard.cut_node, "Select files and directories for cut", { "n", "v" })
  M.define_action(builtin.files.paste_nodes, clipboard.paste_nodes, "Paste files and directories")
  M.define_action(builtin.files.clear_clipboard, clipboard.clear_clipboard, "Clear selected files and directories")

  M.define_action(builtin.files.cd_to, files.cd_to, "Set tree root to directory")
  M.define_action(builtin.files.cd_up, files.cd_up, "Set tree root one level up")

  M.define_action(builtin.files.toggle_filter, files.toggle_filter, "Toggle filtered files and directories", { "n" }, true)

  M.define_action(builtin.files.goto_node_in_files_panel, panels.goto_node_in_files_panel, "Go to node in the files panel")

  M.define_action(
    builtin.search.search_for_node_in_panel,
    search.search_for_node_in_panel,
    "Go to entered path in the panel",
    { "n" },
    true
  )
  M.define_action(builtin.search.search_interactively, search.search_interactively, "Search as you type", { "n" }, true)
  M.define_action(builtin.search.search_once, search.search_once, "Search", { "n" }, true)
  M.define_action(builtin.search.close_search, search.close_search, "Close search", { "n" }, true)

  if config.git.enable then
    M.define_action(builtin.git.toggle_ignored, git.toggle_ignored, "Toggle git ignored files and directories", { "n" }, true)
    M.define_action(builtin.git.check_node_for_git, git.check_node_for_git, "Check node for Git repo")
    M.define_action(builtin.git.open_repository, git.open_repository, "Open repository", { "n" }, true)
    M.define_action(builtin.git.focus_prev_git_item, nodes.focus_prev_git_item, "Go to previous Git item")
    M.define_action(builtin.git.focus_next_git_item, nodes.focus_next_git_item, "Go to next Git item")
    M.define_action(builtin.git.git_stage, git.stage, "Stage file/directory")
    M.define_action(builtin.git.git_unstage, git.unstage, "Unstage file/directory")
    M.define_action(builtin.git.git_revert, git.revert, "Revert file/directory")
  end

  if config.diagnostics.enable then
    M.define_action(builtin.diagnostics.focus_prev_diagnostic_item, nodes.focus_prev_diagnostic_item, "Go to the previous diagnostic item")
    M.define_action(builtin.diagnostics.focus_next_diagnostic_item, nodes.focus_next_diagnostic_item, "Go to the next diagnostic item")
  end

  M.define_action(
    builtin.call_hierarchy.toggle_call_direction,
    call_hierarchy.toggle_direction,
    "Toggle call hierarchy direction",
    { "n" },
    true
  )
  M.define_action(
    builtin.call_hierarchy.create_call_hierarchy_from_buffer_position,
    call_hierarchy.create_call_hierarchy_from_buffer_position,
    "Create call hierchy from buffer position",
    { "n" },
    true
  )

  local log = Logger.get("actions")
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
