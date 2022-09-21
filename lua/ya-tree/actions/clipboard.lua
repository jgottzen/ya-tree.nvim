local scheduler = require("plenary.async.util").scheduler

local lib = require("ya-tree.lib")
local fs = require("ya-tree.filesystem")
local ui = require("ya-tree.ui")
local utils = require("ya-tree.utils")
local log = require("ya-tree.log")

local fn = vim.fn

local M = {
  ---@private
  ---@type Yat.Node[]
  queue = {},
}

---@alias Yat.Actions.Clipboard.Action "copy" | "cut"

---@param tree Yat.Tree
---@param action Yat.Actions.Clipboard.Action
local function cut_or_copy_nodes(tree, action)
  for _, node in ipairs(ui.get_selected_nodes()) do
    -- copying the root node will not work
    if tree.root ~= node then
      local skip = false
      for i = #M.queue, 1, -1 do
        local item = M.queue[i]
        if item.path == node.path then
          if item.clipboard_status == action then
            table.remove(M.queue, i)
            node:clear_clipboard_status()
          else
            node:set_clipboard_status(action)
          end
          skip = true
          break
        end
      end
      if not skip then
        M.queue[#M.queue + 1] = node
        node:set_clipboard_status(action)
      end
    end
  end

  ui.update(tree)
end

---@async
---@param tree Yat.Tree
function M.copy_node(tree)
  cut_or_copy_nodes(tree, "copy")
end

---@async
---@param tree Yat.Tree
function M.cut_node(tree)
  cut_or_copy_nodes(tree, "cut")
end

---@async
---@param dest_node Yat.Node
---@param node Yat.Node
---@return string|nil destination_path
local function paste_node(dest_node, node)
  if not fs.exists(node.path) then
    utils.warn(string.format("Item %q does not exist, cannot %s!", node.path, node.clipboard_status))
    return
  end

  local destination = utils.join_path(dest_node.path, node.name)
  local replace = false
  if fs.exists(destination) then
    local response = ui.select({ "Yes", "Rename", "No" }, { kind = "confirmation", prompt = destination .. " already exists" })

    if response == "Yes" then
      utils.notify(string.format("Will replace %q.", destination))
      replace = true
    elseif response == "Rename" then
      local name = ui.input({ prompt = "New name: ", default = node.name })
      if not name then
        utils.notify(string.format("No new name given, not pasting item %q to %q.", node.name, destination))
        return
      else
        destination = utils.join_path(dest_node.path, name)
        log.debug("new destination=%q", destination)
      end
    else
      utils.notify(string.format("Skipping item %q.", node.path))
      return
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

  return destination
end

local function clear_clipboard()
  for _, item in ipairs(M.queue) do
    item:clear_clipboard_status()
  end
  M.queue = {}
end

---@async
---@param tree Yat.Tree
---@param node Yat.Node
function M.paste_nodes(tree, node)
  -- paste can only be done into directories
  if not node:is_directory() then
    node = node.parent
    if not node then
      return
    end
  end

  if #M.queue > 0 then
    local first_file
    for _, item in ipairs(M.queue) do
      local destination_path = paste_node(node, item)
      if destination_path and not first_file then
        first_file = destination_path
      end
    end
    -- let the event loop catch up if there was a very large amount of files pasted
    scheduler()
    clear_clipboard()
    lib.refresh_tree_and_goto_path(tree, first_file)
  else
    utils.notify("Nothing in clipboard")
  end
end

---@async
---@param tree Yat.Tree
function M.clear_clipboard(tree)
  clear_clipboard()
  ui.update(tree)
  utils.notify("Clipboard cleared!")
end

---@param content string
local function copy_to_system_clipboard(content)
  fn.setreg("+", content)
  fn.setreg('"', content)
  utils.notify(string.format("Copied %s to system clipboad", content))
end

---@async
---@param _ Yat.Tree
---@param node Yat.Node
function M.copy_name_to_clipboard(_, node)
  copy_to_system_clipboard(node.name)
end

---@async
---@param tree Yat.Tree
---@param node Yat.Node
function M.copy_root_relative_path_to_clipboard(tree, node)
  local relative = utils.relative_path_for(node.path, tree.root.path)
  if node:is_directory() then
    relative = relative .. utils.os_sep
  end
  copy_to_system_clipboard(relative)
end

---@async
---@param _ Yat.Tree
---@param node Yat.Node
function M.copy_absolute_path_to_clipboard(_, node)
  copy_to_system_clipboard(node.path)
end

return M
