local completion = require("ya-tree.completion")
local utils = require("ya-tree.utils")

local fn = vim.fn

---@alias Yat.Panel.Files.SupportedActions
---| "system_open"
---| "show_node_info"
---
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
---| "goto_node_in_files_panel"
---
---| "search_for_node_in_panel"
---| "search_interactively"
---| "search_once"
---| "close_search"
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
  local tree_renderers = require("ya-tree.panels.tree_renderers")
  local config_renderers = config.panels.files.renderers
  M.renderers.directory, M.renderers.file = tree_renderers.create_renderers("files", config_renderers.directory, config_renderers.file)

  local tree_actions = require("ya-tree.panels.tree_actions")
  local builtin = require("ya-tree.actions.builtin")
  ---@type Yat.Panel.Files.SupportedActions[]
  local supported_actions = utils.tbl_unique({
    builtin.general.system_open,
    builtin.general.show_node_info,

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

    builtin.files.goto_node_in_files_panel,

    builtin.search.search_for_node_in_panel,
    builtin.search.search_interactively,
    builtin.search.search_once,
    builtin.search.close_search,

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

  local sorting = config.panels.files.sorting
  if not (sorting.directories_first and not sorting.case_sensitive and sorting.sort_by == "name") then
    local FilesystemNode = require("ya-tree.nodes.fs_node")
    local sort_by = sorting.sort_by
    if type(sort_by) == "function" then
      FilesystemNode.node_comparator = sort_by
    else
      FilesystemNode.node_comparator = FilesystemNode.static.create_comparator(sorting.directories_first, sorting.case_sensitive, sort_by)
    end
  end

  M.keymap = tree_actions.create_mappings("files", config.panels.files.mappings.list, supported_actions)

  return true
end

---@async
---@param sidebar Yat.Sidebar
---@param config Yat.Config
---@return Yat.Panel.Files
function M.create_panel(sidebar, config)
  return require("ya-tree.panels.files.panel"):new(sidebar, config.panels.files, M.keymap, M.renderers)
end

---@param current string
---@param args string[]
---@return string[]
function M.complete_command(current, args)
  if #args > 1 then
    return {}
  end
  if current == "path=%" then
    return {}
  end

  if vim.startswith(current, "path=") and current ~= "path=" then
    return completion.complete_file_and_dir("path=", current:sub(6))
  else
    return { "path=.", "path=/", "path=%" }
  end
end

---@param args string[]
---@return table<string, string>|nil panel_args
function M.parse_commmand_arguments(args)
  local arg = args[1]
  if arg and vim.startswith(arg, "path=") then
    ---@type string?
    local path = arg:sub(6)
    if path == "%" then
      path = fn.expand(path)
      path = fn.filereadable(path) == 1 and path or nil
    end
    if path then
      return { path = path }
    end
  end
end

return M
