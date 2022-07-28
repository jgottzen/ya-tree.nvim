local uv = require("plenary.async").uv
local Path = require("plenary.path")

local utils = require("ya-tree.utils")

local loop = vim.loop

local M = {}

---@async
---@param path string
---@return boolean is_directory
function M.is_directory(path)
  local _, stat = uv.fs_stat(path)
  return stat and stat.type == "directory" or false
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

---@alias file_type "directory" | "file" | "fifo" | "socket" | "char" | "block"

---@class FsNode
---@field public name string
---@field public type file_type
---@field public path string

---@class FsDirectoryNode : FsNode
---@field public empty boolean

---Creates a directory node
---@async
---@param dir string the directory containing the directory
---@param name string the name of the directory
---@return FsDirectoryNode node
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

---@async
---@param path string
---@param extension string
---@return boolean executable
local function is_executable(path, extension)
  if utils.is_windows then
    return utils.is_windows_exe(extension)
  else
    local _, exec = uv.fs_access(path, "X")
    return exec == true
  end
end

---@class FsFileNode : FsNode
---@field public extension string
---@field public executable boolean

---Creates a file node
---@async
---@param dir string the directory containing the file
---@param name string the name of the file
---@return FsFileNode node
local function file_node(dir, name)
  local path = utils.join_path(dir, name)
  local extension = name:match(".?[^.]+%.(.*)") or ""
  local executable = is_executable(path, extension)

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
local function get_file_name(path)
  if path:sub(-1) == utils.os_sep then
    path = path:sub(1, -2)
  end
  ---@type string[]
  local splits = vim.split(path, utils.os_sep, { plain = true })
  return splits[#splits]
end

---@class FsFifoNode : FsFileNode, FsNode

---@async
---@param dir string the directory containing the fifo
---@param name string name of the fifo
---@return FsFifoNode node
local function fifo_node(dir, name)
  local node = file_node(dir, name)
  node.type = "fifo"
  return node --[[@as FsFifoNode]]
end

---@class FsSocketNode : FsFileNode, FsNode

---@async
---@param dir string the directory containing the socket
---@param name string name of the socket
---@return FsSocketNode node
local function socket_node(dir, name)
  local node = file_node(dir, name)
  node.type = "socket"
  return node --[[@as FsSocketNode]]
end

---@class FsCharNode : FsFileNode, FsNode

---@async
---@param dir string the directory containing the char device file
---@param name string name of the char device file
---@return FsCharNode node
local function char_node(dir, name)
  local node = file_node(dir, name)
  node.type = "char"
  return node --[[@as FsCharNode]]
end

---@class FsBlockNode : FsFileNode, FsNode

---@async
---@param dir string the directory containing the block device file
---@param name string name of the block device file
---@return FsBlockNode node
local function block_node(dir, name)
  local node = file_node(dir, name)
  node.type = "block"
  return node --[[@as FsBlockNode]]
end

---@class FsLinkNodeMixin
---@field public link boolean
---@field public absolute_link_to string
---@field public relative_link_to string
---@field public link_orphan boolean

---@class FsDirectoryLinkNode : FsDirectoryNode, FsLinkNodeMixin, FsNode

---@class FsFileLinkNode : FsFileNode, FsLinkNodeMixin, FsNode
---@field public link_name string
---@field public link_extension string

---@async
---@param dir string the directory containing the link
---@param name string name of the link
---@return FsDirectoryLinkNode|FsFileLinkNode|nil node
local function link_node(dir, name)
  local path = utils.join_path(dir, name)
  ---@type userdata, string
  local _, abs_link_to = uv.fs_readlink(path)
  local rel_link_to = Path:new(abs_link_to):make_relative(dir) --[[@as string]]
  local _, stat = uv.fs_stat(path)
  local node
  if stat then
    local _type = stat.type --[[@as file_type]]
    if _type == "directory" then
      node = directory_node(dir, name)
    elseif _type == "file" or _type == "fifo" or _type == "socket" or _type == "char" or _type == "block" then
      local link_name = get_file_name(abs_link_to)
      ---@type string
      local link_extension = link_name:match(".?[^.]+%.(.*)") or ""

      node = file_node(dir, name)
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
    node = file_node(dir, name)
    node.link_orphan = true
  end

  ---@cast node FsDirectoryLinkNode|FsFileLinkNode
  node.link = true
  node.absolute_link_to = abs_link_to
  node.relative_link_to = rel_link_to
  return node
end

---@async
---@param path string
---@return FsNode|nil node
function M.node_for(path)
  -- in case of a link, fs_lstat returns info about the link itself instead of the file it refers to
  local _, stat = uv.fs_lstat(path)
  local _type = stat and stat.type or nil --[[@as file_type?]]
  if not _type then
    return nil
  end

  ---@type string
  local parent_path = Path:new(path):parent():absolute()
  local name = get_file_name(path)
  if _type == "directory" then
    return directory_node(parent_path, name)
  elseif _type == "file" then
    return file_node(parent_path, name)
  elseif _type == "link" then
    return link_node(parent_path, name)
  elseif _type == "fifo" then
    return fifo_node(parent_path, name)
  elseif _type == "socket" then
    return socket_node(parent_path, name)
  elseif _type == "char" then
    return char_node(parent_path, name)
  elseif _type == "block" then
    return block_node(parent_path, name)
  else
    return nil
  end
end

---Scans a directory and returns an array of items extending `FsNode`.
---@async
---@param dir string the directory to scan.
---@return FsNode[] nodes
function M.scan_dir(dir)
  ---@type FsNode[]
  local nodes = {}
  local _, fd = uv.fs_scandir(dir)
  if fd then
    while true do
      ---@type string, file_type?
      local name, _type = loop.fs_scandir_next(fd)
      if name == nil then
        break
      end
      ---@type FsNode?
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

  local _, stat = uv.fs_stat(source_path:absolute())
  local mode = stat.mode
  local continue = replace
  if not continue then
    -- fs_mkdir returns nil if dir alrady exists
    _, continue = uv.fs_mkdir(destination_path:absolute(), mode)
  end
  if continue then
    while true do
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
  local abs_path = Path:new(path):absolute()
  local _, success = uv.fs_mkdir(abs_path, mode)
  if not success and not M.exists(abs_path) then
    ---@type string[]
    local dirs = vim.split(abs_path, utils.os_sep)
    local acc = ""
    for _, dir in ipairs(dirs) do
      local current = utils.join_path(acc, dir)
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
    ---@type string, file_type?
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
