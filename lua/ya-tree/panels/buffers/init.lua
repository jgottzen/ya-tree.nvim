local builtin = require("ya-tree.actions.builtin")

---@alias Yat.Panel.Buffers.SupportedActions
---| "close_sidebar"
---| "open_help"
---| "close_panel"
---
---| "open_git_status_panel"
---| "open_symbols_panel"
---| "open_call_hierarchy_panel"
---| "open_buffers_panel"
---
---| "open"
---| "vsplit"
---| "split"
---| "tabnew"
---| "preview"
---| "preview_and_focus"
---
---| "copy_name_to_clipboard"
---| "copy_root_relative_path_to_clipboard"
---| "copy_absolute_path_to_clipboard"
---
---| "close_node"
---| "close_all_nodes"
---| "close_all_child_nodes"
---| "expand_all_nodes"
---| "expand_all_child_nodes"
---
---| "refresh_panel"
---
---| "focus_parent"
---| "focus_prev_sibling"
---| "focus_next_sibling"
---| "focus_first_sibling"
---| "focus_last_sibling"
---
---| "system_open"
---| "show_node_info"
---|
---| "cd_to"
---| "toggle_filter"
---
---| "goto_node_in_files_panel"
---
---| "search_for_node_in_panel"
---
---| "toggle_ignored"
---| "check_node_for_git"
---| "focus_prev_git_item"
---| "focus_next_git_item"
---| "git_stage"
---| "git_unstage"
---| "git_revert"
---
---| "focus_prev_diagnostic_item"
---| "focus_next_diagnostic_item"

---@type Yat.Panel.Factory
local M = {
  ---@private
  renderers = {
    ---@type Yat.Panel.Tree.Ui.Renderer[]
    directory = {},
    ---@type Yat.Panel.Tree.Ui.Renderer[]
    file = {},
  },
  ---@type table<string, Yat.Action>
  keymap = {},
  ---@type Yat.Panel.Buffers.SupportedActions[]
  supported_actions = {
    builtin.general.close_sidebar,
    builtin.general.open_help,
    builtin.general.close_panel,

    builtin.general.open_git_status_panel,
    builtin.general.open_symbols_panel,
    builtin.general.open_call_hierarchy_panel,
    builtin.general.open_buffers_panel,

    builtin.general.open,
    builtin.general.vsplit,
    builtin.general.split,
    builtin.general.tabnew,
    builtin.general.preview,
    builtin.general.preview_and_focus,

    builtin.general.copy_name_to_clipboard,
    builtin.general.copy_root_relative_path_to_clipboard,
    builtin.general.copy_absolute_path_to_clipboard,

    builtin.general.close_node,
    builtin.general.close_all_nodes,
    builtin.general.close_all_child_nodes,
    builtin.general.expand_all_nodes,
    builtin.general.expand_all_child_nodes,

    builtin.general.refresh_panel,

    builtin.general.focus_parent,
    builtin.general.focus_prev_sibling,
    builtin.general.focus_next_sibling,
    builtin.general.focus_first_sibling,
    builtin.general.focus_last_sibling,

    builtin.general.system_open,
    builtin.general.show_node_info,

    builtin.files.cd_to,
    builtin.files.toggle_filter,

    builtin.files.goto_node_in_files_panel,

    builtin.search.search_for_node_in_panel,

    builtin.git.toggle_ignored,
    builtin.git.check_node_for_git,
    builtin.git.focus_prev_git_item,
    builtin.git.focus_next_git_item,
    builtin.git.git_stage,
    builtin.git.git_unstage,
    builtin.git.git_revert,

    builtin.diagnostics.focus_prev_diagnostic_item,
    builtin.diagnostics.focus_next_diagnostic_item,
  },
}

---@param config Yat.Config
---@return boolean success
function M.setup(config)
  local renderers = config.panels.buffers.renderers
  local utils = require("ya-tree.panels.tree_utils")
  M.renderers.directory, M.renderers.file = utils.create_renderers("buffers", renderers.directory, renderers.file)
  M.keymap = utils.create_mappings("buffers", config.panels.buffers.mappings.list, M.supported_actions)
  return true
end

---@async
---@param sidebar Yat.Sidebar
---@param config Yat.Config
---@return Yat.Panel.Buffers
function M.create_panel(sidebar, config)
  return require("ya-tree.panels.buffers.panel"):new(sidebar, config.panels.buffers, M.keymap, M.renderers)
end

return M
