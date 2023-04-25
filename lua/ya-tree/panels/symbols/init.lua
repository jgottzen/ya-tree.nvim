local lazy = require("ya-tree.lazy")

local builtin = lazy.require("ya-tree.actions.builtin") ---@module "ya-tree.actions.builtin"
local SymbolsPanel = lazy.require("ya-tree.panels.symbols.panel") ---@module "ya-tree.panels.symbols.panel"
local tree_actions = lazy.require("ya-tree.panels.tree_actions") ---@module "ya-tree.panels.tree_actions"
local tree_renderers = lazy.require("ya-tree.panels.tree_renderers") ---@module "ya-tree.panels.tree_renderers"
local utils = lazy.require("ya-tree.utils") ---@module "ya-tree.utils"

---@alias Yat.Panel.Symbols.SupportedActions
---| "toggle_filter"
---
---| "toggle_ignored"
---
---| "focus_prev_diagnostic_item"
---| "focus_next_diagnostic_item"
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
  local renderers = config.panels.symbols.renderers
  M.renderers.container, M.renderers.leaf = tree_renderers.create_renderers("symbols", renderers.container, renderers.leaf)

  ---@type Yat.Panel.Symbols.SupportedActions[]
  local supported_actions = utils.tbl_unique({
    builtin.files.toggle_filter,

    builtin.git.toggle_ignored,

    builtin.diagnostics.focus_prev_diagnostic_item,
    builtin.diagnostics.focus_next_diagnostic_item,

    unpack(vim.deepcopy(tree_actions.supported_actions)),
  })

  M.keymap = tree_actions.create_mappings("symbols", config.panels.symbols.mappings.list, supported_actions)

  return true
end

---@async
---@param sidebar Yat.Sidebar
---@param config Yat.Config
---@return Yat.Panel.Symbols
function M.create_panel(sidebar, config)
  return SymbolsPanel:new(sidebar, config.panels.symbols, M.keymap, M.renderers)
end

return M
