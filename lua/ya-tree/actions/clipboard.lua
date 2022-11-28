local fs = require("ya-tree.fs")
local ui = require("ya-tree.ui")
local utils = require("ya-tree.utils")
local log = require("ya-tree.log")("actions")

local fn = vim.fn

local M = {
  ---@type Yat.Node[]
  queue = {},
}

---@alias Yat.Actions.Clipboard.Action "copy"|"cut"

---@param sidebar Yat.Sidebar
---@param tree Yat.Tree
---@param action Yat.Actions.Clipboard.Action
local function cut_or_copy_nodes(sidebar, tree, action)
  for _, node in ipairs(sidebar:get_selected_nodes()) do
    -- copying the root node will not work
    if tree.root ~= node then
      local skip = false
      for i = #M.queue, 1, -1 do
        local item = M.queue[i]
        if item.path == node.path then
          if item:clipboard_status() == action then
            table.remove(M.queue, i)
            node:set_clipboard_status(nil)
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
  sidebar:update()
end

---@async
---@param tree Yat.Tree
---@param _ Yat.Node
---@param sidebar Yat.Sidebar
function M.copy_node(tree, _, sidebar)
  cut_or_copy_nodes(sidebar, tree, "copy")
end

---@async
---@param tree Yat.Tree
---@param _ Yat.Node
---@param sidebar Yat.Sidebar
function M.cut_node(tree, _, sidebar)
  cut_or_copy_nodes(sidebar, tree, "cut")
end

local function clear_clipboard()
  for _, item in ipairs(M.queue) do
    item:set_clipboard_status(nil)
  end
  M.queue = {}
end

---@async
---@param tree Yat.Trees.Filesystem
---@param node Yat.Node
function M.paste_nodes(tree, node)
  ---@async
  ---@param dir string
  ---@param nodes_to_paste Yat.Node[]
  ---@return { node: Yat.Node, destination: string, replace: boolean }[]
  local function get_nodes_to_paste(dir, nodes_to_paste)
    ---@type { node: Yat.Node, destination: string, replace: boolean }[]
    local items = {}
    for _, node_to_paste in ipairs(nodes_to_paste) do
      if not fs.exists(node_to_paste.path) then
        utils.warn(string.format("Item %q does not exist, cannot %s!", node_to_paste.path, node_to_paste:clipboard_status()))
      else
        local destination = utils.join_path(dir, node_to_paste.name)
        local skip = false
        local replace = false
        if fs.exists(destination) then
          local response = ui.select({ "Yes", "Rename", "No" }, { kind = "confirmation", prompt = destination .. " already exists" })

          if response == "Yes" then
            utils.notify(string.format("Will replace %q.", destination))
            replace = true
          elseif response == "Rename" then
            local name = ui.input({ prompt = "New name: ", default = node_to_paste.name })
            if not name then
              utils.notify(string.format("No new name given, not pasting item %q to %q.", node_to_paste.name, destination))
              skip = true
            else
              destination = utils.join_path(dir, name)
              log.debug("new destination=%q", destination)
            end
          else
            utils.notify(string.format("Skipping item %q.", node_to_paste.path))
            skip = true
          end
        end

        if not skip then
          items[#items + 1] = { node = node_to_paste, destination = destination, replace = replace }
        end
      end
    end
    return items
  end

  -- paste can only be done into directories
  if not node:is_directory() then
    node = node.parent --[[@as Yat.Node]]
  end

  if #M.queue > 0 then
    local nodes = get_nodes_to_paste(node.path, M.queue)
    local pasted = false
    tree.focus_path_on_fs_event = "expand"
    for _, item in ipairs(nodes) do
      local ok = false
      if item.node:clipboard_status() == "copy" then
        if item.node:is_directory() then
          ok = fs.copy_dir(item.node.path, item.destination, item.replace)
        elseif item.node:is_file() then
          ok = fs.copy_file(item.node.path, item.destination, item.replace)
        end
      elseif item.node:clipboard_status() == "cut" then
        ok = fs.rename(item.node.path, item.destination)
      end

      if ok then
        local copy_or_move = item.node:clipboard_status() == "copy" and "Copied" or "Moved"
        utils.notify(string.format("%s %q to %q.", copy_or_move, item.node.path, item.destination))
      else
        local copy_or_move = item.node:clipboard_status() == "copy" and "copy" or "move"
        utils.warn(string.format("Failed to %s %q to %q!", copy_or_move, item.node.path, item.destination))
      end
      pasted = ok or pasted
    end
    if pasted then
      clear_clipboard()
    end
  else
    utils.notify("Nothing in clipboard")
  end
end

---@async
---@param sidebar Yat.Sidebar
function M.clear_clipboard(_, _, sidebar)
  clear_clipboard()
  sidebar:update()
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
