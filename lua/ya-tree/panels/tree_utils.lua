local lazy = require("ya-tree.lazy")

local Actions = lazy.require("ya-tree.actions") ---@module "ya-tree.actions"
local builtin = require("ya-tree.actions.builtin")
local Logger = lazy.require("ya-tree.log") ---@module "ya-tree.log"
local utils = require("ya-tree.utils")

---@alias Yat.Panel.Tree.SupportedActions
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

local M = {
  ---@type Yat.Panel.Tree.SupportedActions[]
  supported_actions = utils.tbl_unique({
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
  }),
}

---@param panel_type Yat.Panel.Type
---@param mappings table<string, Yat.Actions.Name>
---@param supported_actions Yat.Actions.Name[]
---@return table<string, Yat.Action>
function M.create_mappings(panel_type, mappings, supported_actions)
  local log = Logger.get("panels")

  ---@type table<string, Yat.Action>
  local keymap = {}
  for key, name in pairs(mappings) do
    if name == "" then
      log.debug("key %q is disabled by user config", key)
    else
      local action = Actions.actions[name]
      if not action then
        log.error("key %q is mapped to 'action' %q, which doesn't exist, mapping ignored", key, name, panel_type)
        utils.warn(string.format("Key %q is mapped to 'action' %q, which doesnt' exist, mapping ignored!", key, name, panel_type))
      elseif not vim.tbl_contains(supported_actions, name) and not action.user_defined then
        log.error("key %q is mapped to 'action' %q, which panel %q doesn't support, mapping ignored", key, name, panel_type)
        utils.warn(
          string.format("Key %q is mapped to 'action' %q, which panel %q doesn't support, mapping ignored!", key, name, panel_type)
        )
      else
        if action then
          keymap[key] = action
        else
          log.debug("tree %q action %q is disabled due to dependent feature is disabled", panel_type, name)
        end
      end
    end
  end

  return keymap
end

return M
