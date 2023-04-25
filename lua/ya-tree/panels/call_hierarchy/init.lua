local builtin = require("ya-tree.actions.builtin")

---@alias Yat.Panel.CallHierarchy.SupportedActions
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
---| "toggle_call_direction"
---| "create_call_hierarchy_from_buffer_position"

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
  ---@type Yat.Panel.CallHierarchy.SupportedActions[]
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

    builtin.call_hierarchy.toggle_call_direction,
    builtin.call_hierarchy.create_call_hierarchy_from_buffer_position,
  },
}

---@param config Yat.Config
---@return boolean success
function M.setup(config)
  local renderers = config.panels.call_hierarchy.renderers
  local utils = require("ya-tree.panels.tree_utils")
  M.renderers.container, M.renderers.leaf = utils.create_renderers("call_hierarchy", renderers.container, renderers.leaf)
  M.keymap = utils.create_mappings("call_hierarchy", config.panels.call_hierarchy.mappings.list, M.supported_actions)
  return true
end

---@async
---@param sidebar Yat.Sidebar
---@param config Yat.Config
---@return Yat.Panel.CallHierarchy
function M.create_panel(sidebar, config)
  return require("ya-tree.panels.call_hierarchy.panel"):new(sidebar, config.panels.call_hierarchy, M.keymap, M.renderers)
end

---@param current string
---@param args string[]
---@return string[]
function M.complete_command(current, args)
  if #args > 1 then
    return {}
  end

  return vim.tbl_filter(function(direction)
    return vim.startswith(direction, current)
  end, { "direction=incoming", "direction=outgoing" })
end

---@param args string[]
---@return table<string, string>|nil panel_args
function M.parse_commmand_arguments(args)
  local direction = args[1]
  direction = direction and direction:sub(11)
  if direction and (direction == "incoming" or direction == "outgoing") then
    return { direction = direction }
  end
end

return M
