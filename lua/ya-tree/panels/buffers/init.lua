local lazy = require("ya-tree.lazy")

local BuffersPanel = lazy.require("ya-tree.panels.buffers.panel") ---@module "ya-tree.panels.buffers.panel"
local builtin = lazy.require("ya-tree.actions.builtin") ---@module "ya-tree.actions.builtin"
local tree_actions = lazy.require("ya-tree.panels.tree_actions") ---@module "ya-tree.panels.tree_actions"
local tree_renderers = lazy.require("ya-tree.panels.tree_renderers") ---@module "ya-tree.panels.tree_renderers"
local utils = lazy.require("ya-tree.utils") ---@module "ya-tree.utils"

---@alias Yat.Panel.Buffers.SupportedActions
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
---
---| Yat.Panel.Tree.SupportedActions

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
}

---@param config Yat.Config
---@return boolean success
function M.setup(config)
  local renderers = config.panels.buffers.renderers
  M.renderers.directory, M.renderers.file = tree_renderers.create_renderers("buffers", renderers.directory, renderers.file)

  ---@type Yat.Panel.Buffers.SupportedActions[]
  local supported_actions = utils.tbl_unique({
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

    unpack(vim.deepcopy(tree_actions.supported_actions)),
  })

  M.keymap = tree_actions.create_mappings("buffers", config.panels.buffers.mappings.list, supported_actions)

  return true
end

---@async
---@param sidebar Yat.Sidebar
---@param config Yat.Config
---@return Yat.Panel.Buffers
function M.create_panel(sidebar, config)
  return BuffersPanel:new(sidebar, config.panels.buffers, M.keymap, M.renderers)
end

return M
