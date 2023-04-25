local lazy = require("ya-tree.lazy")

local builtin = lazy.require("ya-tree.actions.builtin") ---@module "ya-tree.actions.builtin"
local CallHierarchyPanel = lazy.require("ya-tree.panels.call_hierarchy.panel") ---@module "ya-tree.panels.call_hierarchy.panel"
local tree_actions = lazy.require("ya-tree.panels.tree_actions") ---@module "ya-tree.panels.tree_actions"
local tree_renderers = lazy.require("ya-tree.panels.tree_renderers") ---@module "ya-tree.panels.tree_renderers"
local utils = lazy.require("ya-tree.utils") ---@module "ya-tree.utils"

---@alias Yat.Panel.CallHierarchy.SupportedActions
---| "toggle_call_direction"
---| "create_call_hierarchy_from_buffer_position"
---
---| Yat.Panel.Tree.SupportedActions

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
}

---@param config Yat.Config
---@return boolean success
function M.setup(config)
  local renderers = config.panels.call_hierarchy.renderers
  M.renderers.container, M.renderers.leaf = tree_renderers.create_renderers("call_hierarchy", renderers.container, renderers.leaf)

  ---@type Yat.Panel.CallHierarchy.SupportedActions[]
  local supported_actions = utils.tbl_unique({
    builtin.call_hierarchy.toggle_call_direction,
    builtin.call_hierarchy.create_call_hierarchy_from_buffer_position,

    unpack(vim.deepcopy(tree_actions.supported_actions)),
  })

  M.keymap = tree_actions.create_mappings("call_hierarchy", config.panels.call_hierarchy.mappings.list, supported_actions)

  return true
end

---@async
---@param sidebar Yat.Sidebar
---@param config Yat.Config
---@return Yat.Panel.CallHierarchy
function M.create_panel(sidebar, config)
  return CallHierarchyPanel:new(sidebar, config.panels.call_hierarchy, M.keymap, M.renderers)
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
