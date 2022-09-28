local scheduler = require("plenary.async.util").scheduler

local fs = require("ya-tree.filesystem")
local ui = require("ya-tree.ui")
local utils = require("ya-tree.utils")
local log = require("ya-tree.log")("actions")

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
  ---@type table<Yat.Git.Repo, boolean>
  local repos = {}

  ---@async
  ---@param dir Yat.Node
  ---@param src_node Yat.Node
  ---@return Yat.Node|nil new_node
  local function paste_node(dir, src_node)
    if not fs.exists(src_node.path) then
      utils.warn(string.format("Item %q does not exist, cannot %s!", src_node.path, src_node.clipboard_status))
      return
    end

    local destination = utils.join_path(dir.path, src_node.name)
    local replace = false
    if fs.exists(destination) then
      local response = ui.select({ "Yes", "Rename", "No" }, { kind = "confirmation", prompt = destination .. " already exists" })

      if response == "Yes" then
        utils.notify(string.format("Will replace %q.", destination))
        replace = true
      elseif response == "Rename" then
        local name = ui.input({ prompt = "New name: ", default = src_node.name })
        if not name then
          utils.notify(string.format("No new name given, not pasting item %q to %q.", src_node.name, destination))
          return
        else
          destination = utils.join_path(dir.path, name)
          log.debug("new destination=%q", destination)
        end
      else
        utils.notify(string.format("Skipping item %q.", src_node.path))
        return
      end
    end

    local new_node
    local ok = false
    if src_node.clipboard_status == "copy" then
      if src_node:is_directory() then
        ok = fs.copy_dir(src_node.path, destination, replace)
      elseif src_node:is_file() then
        ok = fs.copy_file(src_node.path, destination, replace)
      end
    elseif src_node.clipboard_status == "cut" then
      ok = fs.rename(src_node.path, destination)
      if ok then
        tree.root:remove_node(src_node.path)
        if src_node.repo then
          repos[src_node.repo] = true
        end
      end
    end

    if ok then
      utils.notify(string.format("%s %q to %q.", src_node.clipboard_status == "copy" and "Copied" or "Moved", src_node.path, destination))
      new_node = tree.root:add_node(destination)
      if new_node and new_node.repo then
        repos[new_node.repo] = true
      end
    else
      utils.warn(
        string.format("Failed to %s %q to %q!", src_node.clipboard_status == "copy" and "copy" or "move", src_node.path, destination)
      )
    end

    return new_node
  end

  -- paste can only be done into directories
  if not node:is_directory() then
    node = node.parent
    if not node then
      return
    end
  end

  if #M.queue > 0 then
    local first_node
    for _, item in ipairs(M.queue) do
      local destination_node = paste_node(node, item)
      if destination_node and not first_node then
        first_node = destination_node
      end
    end
    for repo in pairs(repos) do
      repo:refresh_status({ ignored = true })
    end
    clear_clipboard()
    -- let the event loop catch up if there was a very large amount of files pasted
    scheduler()
    tree.root:expand({ to = first_node.path })
    ui.update(tree, first_node)
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
