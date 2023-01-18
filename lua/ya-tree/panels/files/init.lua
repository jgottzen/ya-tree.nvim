local utils = require("ya-tree.utils")

---@alias Yat.Panel.Files.SupportedActions
---| "add"
---| "rename"
---| "delete"
---| "trash"
---
---| "copy_node"
---| "cut_node"
---| "paste_nodes"
---| "clear_clipboard"
---
---| "cd_to"
---| "cd_up"
---
---| "toggle_filter"
---
---| "search_for_node_in_panel"
---| "search_interactively"
---| "search_once"
---| "close_search"
---
---| "goto_node_in_files_panel"
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
  ---@type Yat.Panel.TreeRenderers
  renderers = {},
  ---@type table<string, Yat.Action>
  keymap = {},
}

---@param config Yat.Config
---@return boolean success
function M.setup(config)
  local tree_renderers = require("ya-tree.panels.tree_renderers")
  M.renderers = tree_renderers.create_renderers("files", config.panels.files.renderers)

  local tree_actions = require("ya-tree.panels.tree_actions")
  local builtin = require("ya-tree.actions.builtin")
  ---@type Yat.Panel.Files.SupportedActions[]
  local supported_actions = utils.tbl_unique({
    builtin.files.add,
    builtin.files.rename,
    builtin.files.delete,
    builtin.files.trash,

    builtin.files.copy_node,
    builtin.files.cut_node,
    builtin.files.paste_nodes,
    builtin.files.clear_clipboard,

    builtin.files.cd_to,
    builtin.files.cd_up,

    builtin.files.toggle_filter,

    builtin.search.search_for_node_in_panel,
    builtin.search.search_interactively,
    builtin.search.search_once,
    builtin.search.close_search,

    builtin.panel_specific.goto_node_in_files_panel,

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

  ---@type table<string, Yat.Actions.Name|string>
  local mappings = vim.tbl_deep_extend("force", config.panels.global_mappings.list, config.panels.files.mappings.list)
  M.keymap = tree_actions.create_mappings("files", mappings, supported_actions)

  return true
end

---@async
---@param sidebar Yat.Sidebar
---@param config Yat.Config
---@return Yat.Panel.GitStatus
function M.create_panel(sidebar, config)
  return require("ya-tree.panels.files.panel"):new(sidebar, config.panels.files, M.keymap, M.renderers)
end

return M
