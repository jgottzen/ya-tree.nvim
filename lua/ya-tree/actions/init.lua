local config = require("ya-tree.config").config
local lib = require("ya-tree.lib")
local ui = require("ya-tree.ui")
local clipboard = require("ya-tree.actions.clipboard")
local file_actions = require("ya-tree.actions.file-actions")
local search = require("ya-tree.actions.search")
local utils = require("ya-tree.utils")
local log = require("ya-tree.log")

local M = {}

---@type table<string, ActionCommand>
local commands = {}

---@type table<string, fun(node: YaTreeNode):nil>
local actions = {
  ["open"] = file_actions.open,
  ["vsplit"] = file_actions.vsplit,
  ["split"] = file_actions.split,
  ["preview"] = file_actions.preview,
  ["add"] = file_actions.add,
  ["rename"] = file_actions.rename,
  ["delete"] = file_actions.delete,
  ["trash"] = file_actions.trash,

  ["copy_node"] = clipboard.copy_node,
  ["cut_node"] = clipboard.cut_node,
  ["paste_nodes"] = clipboard.paste_nodes,
  ["clear_clipboard"] = clipboard.clear_clipboard,
  ["copy_name_to_clipboard"] = clipboard.copy_name_to_clipboard,
  ["copy_root_relative_path_to_clipboard"] = clipboard.copy_root_relative_path_to_clipboard,
  ["copy_absolute_path_to_clipboard"] = clipboard.copy_absolute_path_to_clipboard,

  ["live_search"] = search.live_search,
  ["search"] = search.search,
  ["clear_search"] = lib.clear_search,

  ["close_window"] = lib.close,
  ["close_node"] = lib.close_node,
  ["close_all_nodes"] = lib.close_all_nodes,
  ["cd_to"] = lib.cd_to,
  ["cd_up"] = lib.cd_up,
  ["parent_node"] = lib.parent_node,
  ["prev_sibling"] = lib.prev_sibling,
  ["next_sibling"] = lib.next_sibling,
  ["first_sibling"] = lib.first_sibling,
  ["last_sibling"] = lib.last_sibling,
  ["prev_git_item"] = lib.prev_git_item,
  ["next_git_item"] = lib.next_git_item,
  ["toggle_ignored"] = lib.toggle_ignored,
  ["toggle_filter"] = lib.toggle_filter,
  ["refresh"] = lib.refresh,
  ["rescan_dir_for_git"] = lib.rescan_dir_for_git,
  ["toggle_help"] = lib.toggle_help,
  ["system_open"] = lib.system_open,
}

---@param id string
function M.execute(id)
  local command = commands[id]
  if not command then
    utils.warn(string.format("no command for id %q found", id))
    return
  end
  if ui.is_help_open() and command.name ~= "toggle_help" then
    return
  end

  local node = ui.get_current_node()
  if command.action then
    command.action(node)
  elseif command.func then
    command.func(node, config)
  end
end

---@class ActionCommand
---@field name string
---@field action? fun(node: YaTreeNode):nil
---@field func? fun(node: YaTreeNode, config: YaTreeConfig):nil

local next_handler_id = 1

---@param mapping ActionMapping
---@return string
local function assing_handler(mapping)
  local handler_id = tostring(next_handler_id)
  local action = mapping.action
  local func = mapping.func
  if action then
    handler_id = action
    commands[handler_id] = {
      name = action,
      action = actions[action],
    }
  elseif func then
    commands[handler_id] = {
      name = mapping.name or "function",
      func = func,
    }
    next_handler_id = next_handler_id + 1
  else
    utils.warn(string.format("mapping for key %s doesn't have an action or func assigned", vim.inspect(mapping.keys)))
    return
  end

  return handler_id
end

---@param bufnr number
function M.apply_mappings(bufnr)
  local opts = { noremap = true, silent = true, nowait = true }
  for _, mapping in pairs(M.mappings) do
    for _, key in ipairs(mapping.keys) do
      local rhs
      if mapping.command then
        rhs = mapping.command
      else
        local handler = assing_handler(mapping)
        if handler then
          rhs = string.format("<cmd>lua require('ya-tree.actions').execute('%s')<CR>", handler)
        end
      end

      if rhs then
        if not pcall(vim.api.nvim_buf_set_keymap, bufnr, mapping.mode, key, rhs, opts) then
          utils.warn(string.format("cannot construct mapping for key=%s", key))
        end
      else
        utils.warn(string.format("cannot construct mapping for key=%s", key))
      end
    end
  end
end

---@param mappings table<string|string[], YaTreeConfig.Mapping>
---@return ActionMapping[]
local function validate_and_create_mappings(mappings)
  ---@type ActionMapping[]
  local valid = {}
  for k, m in pairs(mappings) do
    ---@type string[]
    local modes = type(m.mode) == "table" and m.mode or (m.mode and { m.mode } or { "n" })
    ---@type string[]
    local keys = type(k) == "table" and k or { k }
    local action = m.action
    local func = m.func
    local command = m.command

    local nr_of_mappings = 0
    if type(action) == "string" then
      if #action == 0 then
        action = nil
        log.debug("key %s is disabled by user config", keys)
      elseif not actions[action] then
        action = nil
        utils.warn(string.format("key %s is mapped to 'action' %s, which does not exist, mapping ignored!", vim.inspect(keys), m.action))
      else
        nr_of_mappings = nr_of_mappings + 1
      end
    elseif action then
      action = nil
      utils.warn(string.format("key %s is not mapped to an action string, mapping ignored!", vim.inspect(keys)))
    end

    if type(func) == "function" then
      nr_of_mappings = nr_of_mappings + 1
    elseif func then
      func = nil
      utils.warn(string.format("key %s is mapped to 'func' %s, which is not a function, mapping ignored!", vim.inspect(keys), func))
    end

    if type(command) == "string" then
      nr_of_mappings = nr_of_mappings + 1
    elseif command then
      command = nil
      utils.warn(string.format("key %s is mapped to 'command' %s, which is not a string, mapping ignored!", vim.inspect(keys), command))
    end

    if nr_of_mappings == 1 then
      for _, mode in ipairs(modes) do
        ---@class ActionMapping
        ---@field mode string
        ---@field keys string[]
        ---@field name string
        ---@field action? string
        ---@field func? fun(node: YaTreeNode, config: YaTreeConfig):nil
        ---@field command? string
        local mapping = {
          mode = mode,
          keys = keys,
          name = action and action or (func and "'<function>'") or (command and ('"' .. command .. '"')),
          action = action,
          func = func,
          command = command,
        }
        valid[#valid + 1] = mapping
      end
    elseif nr_of_mappings > 1 then
      utils.warn(string.format("Key(s) %s is mapped to mutliple action, ignoring key", vim.inspect(keys)))
    else
      utils.warn(string.format("Key(s) %s is not mapped to anything, ignoring key", vim.inspect(keys)))
    end
  end

  return valid
end

function M.setup()
  M.mappings = validate_and_create_mappings(config.mappings)
  file_actions.setup()
end

return M
