local bit = require("bit")
local log = require("ya-tree.log").get("fs")
local Path = require("ya-tree.path")
local utils = require("ya-tree.utils")
local wrap = require("ya-tree.async").wrap

local uv = vim.loop

local os_sep = Path.path.sep

local M = {}

-- types defined by luv are:
-- file, directory, link, fifo, socket, char, block and unknown
-- see: https://github.com/luvit/luv/blob/d2e235503f6cb5c86121cd70cdb5d17e368bab03/src/fs.c#L107=

---Excludes the link type since it's handled differently, and unknown.
---@alias Luv.FileType "directory"|"file"|"fifo"|"socket"|"char"|"block"

---@type async fun(path: string): err: string|nil, stat: uv.aliases.fs_stat_table|nil
local fs_stat = wrap(uv.fs_stat, 2, true)

---@type async fun(path: string): err: string|nil, stat: uv.aliases.fs_stat_table|nil
local fs_lstat = wrap(uv.fs_lstat, 2, true)

---@param path string
---@param entries integer
---@param callback fun(err: string|nil, luv_dir_t: uv.aliases.fs_stat_table|nil)
---@type async fun(path: string, entries: integer): err: string|nil, luv_dir_t: uv.aliases.fs_stat_table|nil
local fs_opendir = wrap(function(path, entries, callback)
  -- the uv meta file has the wrong api
  uv.fs_opendir(path, callback, entries)
end, 3, true)

---@type async fun(luv_dir_t: uv.aliases.fs_stat_table): string|nil, uv.aliases.fs_readdir_entries[]|nil
local fs_readdir = wrap(uv.fs_readdir, 2, true)

---@type async fun(luv_dir_t: uv.aliases.fs_stat_table): err: string|nil, success: boolean|nil
local fs_closedir = wrap(uv.fs_closedir, 2, true)

---@type async fun(path: string): err: string|nil, path: string|nil
local fs_readlink = wrap(uv.fs_readlink, 2, true)

---@param path string
---@return boolean is_file
function M.is_file(path)
  local stat = uv.fs_stat(path)
  return stat and stat.type == "file" or false
end

---@param path string
---@return boolean is_directory
function M.is_directory(path)
  local stat = uv.fs_stat(path)
  return stat and stat.type == "directory" or false
end

---@async
---@param path string
---@return uv.aliases.fs_stat_table|nil stat
function M.lstat(path)
  local err, stat = fs_lstat(path)
  if not stat then
    log.error("cannot fs_lstat path %q, %s", path, err)
  end
  return stat
end

---@async
---@param path string
---@return boolean empty
local function is_empty(path)
  local err, fd = fs_opendir(path, 1)
  if not fd then
    log.error("cannot fs_opendir path %q, %s", path, err)
    return false
  else
    local entries
    err, entries = fs_readdir(fd)
    if err then
      log.error("cannot fs_readdir path %q, %s", path, err)
    end
    fs_closedir(fd)
    return entries == nil
  end
end

---@class Yat.Fs.Node
---@field public name string
---@field public _type Luv.FileType
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
    _type = "directory",
    path = path,
    empty = empty,
  }
end

M.st_mode_masks = {
  EXECUTABLE = 0x49, -- octal 111, corresponding to S_IXUSR, S_IXGRP and S_IXOTH
  PERMISSIONS_MASK = 0x7, -- octal 7, corresponding to S_IRWX
}

---@class Yat.Fs.FileNode : Yat.Fs.Node
---@field public extension string
---@field public executable boolean

---Creates a file node
---@async
---@param dir string the directory containing the file
---@param name string the name of the file
---@param stat? uv.aliases.fs_stat_table
---@return Yat.Fs.FileNode node
local function file_node(dir, name, stat)
  local path = utils.join_path(dir, name)
  local extension = name:match(".?[^.]+%.(.*)") or ""
  local executable
  if utils.is_windows then
    executable = utils.is_windows_exe(extension)
  else
    if not stat then
      local err
      err, stat = fs_lstat(path)
      if err then
        log.error("cannot fs_lstat path %q, %s", path, err)
      end
    end
    executable = stat and bit.band(M.st_mode_masks.EXECUTABLE, stat.mode) > 1 or false
  end

  return {
    name = name,
    _type = "file",
    path = path,
    extension = extension,
    executable = executable,
  }
end

---@class Yat.Fs.FifoNode : Yat.Fs.FileNode, Yat.Fs.Node

---@async
---@param dir string the directory containing the fifo
---@param name string name of the fifo
---@param stat? uv.aliases.fs_stat_table
---@return Yat.Fs.FifoNode node
local function fifo_node(dir, name, stat)
  local node = file_node(dir, name, stat) --[[@as Yat.Fs.FifoNode]]
  node._type = "fifo"
  return node
end

---@class Yat.Fs.SocketNode : Yat.Fs.FileNode, Yat.Fs.Node

---@async
---@param dir string the directory containing the socket
---@param name string name of the socket
---@param stat? uv.aliases.fs_stat_table
---@return Yat.Fs.SocketNode node
local function socket_node(dir, name, stat)
  local node = file_node(dir, name, stat) --[[@as Yat.Fs.SocketNode]]
  node._type = "socket"
  return node
end

---@class Yat.Fs.CharNode : Yat.Fs.FileNode, Yat.Fs.Node

---@async
---@param dir string the directory containing the char device file
---@param name string name of the char device file
---@param stat? uv.aliases.fs_stat_table
---@return Yat.Fs.CharNode node
local function char_node(dir, name, stat)
  local node = file_node(dir, name, stat) --[[@as Yat.Fs.CharNode]]
  node._type = "char"
  return node
end

---@class Yat.Fs.BlockNode : Yat.Fs.FileNode, Yat.Fs.Node

---@async
---@param dir string the directory containing the block device file
---@param name string name of the block device file
---@param stat? uv.aliases.fs_stat_table
---@return Yat.Fs.BlockNode node
local function block_node(dir, name, stat)
  local node = file_node(dir, name, stat) --[[@as Yat.Fs.BlockNode]]
  node._type = "block"
  return node
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
---@param lstat? uv.aliases.fs_stat_table
---@return Yat.Fs.DirectoryLinkNode|Yat.Fs.FileLinkNode|nil node
local function link_node(dir, name, lstat)
  local path = utils.join_path(dir, name)
  local rel_link_to, err, abs_link_to
  err, abs_link_to = fs_readlink(path)
  if err then
    log.error("cannot fs_readlink path %q, %s", path, err)
  end
  if not abs_link_to or not Path.is_absolute_path(abs_link_to) then
    rel_link_to = abs_link_to or ""
    abs_link_to = dir .. os_sep .. abs_link_to
  else
    rel_link_to = Path:new(abs_link_to):make_relative(dir)
  end

  -- stat here is for the target of the link
  local _, stat = fs_stat(path)
  local node
  if stat then
    local _type = stat.type
    if _type == "directory" then
      node = directory_node(dir, name)
    elseif _type == "file" or _type == "fifo" or _type == "socket" or _type == "char" or _type == "block" then
      local link_name = utils.get_file_name(abs_link_to)
      local link_extension = link_name:match(".?[^.]+%.(.*)") or "" --[[@as string]]

      node = file_node(dir, name, stat)
      node.link_name = link_name
      node.link_extension = link_extension
      node._type = _type --[[@as Luv.FileType]]
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
  path = p:absolute()
  -- in case of a link, fs_lstat returns info about the link itself instead of the file it refers to
  local err, lstat = fs_lstat(path)
  if not lstat then
    log.info("cannot fs_lstat path %q, %s", path, err)
    return nil
  end

  local parent_path = p:parent():absolute()
  local name = utils.get_file_name(path)
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
  dir = Path:new(dir):absolute()
  local err, fd = fs_opendir(dir, 50)
  if not fd then
    log.error("cannot fs_opendir path %q, %s", dir, err)
    return {}
  else
    ---@type Yat.Fs.Node[]
    local nodes, entries = {}, nil
    while true do
      err, entries = fs_readdir(fd)
      if err then
        log.error("cannot fs_readdir path %q, %s", dir, err)
      end
      if entries == nil then
        break
      end
      for _, entry in ipairs(entries) do
        local node
        if entry.type == "directory" then
          node = directory_node(dir, entry.name)
        elseif entry.type == "file" then
          node = file_node(dir, entry.name)
        elseif entry.type == "link" then
          node = link_node(dir, entry.name)
        elseif entry.type == "fifo" then
          node = fifo_node(dir, entry.name)
        elseif entry.type == "socket" then
          node = socket_node(dir, entry.name)
        elseif entry.type == "char" then
          node = char_node(dir, entry.name)
        elseif entry.type == "block" then
          node = block_node(dir, entry.name)
        end
        if node then
          nodes[#nodes + 1] = node
        end
      end
    end
    fs_closedir(fd)
    return nodes
  end
end

---@param path string
---@return boolean whether the path exists.
function M.exists(path)
  -- must use fs_lstat since fs_stat checks the target of links, not the link itself
  -- the uv meta file has the wrong api
  local stat = uv.fs_lstat(path)
  return stat ~= nil
end

---Recursively copy a directory.
---@param source string|string[] source path.
---@param destination string|string[] destination path.
---@param replace boolean whether to replace existing files.
---@return boolean success success or not
function M.copy_dir(source, destination, replace)
  local source_path = Path:new(source):absolute()
  local destination_path = Path:new(destination):absolute()

  local fd, err = uv.fs_scandir(source_path)
  if not fd then
    log.error("cannot fs_scandir path %q, %s", source_path, err)
    return false
  end

  local stat
  stat, err = uv.fs_stat(source_path)
  if not stat then
    log.error("cannot fs_stat path %q, %s", source_path, err)
    return false
  end
  local mode = stat.mode
  local continue = replace --[[@as boolean?]]
  if not continue then
    -- fs_mkdir returns nil if dir already exists
    continue, err = uv.fs_mkdir(destination_path, mode)
    if err then
      log.error("cannot fs_mkdir path %q, %s", destination_path, err)
      return false
    else
      log.debug("created directory %q", destination_path)
    end
  end
  if continue then
    while true do
      local name, _type = uv.fs_scandir_next(fd)
      if not name then
        break
      end

      if _type == "directory" then
        if not M.copy_dir({ source_path, name }, { destination_path, name }, replace) then
          return false
        end
      else
        if not M.copy_file({ source_path, name }, { destination_path, name }, replace) then
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
---@param source string|string[] source path.
---@param destination string|string[] destination path.
---@param replace boolean whether to replace an existing file.
---@return boolean success success or not.
function M.copy_file(source, destination, replace)
  source = Path:new(source):absolute()
  destination = Path:new(destination):absolute()
  local success, err = uv.fs_copyfile(source, destination, { excl = not replace })
  if not success then
    log.error("cannot fs_copyfile path %q to %q, %s", source, destination, err)
  else
    log.debug("created file %q", destination)
  end
  return success == true
end

---Rename file or directory.
---@param old string old name.
---@param new string new name.
---@return boolean success success or not.
function M.rename(old, new)
  old = Path:new(old):absolute()
  new = Path:new(new):absolute()
  local success, err = uv.fs_rename(old, new)
  if not success then
    log.error("cannot fs_rename path %q to %q, %s", old, new, err)
  else
    log.debug("renamed file %q to %q", old, new)
  end
  return success == true
end

---Create a directory.
---@param path string the directory to create
---@return boolean success success or not.
function M.create_dir(path)
  local mode = 493 -- 755 in octal
  -- fs_mkdir returns nil if the path already exists, or if the path has parent
  -- directories that has to be created as well
  local abs_path = Path:new(path):absolute()
  local success, err = uv.fs_mkdir(abs_path, mode)
  if success == nil then
    if not M.exists(abs_path) then
      local dirs = vim.split(abs_path, os_sep, { plain = true })
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
          success, err = uv.fs_mkdir(current, mode)
          if not success then
            log.error("cannot fs_mkdir path %q, %s", current, err)
            return false
          else
            log.debug("created directory %q", current)
          end
          acc = current
        end
      end
    else
      log.debug("directory %q already exists", abs_path)
    end
    return true
  elseif success == false then
    log.error("cannot fs_mkdir path %q, %s", abs_path, err)
    return false
  else
    log.debug("created directory %q", abs_path)
    return true
  end
end

---Create a new file.
---@param file string path.
---@return boolean sucess success or not.
function M.create_file(file)
  local path = Path:new(file)

  if M.create_dir(path:parent().filename) then
    local fd, err = uv.fs_open(file, "w", 420) -- 644 in octal
    if not fd or err then
      log.error("cannot fs_open path %q, %s", file, err)
      return false
    end
    local success
    success, err = uv.fs_close(fd)
    if not success then
      log.error("cannot fs_close path %q, %s", file, err)
    else
      log.debug("created file %q", file)
    end
    return success == true
  else
    return false
  end
end

---Recusively remove a directory.
---@param path string the path to remove.
---@return boolean success success or not.
function M.remove_dir(path)
  local fd, err = uv.fs_scandir(path)
  if not fd then
    log.error("cannot fs_scandir path %q, %s", path, err)
    return false
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

  local success
  success, err = uv.fs_rmdir(path)
  if not success then
    log.error("cannot fs_rmdir path %q, %s", path, err)
  else
    log.debug("removed directory %q", path)
  end
  return success == true
end

---Remove a file.
---@param path string the path to remove.
---@return boolean success success or not.
function M.remove_file(path)
  local success, err = uv.fs_unlink(path)
  if not success then
    log.error("cannot fs_unlink path %q, %s", path, err)
  else
    log.debug("removed file %q", path)
  end
  return success == true
end

return M
