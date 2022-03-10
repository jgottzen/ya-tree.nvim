local config = require("ya-tree.config").config
local lib = require("ya-tree.lib")
local ui = require("ya-tree.ui")
local clipboard = require("ya-tree.actions.clipboard")
local file_actions = require("ya-tree.actions.file-actions")
local search = require("ya-tree.actions.search")
local log = require("ya-tree.log")

local M = {}

---@type table<string, ActionMapping>
local commands = {}

---@type table<string, function>
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
  ["paste_from_clipboard"] = clipboard.paste_from_clipboard,
  ["show_clipboard"] = clipboard.show_clipboard,
  ["clear_clipboard"] = clipboard.clear_clipboard,
  ["copy_name_to_clipboard"] = clipboard.copy_name_to_clipboard,
  ["copy_root_relative_path_to_clipboard"] = clipboard.copy_root_relative_path_to_clipboard,
  ["copy_absolute_path_to_clipboard"] = clipboard.copy_absolute_path_to_clipboard,

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
  ["toggle_ignored"] = lib.toggle_ignored,
  ["toggle_filter"] = lib.toggle_filter,
  ["refresh"] = lib.refresh,
  ["live_search"] = search.live_search,
  ["search"] = search.search,
  ["clear_search"] = lib.clear_search,
  ["rescan_dir_for_git"] = lib.rescan_dir_for_git,
  ["toggle_help"] = lib.toggle_help,
  ["system_open"] = lib.system_open,
}

---@param id string
function M.execute(id)
  local command = commands[id]
  if ui.is_help_open() and command and command.name ~= "toggle_help" then
    return
  end

  if command then
    local node = lib.get_current_node()
    if command.action then
      command.action(node, config)
    elseif command.func then
      command.func(node, config)
    end
  end
end

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
    log.error("mapping for key %s doesn't have an action or func assigned", mapping.keys)
    return
  end

  return handler_id
end

---@param bufnr number
function M.apply_mappings(bufnr)
  local opts = { noremap = true, silent = true, nowait = true }
  for _, m in pairs(M.mappings) do
    for _, key in ipairs(m.keys) do
      local rhs
      if m.command then
        rhs = m.command
      else
        local handler = assing_handler(m)
        rhs = string.format("<cmd>lua require('ya-tree.actions').execute('%s')<CR>", handler)
      end

      if rhs then
        vim.api.nvim_buf_set_keymap(bufnr, m.mode, key, rhs, opts)
      else
        log.error("cannot construct mapping for key=%s", key)
      end
    end
  end
end

---@param mappings table<string|string[], YaTreeConfig.Mappings.Action>
---@return ActionMapping[]
local function validate_and_create_mappings(mappings)
  local valid = {}
  for k, m in pairs(mappings) do
    local mode = type(m.mode) == "table" and m.mode or (m.mode and { m.mode } or { "n" })
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
        log.error("key %s is mapped to 'action' %s, which does not exist, mapping ignored!", keys, m.action)
      else
        nr_of_mappings = nr_of_mappings + 1
      end
    elseif action ~= nil then
      action = nil
      log.error("key %s is not mapped to an action string, mapping ignored!", keys)
    end

    if type(func) == "function" then
      nr_of_mappings = nr_of_mappings + 1
    elseif func ~= nil then
      func = nil
      log.error("key %s is mapped to 'func' %s, which is not a function, mapping ignored!", keys, func)
    end

    if type(command) == "string" then
      nr_of_mappings = nr_of_mappings + 1
    elseif command ~= nil then
      command = nil
      log.error("key %s is mapped to 'command' %s, which is not a string, mapping ignored!", keys, command)
    end

    if nr_of_mappings == 1 then
      for _, v in ipairs(mode) do
        ---@class ActionMapping
        ---@field mode string
        ---@field keys string[]
        ---@field name string
        ---@field action? string
        ---@field func? function(node: Node, config: YaTreeConfig)
        ---@field command? string
        local mapping = {
          mode = v,
          keys = keys,
          name = action and action or (func and "'<function>'") or (command and ('"' .. command .. '"')),
          action = action,
          func = func,
          command = command,
        }
        valid[#valid + 1] = mapping
      end
    else
      log.error("Key %s is mapped to mutliple effect, ignoring key", keys)
    end
  end

  return valid
end

function M.setup()
  M.mappings = validate_and_create_mappings(config.mappings)
  file_actions.setup()
end

return M
