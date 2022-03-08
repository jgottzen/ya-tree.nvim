local async = require("plenary.async")
local scheduler = require("plenary.async.util").scheduler

local lib = require("ya-tree.lib")
local job = require("ya-tree.job")
local fs = require("ya-tree.filesystem")
local ui = require("ya-tree.ui")
local utils = require("ya-tree.utils")
local log = require("ya-tree.log")

local api = vim.api
local fn = vim.fn

local M = {}

local function open_file(node, mode, config)
  local edit_winid = ui.get_edit_winid()
  log.debug(
    "open_file: edit_winid=%s, current_winid=%s, ui_winid=%s",
    edit_winid,
    api.nvim_get_current_win(),
    require("ya-tree.ui.view").winid()
  )
  if not edit_winid then
    -- only the tree window is open, i.e. netrw replacement
    -- create a new window for buffers
    local position = config.view.side == "left" and "belowright" or "aboveleft"
    local current_winid = api.nvim_get_current_win()
    vim.cmd(position .. " vsp")
    edit_winid = api.nvim_get_current_win()
    ui.set_edit_winid(edit_winid)
    ui.resize(current_winid)
    if mode == "split" or mode == "vsplit" then
      mode = "edit"
    end
  end

  api.nvim_set_current_win(edit_winid)
  vim.cmd(mode .. " " .. fn.fnameescape(node.path))
end

function M.open(node, config)
  if node:is_file() then
    open_file(node, "edit", config)
  else
    lib.toggle_directory(node)
  end
end

function M.vsplit(node, config)
  if node:is_file() then
    open_file(node, "vsplit", config)
  end
end

function M.split(node, config)
  if node:is_file() then
    open_file(node, "split", config)
  end
end

function M.preview(node, config)
  if node:is_file() then
    open_file(node, "edit", config)
    lib.focus()
  end
end

function M.add(node, _)
  async.run(function()
    scheduler()

    if node:is_file() then
      node = node.parent
    end

    local name = ui.input({ prompt = "Create new file (an ending " .. utils.os_sep .. " will create a directory):" })
    if not name then
      utils.print("No name given, not creating new file/directory")
      return
    end
    local new_path = utils.join_path(node.path, name)

    if vim.endswith(new_path, utils.os_sep) then
      new_path = new_path:sub(1, -2)
      if fs.exists(new_path) then
        utils.print_error(string.format("%q already exists!", new_path))
        return
      end

      if fs.create_dir(new_path) then
        utils.print(string.format("Created directory %q", new_path))
        lib.refresh_and_navigate(new_path)
      else
        utils.print_error(string.format("Failed to create directory %q", new_path))
      end
    else
      if fs.exists(new_path) then
        utils.print_error(string.format("%q already exists!", new_path))
        return
      end

      if fs.create_file(new_path) then
        utils.print(string.format("Created file %q", new_path))
        lib.refresh_and_navigate(new_path)
      else
        utils.print_error(string.format("Failed to create file %q", new_path))
      end
    end
  end)
end

function M.rename(node, _)
  -- prohibit renaming the root node
  if lib.is_node_root(node) then
    return
  end

  async.run(function()
    scheduler()

    local name = ui.input({ prompt = "New name:", default = node.name })
    if not name then
      utils.print('No new name given, not renaming file "' .. node.name .. '"')
      return
    end

    local new_name = utils.join_path(node.parent.path, name)
    if fs.rename(node.path, new_name) then
      utils.print(string.format("Renamed %q to %q", node.path, new_name))
      lib.refresh_and_navigate(new_name)
    else
      utils.print_error(string.format("Failed to rename %q to %q", node.path, new_name))
    end
  end)
end

local function get_nodes_to_delete(node)
  local nodes = {}
  local mode = api.nvim_get_mode().mode
  if mode == "v" or mode == "V" then
    nodes = ui.get_selected_nodes()
    utils.feed_esc()
  else
    nodes = { node }
  end

  local parents = {}
  for _, v in ipairs(nodes) do
    -- prohibit deleting the root node
    if lib.is_node_root(v) then
      utils.print_error(string.format("path %s is the root of the tree, aborting.", v.path))
      return
    end

    -- if this node is a parent of one of the nodes to delete,
    -- remove it from the list
    parents[v.path] = nil
    if v.parent then
      parents[v.parent.path] = v.parent
    end
  end
  table.sort(vim.tbl_values(parents), function(a, b)
    return a.path < b.path
  end)

  return nodes, parents[1]
end

local function delete_node(node)
  local response = ui.input({ prompt = "Delete " .. node.path .. "? y/N:" })
  if response and response:match("^[yY]") then
    local ok
    if node:is_directory() then
      ok = fs.remove_dir(node.path)
    else
      ok = fs.remove_file(node.path)
    end

    if ok then
      utils.print("Deleted " .. node.path)
    else
      utils.print_error("Failed to delete " .. node.path)
    end
  end
end

function M.delete(node, _)
  local nodes, selected_node = get_nodes_to_delete(node)
  if not nodes then
    return
  end

  async.run(function()
    scheduler()

    for _, v in ipairs(nodes) do
      delete_node(v)
    end

    lib.refresh(selected_node)
  end)
end

function M.trash(node, config)
  if not M.trash.enabled then
    return
  end

  local nodes, selected_node = get_nodes_to_delete(node)
  if not nodes then
    return
  end

  async.run(function()
    scheduler()

    local files = {}
    if config.trash.require_confirm then
      for _, v in ipairs(nodes) do
        local response = ui.input({ prompt = "Trash " .. v.path .. "? y/N:" })
        if response and response:match("^[yY]") then
          files[#files + 1] = v.path
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
        if code == 0 then
          lib.refresh(selected_node)
        else
          vim.schedule(function()
            utils.print_error(string.format("Failed to trash some of the files %s, %s", table.concat(files, ", "), error))
          end)
        end
      end)
    end
  end)
end

function M.setup()
  M.trash = {
    enabled = fn.executable("trash") == 1,
  }
end

return M
