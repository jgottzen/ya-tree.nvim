local async = require("plenary.async")
local scheduler = require("plenary.async.util").scheduler

local lib = require("ya-tree.lib")
local job = require("ya-tree.job")
local fs = require("ya-tree.filesystem")
local ui = require("ya-tree.ui")
local Input = require("ya-tree.ui.input")
local utils = require("ya-tree.utils")
local log = require("ya-tree.log")

local api = vim.api

local M = {}

---@alias cmdmode "edit"|"vsplit"|"split"

---@param node YaTreeNode
function M.open(node)
  if not node then
    return
  end

  if node:is_file() then
    ui.open_file(node.path, "edit")
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
    ui.open_file(node.path, "vsplit")
  end
end

---@param node YaTreeNode
function M.split(node)
  if not node then
    return
  end

  if node:is_file() then
    ui.open_file(node.path, "split")
  end
end

---@param node YaTreeNode
function M.preview(node)
  if node:is_file() then
    local already_loaded = vim.fn.bufloaded(node.path) > 0
    ui.open_file(node.path, "edit")

    -- taken from nvim-tree
    if not already_loaded then
      local bufnr = api.nvim_get_current_buf()
      api.nvim_buf_set_option(bufnr, "bufhidden", "delete")
      local group = api.nvim_create_augroup("RemoveBufHidden", { clear = true })
      api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
        group = group,
        buffer = bufnr,
        command = "setlocal bufhidden= | autocmd! RemoveBufHidden",
      })
    end

    ui.focus()
  end
end

---@param node YaTreeNode
function M.add(node)
  if not node then
    return
  end

  if node:is_file() then
    node = node.parent
  end

  ---@type string
  local prompt = "New file (an ending " .. utils.os_sep .. " will create a directory):"
  local input = Input:new({ title = prompt, width = #prompt + 4 }, {
    ---@param name string
    on_submit = function(name)
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
    end,
  })
  input:open()
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

  vim.ui.input({ prompt = "New name:", default = node.name }, function(name)
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
end

function M.delete()
  local nodes, selected_node = get_nodes_to_delete()
  if not nodes then
    return
  end

  async.void(function()
    scheduler()

    for _, node in ipairs(nodes) do
      delete_node(node)
      scheduler()
    end

    lib.refresh(selected_node)
  end)()
end

---@param _ YaTreeNode
function M.trash(_)
  local config = require("ya-tree.config").config
  if not config.trash.enable then
    return
  end

  local nodes, selected_node = get_nodes_to_delete()
  if not nodes then
    return
  end

  async.void(function()
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
      job.run({ cmd = "trash", args = files, wrap_callback = true }, function(code, _, stderr)
        if code == 0 then
          lib.refresh(selected_node)
        else
          stderr = vim.split(stderr or "", "\n", { plain = true, trimempty = true })
          stderr = table.concat(stderr, " ")
          utils.warn(string.format("Failed to trash some of the files %s, %s", table.concat(files, ", "), stderr))
        end
      end)
    end
  end)()
end

return M
