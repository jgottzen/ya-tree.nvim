local async = require("plenary.async")
local scheduler = require("plenary.async.util").scheduler

local config = require("ya-tree.config").config
local lib = require("ya-tree.lib")
local job = require("ya-tree.job")
local fs = require("ya-tree.filesystem")
local ui = require("ya-tree.ui")
local Input = require("ya-tree.ui.input")
local utils = require("ya-tree.utils")
local log = require("ya-tree.log")

local fn = vim.fn

local M = {}

---@alias cmdmode "'edit'"|"'vsplit'"|"'split'"

---@param node YaTreeNode
---@param cmd cmdmode
local function open_file(node, cmd)
  ui.open_file(node.path, cmd)
end

---@param node YaTreeNode
function M.open(node)
  if not node then
    return
  end

  if node:is_file() then
    open_file(node, "edit")
  else
    lib.toggle_directory(node)
  end
end

---@param node YaTreeNode
function M.vsplit(node)
  if not node then
    return
  end

  if node:is_file() then
    open_file(node, "vsplit")
  end
end

---@param node YaTreeNode
function M.split(node)
  if not node then
    return
  end

  if node:is_file() then
    open_file(node, "split")
  end
end

function M.preview()
  local nodes = ui.get_selected_nodes()
  for _, node in ipairs(nodes) do
    if node:is_file() then
      open_file(node, "edit")
    end
  end
  lib.open({ focus = true })
end

---@param node YaTreeNode
function M.add(node)
  if not node then
    return
  end

  if node:is_file() then
    node = node.parent
  end

  async.run(function()
    scheduler()

    ---@type string
    local prompt = "New file (an ending " .. utils.os_sep .. " will create a directory):"
    local input = Input:new({ title = prompt, width = #prompt + 4 }, {
      ---@param name string
      on_submit = function(name)
        vim.schedule(function()
          ui.reset_window()

          if not name then
            utils.notify("No name given, not creating new file/directory")
            return
          end

          local new_path = utils.join_path(node.path, name)

          if vim.endswith(new_path, utils.os_sep) then
            new_path = new_path:sub(1, -2)
            if fs.exists(new_path) then
              utils.warn(string.format("%q already exists!", new_path))
              return
            end

            if fs.create_dir(new_path) then
              utils.notify(string.format("Created directory %q", new_path))
              lib.refresh_and_navigate(new_path)
            else
              utils.warn(string.format("Failed to create directory %q", new_path))
            end
          else
            if fs.exists(new_path) then
              utils.warn(string.format("%q already exists!", new_path))
              return
            end

            if fs.create_file(new_path) then
              utils.notify(string.format("Created file %q", new_path))
              lib.refresh_and_navigate(new_path)
            else
              utils.warn(string.format("Failed to create file %q", new_path))
            end
          end
        end)
      end,
    })
    input:open()
  end)
end

---@param node YaTreeNode
function M.rename(node)
  if not node then
    return
  end

  -- prohibit renaming the root node
  if lib.is_node_root(node) then
    return
  end

  async.run(function()
    scheduler()

    local name = ui.input({ prompt = "New name:", default = node.name })
    if not name then
      utils.notify('No new name given, not renaming file "' .. node.name .. '"')
      return
    end

    local new_name = utils.join_path(node.parent.path, name)
    if fs.rename(node.path, new_name) then
      utils.notify(string.format("Renamed %q to %q", node.path, new_name))
      lib.refresh_and_navigate(new_name)
    else
      utils.warn(string.format("Failed to rename %q to %q", node.path, new_name))
    end
  end)
end

---@return YaTreeNode[], YaTreeNode
local function get_nodes_to_delete()
  local nodes = ui.get_selected_nodes()

  ---@type table<string, YaTreeNode>
  local parents_map = {}
  for _, node in ipairs(nodes) do
    -- prohibit deleting the root node
    if lib.is_node_root(node) then
      utils.warn(string.format("path %s is the root of the tree, aborting.", node.path))
      return
    end

    -- if this node is a parent of one of the nodes to delete,
    -- remove it from the list
    parents_map[node.path] = nil
    if node.parent then
      parents_map[node.parent.path] = node.parent
    end
  end
  ---@type YaTreeNode[]
  local parents = vim.tbl_values(parents_map)
  table.sort(parents, function(a, b)
    return a.path < b.path
  end)

  return nodes, parents[1]
end

---@param node YaTreeNode
local function delete_node(node)
  local response = ui.select({ "Yes", "No" }, { prompt = "Delete " .. node.path .. "?" })
  if response == "Yes" then
    local ok
    if node:is_directory() then
      ok = fs.remove_dir(node.path)
    else
      ok = fs.remove_file(node.path)
    end

    if ok then
      utils.notify("Deleted " .. node.path)
    else
      utils.warn("Failed to delete " .. node.path)
    end
  end

  vim.schedule(function()
    ui.reset_window()
  end)
end

function M.delete()
  local nodes, selected_node = get_nodes_to_delete()
  if not nodes then
    return
  end

  async.run(function()
    scheduler()

    for _, node in ipairs(nodes) do
      delete_node(node)
    end

    lib.refresh(selected_node)
  end)
end

function M.trash()
  if not config.trash.enable then
    return
  end

  local nodes, selected_node = get_nodes_to_delete()
  if not nodes then
    return
  end

  async.run(function()
    scheduler()

    ---@type string[]
    local files = {}
    if config.trash.require_confirm then
      for _, node in ipairs(nodes) do
        local response = ui.select({ "Yes", "No" }, { prompt = "Trash " .. node.path .. "?" })
        if response == "Yes" then
          files[#files + 1] = node.path
        end
      end
    else
      files = vim.tbl_map(function(n)
        return n.path
      end, nodes)
    end

    scheduler()

    if #files > 0 then
      log.debug("trashing files %s", files)
      job.run({ cmd = "trash", args = files }, function(code, _, error)
        vim.schedule(function()
          if code == 0 then
            lib.refresh(selected_node)
          else
            utils.warn(string.format("Failed to trash some of the files %s, %s", table.concat(files, ", "), error))
          end
        end)
      end)
    end
  end)
end

function M.setup()
  if config.trash.enable and fn.executable("trash") == 0 then
    utils.notify("trash is not in the PATH. Disabling 'trash.enable' in the config")
    config.trash.enable = false
  end
end

return M
