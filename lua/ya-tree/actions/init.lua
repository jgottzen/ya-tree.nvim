local lib = require("ya-tree.lib")
local ui = require("ya-tree.ui")
local clipboard = require("ya-tree.actions.clipboard")
local files = require("ya-tree.actions.files")
local search = require("ya-tree.actions.search")
local utils = require("ya-tree.utils")
local log = require("ya-tree.log")

local M = {}

---@class YaTreeAction
---@field fun fun(node: YaTreeNode)
---@field desc string

---@type table<string, YaTreeAction>
local actions = {
  open = { fun = files.open, desc = "Open file or directory" },
  vsplit = { fun = files.vsplit, desc = "Open file in vertical split" },
  split = { fun = files.split, desc = "Open file in split" },
  preview = { fun = files.preview, desc = "Open files (keep cursor in tree)" },
  add = { fun = files.add, desc = "Add file or directory" },
  rename = { fun = files.rename, desc = "Rename file or directory" },
  delete = { fun = files.delete, desc = "Delete files and directories" },
  trash = { fun = files.trash, desc = "Trash files and directories" },

  copy_node = { fun = clipboard.copy_node, desc = "Select files and directories for copy" },
  cut_node = { fun = clipboard.cut_node, desc = "Select files and directories for cut" },
  paste_nodes = { fun = clipboard.paste_nodes, desc = "Paste files and directories" },
  clear_clipboard = { fun = clipboard.clear_clipboard, desc = "Clear selected files and directories" },
  copy_name_to_clipboard = { fun = clipboard.copy_name_to_clipboard, desc = "Copy node name to system clipboard" },
  copy_root_relative_path_to_clipboard = {
    fun = clipboard.copy_root_relative_path_to_clipboard,
    desc = "Copy root-relative path to system clipboard",
  },
  copy_absolute_path_to_clipboard = {
    fun = clipboard.copy_absolute_path_to_clipboard,
    desc = "Copy absolute path to system clipboard",
  },

  live_search = { fun = search.live_search, desc = "Live search" },
  search = { fun = search.search, desc = "Search" },
  clear_search = { fun = lib.clear_search, desc = "Clear search result" },

  close_tree = { fun = lib.close_tree, desc = "Close the tree window" },
  close_node = { fun = lib.close_node, desc = "Close directory" },
  close_all_nodes = { fun = lib.close_all_nodes, desc = "Close all directories" },
  cd_to = { fun = lib.cd_to, desc = "Set tree root to directory" },
  cd_up = { fun = lib.cd_up, desc = "Set tree root one level up" },
  parent_node = { fun = lib.parent_node, desc = "Go to parent directory" },
  prev_sibling = { fun = lib.prev_sibling, desc = "Go to previous sibling node" },
  next_sibling = { fun = lib.next_sibling, desc = "Go to next sibling node" },
  first_sibling = { fun = lib.first_sibling, desc = "Go to first sibling node" },
  last_sibling = { fun = lib.last_sibling, desc = "Go to last sibling node" },
  prev_git_item = { fun = lib.prev_git_item, desc = "Go to previous git item" },
  next_git_item = { fun = lib.next_git_item, desc = "Go to next git item" },
  toggle_ignored = { fun = lib.toggle_ignored, desc = "Toggle git ignored files and directories" },
  toggle_filter = { fun = lib.toggle_filter, desc = "Toggle filtered files and directories" },
  refresh = { fun = lib.refresh, desc = "Refresh the tree" },
  rescan_dir_for_git = { fun = lib.rescan_dir_for_git, desc = "Rescan directory for git repo" },
  open_help = { fun = lib.open_help, desc = "Open keybindings help" },
  system_open = { fun = lib.system_open, desc = "Open the node with the default system application" },
}

---@param mapping ActionMapping
---@return function handler
local function create_keymap_function(mapping)
  ---@type fun(node: YaTreeNode)
  local fun
  if mapping.action then
    local action = actions[mapping.action]
    if action and action.fun then
      fun = action.fun
    end
  elseif mapping.func then
    fun = mapping.func
  end

  return function()
    if fun then
      if not mapping.views[ui.get_view_mode()] then
        return
      end

      fun(ui.get_current_node())
    end
  end
end

---@param bufnr number
function M.apply_mappings(bufnr)
  for _, mapping in pairs(M.mappings) do
    for _, key in ipairs(mapping.keys) do
      local opts = { remap = false, silent = true, nowait = true, buffer = bufnr, desc = mapping.desc }
      ---@type string|function
      local rhs
      if mapping.command then
        rhs = mapping.command
      else
        rhs = create_keymap_function(mapping)
      end

      if not pcall(vim.keymap.set, mapping.mode, key, rhs, opts) then
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
    local desc = m.desc
    ---@type table<YaTreeCanvasMode, boolean>
    local views = {}
    if not m.views or vim.tbl_contains(m.views, "all") then
      views = {
        tree = true,
        search = true,
      }
    else
      for _, view in ipairs(m.views) do
        views[view] = true
      end
    end

    local nr_of_mappings = 0
    if type(action) == "string" then
      if #action == 0 then
        action = nil
        log.debug("key %s is disabled by user config", keys)
      elseif not actions[action] then
        action = nil
        utils.warn(string.format("key %s is mapped to 'action' %s, which does not exist, mapping ignored!", vim.inspect(keys), m.action))
      else
        desc = desc or actions[action].desc
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
        ---@field views table<YaTreeCanvasMode, boolean>
        ---@field mode string
        ---@field keys string[]
        ---@field name string
        ---@field desc? string
        ---@field action? string
        ---@field func? fun(node: YaTreeNode)
        ---@field command? string
        local mapping = {
          views = views,
          mode = mode,
          keys = keys,
          name = action and action or (func and "'<function>'") or (command and ('"' .. command .. '"')),
          desc = desc,
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
  M.mappings = validate_and_create_mappings(require("ya-tree.config").config.mappings)
end

return M
