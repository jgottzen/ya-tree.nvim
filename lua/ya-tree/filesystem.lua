local bit = require("plenary.bit")
local uv = require("plenary.async").uv
local Path = require("plenary.path")

local utils = require("ya-tree.utils")

local loop = vim.loop

local os_sep = Path.path.sep

local M = {}

---@async
---@param path string
---@return boolean is_directory
function M.is_directory(path)
  ---@type userdata, uv_fs_stat
  local _, stat = uv.fs_stat(path)
  return stat and stat.type == "directory" or false
end

---@async
---@param path string
---@return uv_fs_stat|nil stat
function M.lstat(path)
  ---@type userdata, uv_fs_stat?
  local _, stat = uv.fs_lstat(path)
  return stat
end

---@async
---@param path string
---@return boolean empty
local function is_empty(path)
  local _, handle = uv.fs_scandir(path)
  return handle and loop.fs_scandir_next(handle) == nil or false
end

-- types defined by luv are:
-- file, directory, link, fifo, socket, char, block and unknown
-- see: https://github.com/luvit/luv/blob/d2e235503f6cb5c86121cd70cdb5d17e368bab03/src/fs.c#L107=

---@alias Luv.FileType "directory" | "file" | "fifo" | "socket" | "char" | "block"

---@class uv_timespec
---@field sec integer
---@field nsec integer

---@class uv_fs_stat
---@field dev integer
---@field mode integer
---@field nlink integer
---@field uid integer
---@field gid integer
---@field rdev integer
---@field ino integer
---@field size integer
---@field blksize integer
---@field blocks integer
---@field flags integer
---@field gen integer
---@field atime uv_timespec
---@field mtime uv_timespec
---@field ctime uv_timespec
---@field birthtime uv_timespec
---@field type Luv.FileType|"unknown"

---@class Yat.Fs.Node
---@field public name string
---@field public type Luv.FileType
---@field public path string

---@class Yat.Fs.DirectoryNode : Yat.Fs.Node
---@field public empty boolean

---Creates a directory node
---@async
---@param dir string the directory containing the directory
---@param name string the name of the directory
---@return Yat.Fs.DirectoryNode node
local function directory_node(dir, name)
  local path = utils.join_path(dir, name)
  local empty = is_empty(path)

  return {
    name = name,
    type = "directory",
    path = path,
    empty = empty,
  }
end

M.st_mode_masks = {
  executable = 0x49, -- octal 111, corresponding to S_IXUSR, S_IXGRP and S_IXOTH
  permissions_mask = 0x7, -- octal 7, corresponding to S_IRWX
}

---@class Yat.Fs.FileNode : Yat.Fs.Node
---@field public extension string
---@field public executable boolean

---Creates a file node
---@async
---@param dir string the directory containing the file
---@param name string the name of the file
---@param stat? uv_fs_stat
---@return Yat.Fs.FileNode node
local function file_node(dir, name, stat)
  local path = utils.join_path(dir, name)
  local extension = name:match(".?[^.]+%.(.*)") or ""
  local executable
  if utils.is_windows then
    executable = utils.is_windows_exe(extension)
  else
    if not stat then
      local _
      ---@type userdata, uv_fs_stat
      _, stat = uv.fs_lstat(path)
    end
    executable = bit.band(M.st_mode_masks.executable, stat.mode) > 1
  end

  return {
    name = name,
    type = "file",
    path = path,
    extension = extension,
    executable = executable,
  }
end

---@param path string
---@return string name
function M.get_file_name(path)
  if path:sub(-1) == os_sep then
    path = path:sub(1, -2)
  end
  local splits = vim.split(path, os_sep, { plain = true }) --[=[@as string[]]=]
  return splits[#splits]
end

---@class Yat.Fs.FifoNode : Yat.Fs.FileNode, Yat.Fs.Node

---@async
---@param dir string the directory containing the fifo
---@param name string name of the fifo
---@param stat? uv_fs_stat
---@return Yat.Fs.FifoNode node
local function fifo_node(dir, name, stat)
  local node = file_node(dir, name, stat)
  node.type = "fifo"
  return node --[[@as Yat.Fs.FifoNode]]
end

---@class Yat.Fs.SocketNode : Yat.Fs.FileNode, Yat.Fs.Node

---@async
---@param dir string the directory containing the socket
---@param name string name of the socket
---@param stat? uv_fs_stat
---@return Yat.Fs.SocketNode node
local function socket_node(dir, name, stat)
  local node = file_node(dir, name, stat)
  node.type = "socket"
  return node --[[@as Yat.Fs.SocketNode]]
end

---@class Yat.Fs.CharNode : Yat.Fs.FileNode, Yat.Fs.Node

---@async
---@param dir string the directory containing the char device file
---@param name string name of the char device file
---@param stat? uv_fs_stat
---@return Yat.Fs.CharNode node
local function char_node(dir, name, stat)
  local node = file_node(dir, name, stat)
  node.type = "char"
  return node --[[@as Yat.Fs.CharNode]]
end

---@class Yat.Fs.BlockNode : Yat.Fs.FileNode, Yat.Fs.Node

---@async
---@param dir string the directory containing the block device file
---@param name string name of the block device file
---@param stat? uv_fs_stat
---@return Yat.Fs.BlockNode node
local function block_node(dir, name, stat)
  local node = file_node(dir, name, stat)
  node.type = "block"
  return node --[[@as Yat.Fs.BlockNode]]
end

---@class Yat.Fs.LinkNodeMixin
---@field public link boolean
---@field public absolute_link_to string
---@field public relative_link_to string
---@field public link_orphan boolean

---@class Yat.Fs.DirectoryLinkNode : Yat.Fs.DirectoryNode, Yat.Fs.LinkNodeMixin, Yat.Fs.Node

---@class Yat.Fs.FileLinkNode : Yat.Fs.FileNode, Yat.Fs.LinkNodeMixin, Yat.Fs.Node
---@field public link_name string
---@field public link_extension string

---@async
---@param dir string the directory containing the link
---@param name string name of the link
---@param lstat? uv_fs_stat
---@return Yat.Fs.DirectoryLinkNode|Yat.Fs.FileLinkNode|nil node
local function link_node(dir, name, lstat)
  local path = utils.join_path(dir, name)
  local rel_link_to
  ---@type userdata, string
  local _, abs_link_to = uv.fs_readlink(path)
  if not abs_link_to or not utils.is_absolute_path(abs_link_to) then
    rel_link_to = abs_link_to
    abs_link_to = dir .. os_sep .. abs_link_to
  else
    rel_link_to = Path:new(abs_link_to):make_relative(dir) --[[@as string]]
  end

  -- stat here is for the target of the link
  ---@type userdata, uv_fs_stat?
  local _, stat = uv.fs_stat(path)
  local node
  if stat then
    local _type = stat.type
    if _type == "directory" then
      node = directory_node(dir, name)
    elseif _type == "file" or _type == "fifo" or _type == "socket" or _type == "char" or _type == "block" then
      local link_name = M.get_file_name(abs_link_to)
      local link_extension = link_name:match(".?[^.]+%.(.*)") or "" --[[@as string]]

      node = file_node(dir, name, stat)
      node.link_name = link_name
      node.link_extension = link_extension
      node.type = _type
    else
      -- "link" or "unknown"
      return nil
    end

    node.link_orphan = false
  else
    -- the link is orphaned
    node = file_node(dir, name, lstat)
    node.link_orphan = true
  end

  ---@cast node Yat.Fs.DirectoryLinkNode|Yat.Fs.FileLinkNode
  node.link = true
  node.absolute_link_to = abs_link_to
  node.relative_link_to = rel_link_to
  return node
end

---@async
---@param path string
---@return Yat.Fs.Node|nil node
function M.node_for(path)
  local p = Path:new(path)
  path = p:absolute() --[[@as string]]
  -- in case of a link, fs_lstat returns info about the link itself instead of the file it refers to
  ---@type userdata, uv_fs_stat?
  local _, lstat = uv.fs_lstat(path)
  if not lstat then
    return nil
  end

  local parent_path = p:parent():absolute() --[[@as string]]
  local name = M.get_file_name(path)
  if lstat.type == "directory" then
    return directory_node(parent_path, name)
  elseif lstat.type == "file" then
    return file_node(parent_path, name, lstat)
  elseif lstat.type == "link" then
    return link_node(parent_path, name, lstat)
  elseif lstat.type == "fifo" then
    return fifo_node(parent_path, name, lstat)
  elseif lstat.type == "socket" then
    return socket_node(parent_path, name, lstat)
  elseif lstat.type == "char" then
    return char_node(parent_path, name, lstat)
  elseif lstat.type == "block" then
    return block_node(parent_path, name, lstat)
  else
    -- "unknown"
    return nil
  end
end

---Scans a directory and returns an array of items extending `Yat.Fs.Node`.
---@async
---@param dir string the directory to scan.
---@return Yat.Fs.Node[] nodes
function M.scan_dir(dir)
  dir = Path:new(dir):absolute() --[[@as string]]
  ---@type Yat.Fs.Node[]
  local nodes = {}
  local _, fd = uv.fs_scandir(dir)
  if fd then
    while true do
      ---@type string?, Luv.FileType?
      local name, _type = loop.fs_scandir_next(fd)
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
      elseif _type == "fifo" then
        node = fifo_node(dir, name)
      elseif _type == "socket" then
        node = socket_node(dir, name)
      elseif _type == "char" then
        node = char_node(dir, name)
      elseif _type == "block" then
        node = block_node(dir, name)
      end
      if node then
        nodes[#nodes + 1] = node
      end
    end
  end

  return nodes
end

---@async
---@param path string
---@return boolean whether the path exists.
function M.exists(path)
  -- must use fs_lstat since fs_stat fails on a orphaned links
  local _, stat = uv.fs_lstat(path)
  return stat ~= nil
end

---Recursively copy a directory.
---@async
---@param source string|string[] source path.
---@param destination string|string[] destination path.
---@param replace boolean whether to replace existing files.
---@return boolean success success or not
function M.copy_dir(source, destination, replace)
  local source_path = Path:new(source)
  local destination_path = Path:new(destination)

  local _, fd = uv.fs_scandir(source_path:absolute())
  if not fd then
    return false
  end

  ---@type userdata, uv_fs_stat
  local _, stat = uv.fs_stat(source_path:absolute())
  local mode = stat.mode
  local continue = replace
  if not continue then
    -- fs_mkdir returns nil if dir alrady exists
    _, continue = uv.fs_mkdir(destination_path:absolute(), mode)
  end
  if continue then
    while true do
      ---@type string?, Luv.FileType
      local name, _type = loop.fs_scandir_next(fd)
      if not name then
        break
      end

      if _type == "directory" then
        if not M.copy_dir({ source_path, name }, { destination_path, name }, false) then
          return false
        end
      else
        if not M.copy_file({ source_path, name }, { destination_path, name }, false) then
          return false
        end
      end
    end
  else
    return false
  end

  return true
end

---Copy a file.
---@async
---@param source string|string[] source path.
---@param destination string|string[] destination path.
---@param replace boolean whether to replace an existing file.
---@return boolean success success or not.
function M.copy_file(source, destination, replace)
  local _, success = uv.fs_copyfile(Path:new(source):absolute(), Path:new(destination):absolute(), { excl = not replace })
  return success == true
end

---Rename file or directory.
---@async
---@param old string old name.
---@param new string new name.
---@return boolean success success or not.
function M.rename(old, new)
  local _, success = uv.fs_rename(Path:new(old):absolute(), Path:new(new):absolute())
  return success == true
end

---Create a directory.
---@async
---@param path string the directory to create
---@return boolean success success or not.
function M.create_dir(path)
  local mode = 493 -- 755 in octal
  -- fs_mkdir returns nil if the path already exists, or if the path has parent
  -- directories that has to be created as well
  local abs_path = Path:new(path):absolute() --[[@as string]]
  local _, success = uv.fs_mkdir(abs_path, mode)
  if not success and not M.exists(abs_path) then
    local dirs = vim.split(abs_path, os_sep, { plain = true }) --[=[@as string[]]=]
    local acc = ""
    for _, dir in ipairs(dirs) do
      local current = utils.join_path(acc, dir)
      ---@type userdata, uv_fs_stat?
      local _, stat = uv.fs_stat(current)
      if stat then
        if stat.type == "directory" then
          acc = current
        else
          return false
        end
      else
        _, success = uv.fs_mkdir(current, mode)
        if not success then
          return false
        end
        acc = current
      end
    end
  end

  return true
end

---Create a new file.
---@async
---@param file string path.
---@return boolean sucess success or not.
function M.create_file(file)
  local path = Path:new(file)

  if M.create_dir(path:parent()) then
    local _, fd = uv.fs_open(file, "w", 420) -- 644 in octal
    if not fd then
      return false
    else
      local _, success = uv.fs_close(fd)
      return success == true
    end
  else
    return false
  end
end

---Recusively remove a directory.
---@async
---@param path string the path to remove.
---@return boolean success success or not.
function M.remove_dir(path)
  local _, fd = uv.fs_scandir(path)
  if not fd then
    return false
  end

  while true do
    ---@type string?, Luv.FileType
    local name, _type = loop.fs_scandir_next(fd)
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

  local _, success = uv.fs_rmdir(path)
  return success == true
end

---Remove a file.
---@async
---@param path string the path to remove.
---@return boolean success success or not.
function M.remove_file(path)
  local _, success = uv.fs_unlink(path)
  return success == true
end

return M
