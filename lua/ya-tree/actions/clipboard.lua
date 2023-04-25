local lazy = require("ya-tree.lazy")

local fs = lazy.require("ya-tree.fs") ---@module "ya-tree.fs"
local Logger = lazy.require("ya-tree.log") ---@module "ya-tree.log"
local Path = lazy.require("ya-tree.path") ---@module "ya-tree.path"
local ui = lazy.require("ya-tree.ui") ---@module "ya-tree.ui"
local utils = lazy.require("ya-tree.utils") ---@module "ya-tree.utils"

local fn = vim.fn

local M = {
  ---@type Yat.Node.Filesystem[]
  queue = {},
}

---@alias Yat.Actions.Clipboard.Action "copy"|"cut"

---@param panel Yat.Panel.Files
---@param action Yat.Actions.Clipboard.Action
local function cut_or_copy_nodes(panel, action)
  for _, node in
    ipairs(panel:get_selected_nodes() --[=[@as Yat.Node.Filesystem[]]=])
  do
    -- copying the root node will not work
    if panel.root ~= node then
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
  panel:draw()
end

---@async
---@param panel Yat.Panel.Files
---@param _ Yat.Node.Filesystem
function M.copy_node(panel, _)
  if not panel:is_in_search_mode() then
    cut_or_copy_nodes(panel, "copy")
  end
end

---@async
---@param panel Yat.Panel.Files
---@param _ Yat.Node.Filesystem
function M.cut_node(panel, _)
  if not panel:is_in_search_mode() then
    cut_or_copy_nodes(panel, "cut")
  end
end

local function clear_clipboard()
  for _, item in ipairs(M.queue) do
    item:set_clipboard_status(nil)
  end
  M.queue = {}
end

---@async
---@param panel Yat.Panel.Files
---@param node Yat.Node.Filesystem
function M.paste_nodes(panel, node)
  if panel:is_in_search_mode() then
    return
  end

  ---@async
  ---@param dir string
  ---@return { node: Yat.Node.Filesystem, destination: string, replace: boolean }[]
  local function get_nodes_to_paste(dir)
    ---@type { node: Yat.Node.Filesystem, destination: string, replace: boolean }[]
    local items = {}
    for _, node_to_paste in ipairs(M.queue) do
      if not fs.exists(node_to_paste.path) then
        utils.warn(string.format("Item %q does not exist, cannot %s!", node_to_paste.path, node_to_paste:clipboard_status()))
      else
        local destination = fs.join_path(dir, node_to_paste.name)
        local skip = false
        local replace = false
        if fs.exists(destination) then
          local response = ui.select({ "Yes", "Rename", "No" }, { kind = "confirmation", prompt = destination .. " already exists" })

          if response == "Yes" then
            utils.notify(string.format("Will replace %q.", destination))
            replace = true
          elseif response == "Rename" then
            local name = ui.nui_input({ title = " New name: ", default = node_to_paste.name })
            if not name then
              utils.notify(string.format("No new name given, not pasting item %q to %q.", node_to_paste.name, destination))
              skip = true
            else
              destination = fs.join_path(dir, name)
              Logger.get("actions").debug("new destination=%q", destination)
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

  if not node:is_directory() then
    node = node.parent --[[@as Yat.Node.Filesystem]]
  end

  if #M.queue > 0 then
    local items = get_nodes_to_paste(node.path)
    local pasted = false
    panel.focus_path_on_fs_event = "expand"
    for _, item in ipairs(items) do
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
---@param panel Yat.Panel.Files
---@param _ Yat.Node.Filesystem
function M.clear_clipboard(panel, _)
  clear_clipboard()
  panel:draw()
  utils.notify("Clipboard cleared!")
end

---@param content string
local function copy_to_system_clipboard(content)
  fn.setreg("+", content)
  fn.setreg('"', content)
  utils.notify(string.format("Copied %s to system clipboad", content))
end

---@async
---@param _ Yat.Panel.Tree
---@param node Yat.Node
function M.copy_name_to_clipboard(_, node)
  copy_to_system_clipboard(node.name)
end

---@async
---@param panel Yat.Panel.Tree
---@param node Yat.Node
function M.copy_root_relative_path_to_clipboard(panel, node)
  local relative = node:relative_path_to(panel.root)
  if node:is_container() then
    relative = relative .. Path.path.sep
  end
  copy_to_system_clipboard(relative)
end

---@async
---@param _ Yat.Panel.Tree
---@param node Yat.Node
function M.copy_absolute_path_to_clipboard(_, node)
  copy_to_system_clipboard(node.path)
end

return M
