local async = require("plenary.async")
local scheduler = require("plenary.async.util").scheduler

local lib = require("ya-tree.lib")
local fs = require("ya-tree.filesystem")
local ui = require("ya-tree.ui")
local utils = require("ya-tree.utils")
local log = require("ya-tree.log")

local fn = vim.fn

local M = {
  ---@private
  ---@type YaTreeNode[]
  queue = {},
}

---@alias clipboard_action "copy"|"cut"

---@param node YaTreeNode
---@param action clipboard_action
local function add_or_remove_or_replace_in_queue(node, action)
  for i, item in ipairs(M.queue) do
    if item.path == node.path then
      if item.clipboard_status == action then
        table.remove(M.queue, i)
        node:clear_clipboard_status()
      else
        node:set_clipboard_status(action)
      end
      return
    elseif item:is_ancestor_of(node.path) then
      return
    end
  end
  M.queue[#M.queue + 1] = node
  node:set_clipboard_status(action)
end

function M.copy_node()
  local nodes = ui.get_selected_nodes()
  for _, node in ipairs(nodes) do
    -- copying the root node will not work
    if not lib.is_node_root(node) then
      add_or_remove_or_replace_in_queue(node, "copy")
    end
  end

  lib.redraw()
end

function M.cut_node()
  local nodes = ui.get_selected_nodes()
  for _, node in ipairs(nodes) do
    -- cutting the root node will not work
    if not lib.is_node_root(node) then
      add_or_remove_or_replace_in_queue(node, "cut")
    end
  end

  lib.redraw()
end

---@async
---@param dest_node YaTreeNode
---@param node YaTreeNode
---@return boolean success, string? destination_path
local function paste_node(dest_node, node)
  if not fs.exists(node.path) then
    utils.warn(string.format("Item %q does not exist, cannot %s!", node.path, node.clipboard_status))
    return false
  end

  local destination = utils.join_path(dest_node.path, node.name)
  local replace = false
  if fs.exists(destination) then
    local response = ui.select({ "Yes", "Rename", "No" }, { prompt = destination .. " already exists" })

    if response == "Yes" then
      utils.notify(string.format("Will replace %q.", destination))
      replace = true
    elseif response == "Rename" then
      local name = ui.input({ prompt = "New name: ", default = node.name })
      if not name then
        utils.notify(string.format("No new name given, not pasting item %q to %q.", node.name, destination))
        return false
      else
        destination = utils.join_path(dest_node.path, name)
        log.debug("new destination=%q", destination)
      end
    else
      utils.notify(string.format("Skipping item %q.", node.path))
      return false
    end
  end

  local ok = false
  if node.clipboard_status == "copy" then
    if node:is_directory() then
      ok = fs.copy_dir(node.path, destination, replace)
    elseif node:is_file() then
      ok = fs.copy_file(node.path, destination, replace)
    end
  elseif node.clipboard_status == "cut" then
    ok = fs.rename(node.path, destination)
  end

  if ok then
    utils.notify(string.format("%s %q to %q.", node.clipboard_status == "copy" and "Copied" or "Moved", node.path, destination))
  else
    utils.warn(string.format("Failed to %s %q to %q!", node.clipboard_status == "copy" and "copy" or "move", node.path, destination))
  end

  return ok, destination
end

local function clear_clipboard()
  for _, item in ipairs(M.queue) do
    item:clear_clipboard_status()
  end
  M.queue = {}
end

---@param node YaTreeNode
function M.paste_nodes(node)
  -- paste can only be done into directories
  if not node:is_directory() then
    node = node.parent
    if not node then
      return
    end
  end

  async.void(function()
    if #M.queue > 0 then
      ---@type string
      local first_file
      for _, item in ipairs(M.queue) do
        local ok, result = paste_node(node, item)
        scheduler()
        if ok and not first_file then
          first_file = result
        end
      end
      clear_clipboard()
      lib.refresh_tree(first_file)
    else
      utils.notify("Nothing in clipboard")
    end
  end)()
end

function M.clear_clipboard()
  clear_clipboard()
  lib.redraw()
  utils.notify("Clipboard cleared!")
end

---@param content string
local function copy_to_system_clipboard(content)
  fn.setreg("+", content)
  fn.setreg('"', content)
  utils.notify(string.format("Copied %s to system clipboad", content))
end

---@param node YaTreeNode
function M.copy_name_to_clipboard(node)
  copy_to_system_clipboard(node.name)
end

---@param node YaTreeNode
function M.copy_root_relative_path_to_clipboard(node)
  local relative = utils.relative_path_for(node.path, lib.get_root_node_path())
  if node:is_directory() then
    relative = relative .. utils.os_sep
  end
  copy_to_system_clipboard(relative)
end

---@param node YaTreeNode
function M.copy_absolute_path_to_clipboard(node)
  copy_to_system_clipboard(node.path)
end

return M
