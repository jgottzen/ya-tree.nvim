local Path = require("plenary.path")

local utils = require("ya-tree.utils")
local log = require("ya-tree.log")

local vim = vim
local uv = vim.loop

local M = {}

--- creates a directory node
---@param cwd string the directory containing the directory
---@param name string the name of the directory
---@return table { name: string, type: string, path: string, empty: boolean }
local function directory_node(cwd, name)
  local path = utils.join_path(cwd, name)
  local handle = uv.fs_scandir(path)
  local empty = handle and uv.fs_scandir_next(handle) == nil or false

  return {
    name = name,
    type = "directory",
    path = path,
    empty = empty,
  }
end

--- creates a file node
---@param cwd string the directory containing the file
---@param name string the name of the file
---@return table { name: string, type: string, path: string, extension: string, executable: boolean }
local function file_node(cwd, name)
  local path = utils.join_path(cwd, name)
  local extension = string.match(name, ".?[^.]+%.(.*)") or ""
  local executable
  if utils.is_windows then
    executable = utils.is_windows_exe(extension)
  else
    executable = uv.fs_access(path, "X")
  end

  return {
    name = name,
    type = "file",
    path = path,
    extension = extension,
    executable = executable,
  }
end

---@param cwd string the directory containing the link
---@param name string name of the link
---@return table { name: string, type: string, link: boolean, path: string, link_to: string, empty: boolean, link_name: string, link_extension: string, extension: string, executable: boolean }
local function link_node(cwd, name)
  local path = utils.join_path(cwd, name)
  local link_to = uv.fs_realpath(path)
  if not link_to then
    -- don't create nodes for links that have no target
    return nil
  end

  local stat = uv.fs_stat(path)
  local p = Path:new(link_to)
  link_to = Path:new(link_to):make_relative()

  local nodedata
  if stat and stat.type == "directory" then
    local handle = uv.fs_scandir(path)
    local empty = handle and uv.fs_scandir_next(handle) == nil

    nodedata = {
      name = name,
      type = "directory",
      link = true,
      path = path,
      link_to = link_to,
      empty = empty,
    }
  elseif stat and stat.type == "file" then
    local extension = string.match(name, ".?[^.]+%.(.*)") or ""
    local _, pos = p.filename:find(p:parent().filename, 1, true)
    local link_name = p.filename:sub(pos + 2)
    local link_extension = string.match(link_name, ".?[^.]+%.(.*)") or ""
    local executable
    if utils.is_windows then
      executable = utils.is_windows_exe(extension)
    else
      executable = uv.fs_access(path, "X")
    end

    nodedata = {
      name = name,
      type = "file",
      link = true,
      path = path,
      link_to = link_to,
      link_name = link_name,
      link_extension = link_extension,
      extension = extension,
      executable = executable,
    }
  end

  return nodedata
end

function M.file_item_sorter(a, b)
  if a.type == b.type then
    return a.path < b.path
  else
    return a.type < b.type
  end
end

function M.node_for(path)
  local stat = uv.fs_stat(path)
  local _type = stat and stat.type or nil
  if not _type then
    utils.print_error("cannot determine type for path " .. path)
    return
  end

  local p = Path:new(path)
  local parent_path = p:parent().filename
  local _, pos = p.filename:find(parent_path, 1, true)
  local name = p.filename:sub(pos + 2)
  if _type == "directory" then
    return directory_node(parent_path, name)
  elseif _type == "file" then
    return file_node(parent_path, name)
  elseif _type == "link" then
    return link_node(parent_path, name)
  end
end

function M.scan_dir(dir)
  local nodes = {}
  local fd = uv.fs_scandir(dir)
  if fd then
    while true do
      local name, _type = uv.fs_scandir_next(fd)
      if name == nil then
        break
      end
      local node
      if _type == "directory" then
        node = directory_node(dir, name)
      elseif _type == "file" then
        node = file_node(dir, name)
      elseif _type == "link" then
        node = link_node(dir, name)
      end
      if node ~= nil then
        nodes[#nodes + 1] = node
      end
    end
  end

  table.sort(nodes, M.file_item_sorter)
  return nodes
end

function M.exists(...)
  return Path:new(...):exists()
end

function M.copy_dir(source, destination, replace)
  source = Path:new(source)
  destination = Path:new(destination)

  local fd = uv.fs_scandir(source:absolute())
  if not fd then
    return false
  end

  local mode = uv.fs_stat(source:absolute()).mode
  -- fs_mkdir returns nil if dir alrady exists
  if replace or uv.fs_mkdir(destination:absolute(), mode) then
    while true do
      local name, _type = uv.fs_scandir_next(fd)
      if not name then
        break
      end

      if _type == "directory" then
        if not M.copy_dir({ source, name }, { destination, name }) then
          return false
        end
      else
        if not M.copy_file({ source, name }, { destination, name }) then
          return false
        end
      end
    end
  else
    return false
  end
  return true
end

function M.copy_file(source, destination, override)
  source = Path:new(source)
  destination = Path:new(destination)
  log.debug("copying %s to %s", source.filename, destination.filename)
  return uv.fs_copyfile(source:absolute(), destination:absolute(), { excl = not override or false })
end

function M.rename(old, new)
  old = Path:new(old)
  new = Path:new(new)
  return uv.fs_rename(old:absolute(), new:absolute())
end

function M.create_dir(path)
  local p = Path:new(path)

  local mode = 493 -- 755 in octal
  -- fs_mkdir returns nil if the path already exists, or if the path has parent
  -- directories that has to be created as well
  if not uv.fs_mkdir(p:absolute(), mode) and not p:exists() then
    local dirs = vim.split(p:absolute(), utils.os_sep)
    local acc = ""
    for _, dir in ipairs(dirs) do
      local current = utils.join_path(acc, dir)
      local stat = uv.fs_stat(current)
      if stat then
        if stat.type == "directory" then
          acc = current
        else
          return false
        end
      else
        if not uv.fs_mkdir(current, mode) then
          return false
        end
        acc = current
      end
    end
  end

  return true
end

function M.create_file(file)
  local path = Path:new(file)

  if M.create_dir(path:parent()) then
    local fd = uv.fs_open(file, "w", 420) -- 644 in octal
    if not fd then
      return false
    else
      uv.fs_close(fd)
      return true
    end
  else
    return false
  end
end

function M.remove_dir(path)
  local fd = uv.fs_scandir(path)
  if not fd then
    return
  end

  while true do
    local name, _type = uv.fs_scandir_next(fd)
    if not name then
      break
    end
    local to_remove = utils.join_path(path, name)
    if _type == "directory" then
      if not M.remove_dir(to_remove) then
        return false
      end
    else
      if not M.remove_file(to_remove) then
        return false
      end
    end
  end

  return uv.fs_rmdir(path)
end

function M.remove_file(path)
  return uv.fs_unlink(path)
end

return M
