local builtin = require("ya-tree.actions.builtin")

---@alias Yat.Panel.Symbols.SupportedActions
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
---| "toggle_filter"
---
---| "toggle_ignored"
---
---| "focus_prev_diagnostic_item"
---| "focus_next_diagnostic_item"

---@type Yat.Panel.Factory
local M = {
  ---@private
  renderers = {
    ---@type Yat.Panel.Tree.Ui.Renderer[]
    container = {},
    ---@type Yat.Panel.Tree.Ui.Renderer[]
    leaf = {},
  },
  ---@type table<string, Yat.Action>
  keymap = {},
  ---@type Yat.Panel.Symbols.SupportedActions[]
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

    builtin.files.toggle_filter,

    builtin.git.toggle_ignored,

    builtin.diagnostics.focus_prev_diagnostic_item,
    builtin.diagnostics.focus_next_diagnostic_item,
  },
}

---@param config Yat.Config
---@return boolean success
function M.setup(config)
  local renderers = config.panels.symbols.renderers
  local utils = require("ya-tree.panels.tree_utils")
  M.renderers.container, M.renderers.leaf = utils.create_renderers("symbols", renderers.container, renderers.leaf)
  M.keymap = utils.create_mappings("symbols", config.panels.symbols.mappings.list, M.supported_actions)
  return true
end

---@async
---@param sidebar Yat.Sidebar
---@param config Yat.Config
---@return Yat.Panel.Symbols
function M.create_panel(sidebar, config)
  return require("ya-tree.panels.symbols.panel"):new(sidebar, config.panels.symbols, M.keymap, M.renderers)
end

return M
