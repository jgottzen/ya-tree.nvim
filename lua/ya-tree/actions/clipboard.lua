local async = require("plenary.async")
local scheduler = require("plenary.async.util").scheduler

local lib = require("ya-tree.lib")
local fs = require("ya-tree.filesystem")
local ui = require("ya-tree.ui")
local utils = require("ya-tree.utils")
local log = require("ya-tree.log")

---@class ClipboardItem
---@field node YaTreeNode
---@field action clipboard_action

local M = {
  ---@type ClipboardItem[]
  queue = {},
}

---@alias clipboard_action "'copy'"|"'cut'"

local copy_action, cut_action = "copy", "cut"

---@param node YaTreeNode
---@param action clipboard_action
local function add_or_remove_or_replace_in_queue(node, action)
  for i, v in ipairs(M.queue) do
    if v.node.path == node.path then
      if v.action == action then
        table.remove(M.queue, i)
        node:set_clipboard_status(nil)
      else
        v.action = action
        node:set_clipboard_status(action)
      end
      return
    end
  end
  M.queue[#M.queue + 1] = { node = node, action = action }
  node:set_clipboard_status(action)
end

function M.copy_node()
  local nodes = ui.get_selected_nodes()
  for _, node in ipairs(nodes) do
    -- copying the root node will not work
    if not lib.is_node_root(node) then
      add_or_remove_or_replace_in_queue(node, copy_action)
    end
  end

  lib.redraw()
end

function M.cut_node()
  local nodes = ui.get_selected_nodes()
  for _, node in ipairs(nodes) do
    -- cutting the root node will not work
    if not lib.is_node_root(node) then
      add_or_remove_or_replace_in_queue(node, cut_action)
    end
  end

  lib.redraw()
end

---@param dest_node YaTreeNode
---@param node YaTreeNode
---@param action clipboard_action
---@return boolean, string?
local function paste_node(dest_node, node, action)
  if not fs.exists(node.path) then
    utils.print_error(string.format("Item %q does not exist, cannot %s!", node.path, action))
    return false
  end

  local destination = utils.join_path(dest_node.path, node.name)
  local replace = false
  if fs.exists(destination) then
    local response = ui.select({ "Yes", "Rename", "No" }, { prompt = destination .. " already exists" })

    vim.schedule(function()
      ui.reset_ui_window()
    end)

    if response == "Yes" then
      utils.print('Will replace "' .. destination .. '"')
      replace = true
    elseif response == "Rename" then
      local name = ui.input({ prompt = "New name: ", default = node.name })
      if not name then
        utils.print('No new name given, not pasting file "' .. node.name .. '" to "' .. destination .. '"')
        return false
      else
        destination = utils.join_path(dest_node.path, name)
        log.debug("new destination=%q", destination)
      end
    else
      utils.print('Skipping file "' .. node.path .. '"')
      return false
    end
  end

  ---@type boolean
  local ok
  if action == copy_action then
    if node:is_directory() then
      ok = fs.copy_dir(node.path, destination, replace)
    elseif node:is_file() then
      ok = fs.copy_file(node.path, destination, replace)
    end

    if ok then
      utils.print(string.format("Copied %q to %q", node.path, destination))
    else
      utils.print_error(string.format("Failed to copy %q to %q", node.path, destination))
    end
  else
    ok = fs.rename(node.path, destination)

    if ok then
      utils.print(string.format("Moved %q to %q", node.path, destination))
    else
      utils.print_error(string.format("Failed to move %q to %q", node.path, destination))
    end
  end

  return ok, destination
end

local function clear_clipboard()
  for _, v in ipairs(M.queue) do
    v.node:set_clipboard_status(nil)
  end
  M.queue = {}
end

---@param node YaTreeNode
function M.paste_from_clipboard(node)
  if not node then
    return
  end
  -- paste can only be done into directories
  if not node:is_directory() then
    node = node.parent
    if not node then
      return
    end
  end

  async.run(function()
    scheduler()

    if #M.queue > 0 then
      ---@type string
      local first_file
      for _, v in ipairs(M.queue) do
        local ok, result = paste_node(node, v.node, v.action)
        if ok and not first_file then
          first_file = result
        end
      end
      clear_clipboard()
      lib.refresh_and_navigate(first_file)
    else
      utils.print("Nothing in clipboard")
    end
  end)
end

function M.show_clipboard()
  if #M.queue > 0 then
    utils.print("The following file/directories are in the clipboard:")
    for _, v in ipairs(M.queue) do
      utils.print("  " .. v.action .. ": " .. v.node.path)
    end
  else
    utils.print("The clipboard is empty")
  end
end

function M.clear_clipboard()
  clear_clipboard()
  lib.redraw()
  utils.print("Clipboard cleared!")
end

---@param content string
local function copy_to_system_clipboard(content)
  vim.fn.setreg("+", content)
  vim.fn.setreg('"', content)
  utils.print(string.format("Copied %s to system clipboad", content))
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
