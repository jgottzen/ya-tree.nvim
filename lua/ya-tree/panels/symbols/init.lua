local utils = require("ya-tree.utils")

---@alias Yat.Panel.Symbols.SupportedActions
---| "toggle_ignored"
---| "toggle_filter"
---
---| "search_for_node_in_panel"
---
---| "focus_prev_diagnostic_item"
---| "focus_next_diagnostic_item"
---
---| Yat.Panel.Tree.SupportedActions

---@type Yat.Panel.Factory
local M = {
  ---@private
  ---@type Yat.Panel.TreeRenderers
  renderers = {},
  ---@type table<string, Yat.Action>
  keymap = {},
}

---@param config Yat.Config
---@return boolean success
function M.setup(config)
  local tree_renderers = require("ya-tree.panels.tree_renderers")
  M.renderers = tree_renderers.create_renderers("symbols", config.panels.symbols.renderers)

  local tree_actions = require("ya-tree.panels.tree_actions")
  local builtin = require("ya-tree.actions.builtin")
  ---@type Yat.Panel.Symbols.SupportedActions[]
  local supported_actions = utils.tbl_unique({
    builtin.files.toggle_ignored,
    builtin.files.toggle_filter,

    builtin.search.search_for_node_in_panel,

    builtin.diagnostics.focus_prev_diagnostic_item,
    builtin.diagnostics.focus_next_diagnostic_item,

    unpack(vim.deepcopy(tree_actions.supported_actions)),
  })

  ---@type table<string, Yat.Actions.Name|string>
  local mappings = vim.tbl_deep_extend("force", config.panels.global_mappings.list, config.panels.symbols.mappings.list)
  M.keymap = tree_actions.create_mappings("symbols", mappings, supported_actions)

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
