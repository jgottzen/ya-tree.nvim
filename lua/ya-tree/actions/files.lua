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

function M.open()
  local nodes = ui.get_selected_nodes()
  if #nodes == 1 then
    local node = nodes[1]
    if node:is_file() then
      ui.open_file(node.path, "edit")
    else
      lib.toggle_directory(node)
    end
  else
    for _, node in ipairs(nodes) do
      if node:is_file() then
        ui.open_file(node.path, "edit")
      end
    end
  end
end

---@param node YaTreeNode
function M.vsplit(node)
  if node:is_file() then
    ui.open_file(node.path, "vsplit")
  end
end

---@param node YaTreeNode
function M.split(node)
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
  if node:is_file() then
    node = node.parent
  end

  local title = "New file (an ending " .. utils.os_sep .. " will create a directory):"
  local input = Input:new({ prompt = title, default = node.path .. utils.os_sep, completion = "file", width = #title + 4 }, {
    ---@param path string
    on_submit = function(path)
      if not path then
        utils.notify("No name given, not creating new file/directory")
        return
      end

      local is_directory = vim.endswith(path, utils.os_sep)
      if is_directory then
        path = path:sub(1, -2)
      end

      if fs.exists(path) then
        utils.warn(string.format("%q already exists!", path))
        return
      end

      local ok = is_directory and fs.create_dir(path) or fs.create_file(path)
      if ok then
        utils.notify(string.format("Created %s %q", is_directory and "directory" or "file", path))
        lib.refresh_tree(path)
      else
        utils.warn(string.format("Failed to create %s %q", is_directory and "directory" or "file", path))
      end
    end,
  })
  input:open()
end

---@param node YaTreeNode
function M.rename(node)
  -- prohibit renaming the root node
  if lib.is_node_root(node) then
    return
  end

  vim.ui.input({ prompt = "New name:", default = node.path, completion = "file" }, function(path)
    if not path then
      utils.notify('No new name given, not renaming "' .. node.path .. '"')
      return
    end

    if fs.exists(path) then
      utils.warn(string.format("%q already exists!", path))
      return
    end

    if fs.rename(node.path, path) then
      utils.notify(string.format("Renamed %q to %q", node.path, path))
      lib.refresh_tree(path)
    else
      utils.warn(string.format("Failed to rename %q to %q", node.path, path))
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

    lib.refresh_tree(selected_node)
  end)()
end

function M.trash()
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
          lib.refresh_tree(selected_node)
        else
          stderr = vim.split(stderr or "", "\n", { plain = true, trimempty = true })
          stderr = table.concat(stderr, " ")
          utils.warn(string.format("Failed to trash some of the files %s, %s", table.concat(files, ", "), stderr))
        end
      end)
    end
  end)()
end

---@param node YaTreeNode
function M.system_open(node)
  local config = require("ya-tree.config").config
  if not config.system_open.cmd then
    utils.warn("No sytem open command set, or OS cannot be recognized!")
    return
  end

  local args = vim.deepcopy(config.system_open.args)
  table.insert(args, node.link_to or node.path)
  job.run({ cmd = config.system_open.cmd, args = args, detached = true, wrap_callback = true }, function(code, _, stderr)
    if code ~= 0 then
      stderr = vim.split(stderr or "", "\n", { plain = true, trimempty = true })
      stderr = table.concat(stderr, " ")
      utils.warn(string.format("%q returned error code %q and message %q", config.system_open.cmd, code, stderr))
    end
  end)
end

return M
