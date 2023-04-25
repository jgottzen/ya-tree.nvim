local lazy = require("ya-tree.lazy")

local builtin = lazy.require("ya-tree.actions.builtin") ---@module "ya-tree.actions.builtin"
local completion = lazy.require("ya-tree.completion") ---@module "ya-tree.completion"
local GitStatusPanel = lazy.require("ya-tree.panels.git_status.panel") ---@module "ya-tree.panels.git_status.panel"
local tree_actions = lazy.require("ya-tree.panels.tree_actions") ---@module "ya-tree.panels.tree_actions"
local tree_renderers = lazy.require("ya-tree.panels.tree_renderers") ---@module "ya-tree.panels.tree_renderers"
local utils = lazy.require("ya-tree.utils") ---@module "ya-tree.utils"

---@alias Yat.Panel.GitStatus.SupportedActions
---| "system_open"
---| "show_node_info"
---|
---| "rename"
---
---| "cd_to"
---| "toggle_filter"
---
---| "goto_node_in_files_panel"
---
---| "search_for_node_in_panel"
---
---| "toggle_ignored"
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
  if not config.git.enable then
    return false
  end

  local renderers = config.panels.git_status.renderers
  M.renderers.directory, M.renderers.file = tree_renderers.create_renderers("git_status", renderers.directory, renderers.file)

  ---@type Yat.Panel.GitStatus.SupportedActions[]
  local supported_actions = utils.tbl_unique({
    builtin.general.system_open,
    builtin.general.show_node_info,

    builtin.files.rename,

    builtin.files.cd_to,
    builtin.files.toggle_filter,

    builtin.files.goto_node_in_files_panel,

    builtin.search.search_for_node_in_panel,

    builtin.git.toggle_ignored,
    builtin.git.focus_prev_git_item,
    builtin.git.focus_next_git_item,
    builtin.git.git_stage,
    builtin.git.git_unstage,
    builtin.git.git_revert,

    builtin.diagnostics.focus_prev_diagnostic_item,
    builtin.diagnostics.focus_next_diagnostic_item,

    unpack(vim.deepcopy(tree_actions.supported_actions)),
  })

  M.keymap = tree_actions.create_mappings("git_status", config.panels.git_status.mappings.list, supported_actions)

  return true
end

---@async
---@param sidebar Yat.Sidebar
---@param config Yat.Config
---@param repo? Yat.Git.Repo
---@return Yat.Panel.GitStatus
function M.create_panel(sidebar, config, repo)
  return GitStatusPanel:new(sidebar, config.panels.git_status, M.keymap, M.renderers, repo)
end

---@param current string
---@param args string[]
---@return string[]
function M.complete_command(current, args)
  if #args > 1 then
    return {}
  end

  if vim.startswith(current, "dir=") and current ~= "dir=" then
    return completion.complete_dir("dir=", current:sub(5))
  else
    return { "dir=.", "dir=/" }
  end
end

---@param args string[]
---@return table<string, string>|nil panel_args
function M.parse_commmand_arguments(args)
  local arg = args[1]
  if arg and vim.startswith(arg, "dir=") then
    local dir = arg:sub(5)
    if dir then
      return { dir = dir }
    end
  end
end

return M
