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

---@alias cmd_mode "edit"|"vsplit"|"split"|"tabnew"

function M.open()
  local nodes = ui.get_selected_nodes()
  if #nodes == 1 and nodes[1]:is_directory() then
    lib.toggle_directory(nodes[1])
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
    ---@type boolean
    local already_loaded = vim.fn.bufloaded(node.path) > 0
    ui.open_file(node.path, "edit")

    -- taken from nvim-tree
    if not already_loaded then
      local bufnr = api.nvim_get_current_buf()
      vim.bo.bufhidden = "delete"
      local group = api.nvim_create_augroup("RemoveBufHidden", { clear = true })
      api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
        group = group,
        buffer = bufnr,
        once = true,
        callback = function()
          vim.bo.bufhidden = ""
        end,
      })
    end

    ui.focus()
  end
end

---@param node YaTreeNode
function M.tabnew(node)
  if node:is_file() then
    ui.open_file(node.path, "tabnew")
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
        return
      elseif fs.exists(path) then
        utils.warn(string.format("%q already exists!", path))
        return
      end

      local is_directory = vim.endswith(path, utils.os_sep)
      if is_directory then
        path = path:sub(1, -2)
      end

      local ok = is_directory and fs.create_dir(path) or fs.create_file(path)
      if ok then
        utils.notify(string.format("Created %s %q.", is_directory and "directory" or "file", path))
        lib.refresh_tree(path)
      else
        utils.warn(string.format("Failed to create %s %q!", is_directory and "directory" or "file", path))
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
      return
    elseif fs.exists(path) then
      utils.warn(string.format("%q already exists!", path))
      return
    end

    if fs.rename(node.path, path) then
      utils.notify(string.format("Renamed %q to %q.", node.path, path))
      lib.refresh_tree(path)
    else
      utils.warn(string.format("Failed to rename %q to %q!", node.path, path))
    end
  end)
end

---@return YaTreeNode[]? nodes, string common_parent
local function get_nodes_to_delete()
  local nodes = ui.get_selected_nodes()

  ---@type string[]
  local parents = {}
  for _, node in ipairs(nodes) do
    -- prohibit deleting the root node
    if lib.is_node_root(node) then
      utils.warn(string.format("Path %q is the root of the tree, aborting!", node.path))
      return
    end

    if node.parent then
      parents[#parents + 1] = node.parent.path
    end
  end
  local common_parent = utils.find_common_ancestor(parents) or nodes[1].path

  return nodes, common_parent
end

---@async
---@param node YaTreeNode
---@return boolean
local function delete_node(node)
  local response = ui.select({ "Yes", "No" }, { prompt = "Delete " .. node.path .. "?" })
  if response == "Yes" then
    local ok = node:is_directory() and fs.remove_dir(node.path) or fs.remove_file(node.path)
    if ok then
      utils.notify(string.format("Deleted %q.", node.path))
    else
      utils.warn(string.format("Failed to delete %q!", node.path))
    end
    return true
  else
    return false
  end
end

function M.delete()
  local nodes, common_parent = get_nodes_to_delete()
  if not nodes then
    return
  end

  async.void(function()
    local refresh = false
    for _, node in ipairs(nodes) do
      refresh = delete_node(node) or refresh
      scheduler()
    end
    if refresh then
      lib.refresh_tree(common_parent)
    end
  end)()
end

function M.trash()
  local config = require("ya-tree.config").config
  if not config.trash.enable then
    return
  end

  local nodes, common_parent = get_nodes_to_delete()
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
        scheduler()
      end
    else
      ---@param n YaTreeNode
      files = vim.tbl_map(function(n)
        return n.path
      end, nodes)
    end

    if #files > 0 then
      log.debug("trashing files %s", files)
      job.run({ cmd = "trash", args = files, wrap_callback = true }, function(code, _, stderr)
        if code == 0 then
          lib.refresh_tree(common_parent)
        else
          log.error("%q with args %s failed with code %s and message %s", "trash", files, code, stderr)
          utils.warn(string.format("Failed to trash some of the files:\n%s\n\nMessage:\n%s", table.concat(files, "\n"), stderr))
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
      log.error("%q with args %s failed with code %s and message %s", config.system_open.cmd, args, code, stderr)
      utils.warn(string.format("%q returned error code %q and message:\n\n%s", config.system_open.cmd, code, stderr))
    end
  end)
end

function M.goto_path_in_tree()
  local input = Input:new({ prompt = "Path:", completion = "file_in_path" }, {
    on_submit = function(path)
      if path then
        lib.goto_path_in_tree(path)
      end
    end,
  })
  input:open()
end

return M
