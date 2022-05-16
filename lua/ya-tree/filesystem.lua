local Path = require("plenary.path")

local utils = require("ya-tree.utils")

local uv = vim.loop

local M = {}

---@param path string
---@return boolean empty
local function is_empty(path)
  local handle = uv.fs_scandir(path)
  return handle and uv.fs_scandir_next(handle) == nil or false
end

-- types defined by luv are:
-- file, directory, link, fifo, socket, char, block and unknown
-- see: https://github.com/luvit/luv/blob/d2e235503f6cb5c86121cd70cdb5d17e368bab03/src/fs.c#L107=

---@alias file_type "directory"|"file"

---@class FsNode
---@field name string
---@field type file_type
---@field path string

---@class FsDirectoryNode : FsNode
---@field empty boolean

---Creates a directory node
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

---@param path string
---@param extension string
---@return boolean executable
local function is_executable(path, extension)
  return utils.is_windows and utils.is_windows_exe(extension) or uv.fs_access(path, "X")
end

---@class FsFileNode : FsNode
---@field extension string
---@field executable boolean

---Creates a file node
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
  ---@type string[]
  local splits = vim.split(path, utils.os_sep, { plain = true })
  return splits[#splits]
end

---@class FsDirectoryLinkNode : FsDirectoryNode
---@field link boolean
---@field link_to string

---@class FsFileLinkNode : FsFileNode
---@field link boolean
---@field link_to string
---@field link_name string
---@field link_extension string

---@param dir string the directory containing the link
---@param name string name of the link
---@return FsDirectoryLinkNode|FsFileLinkNode|nil node
local function link_node(dir, name)
  local path = utils.join_path(dir, name)
  ---@type string
  local link_to = uv.fs_realpath(path)
  if not link_to then
    -- don't create nodes for links that have no target
    return nil
  end

  local stat = uv.fs_stat(path)
  local p = Path:new(link_to)
  link_to = p:make_relative()

  ---@type FsDirectoryLinkNode|FsFileLinkNode|nil
  local node
  if stat and stat.type == "directory" then
    node = directory_node(dir, name)
  elseif stat and stat.type == "file" then
    local link_name = get_file_name(p.filename)
    local link_extension = link_name:match(".?[^.]+%.(.*)") or ""

    node = file_node(dir, name)
    node.link_name = link_name
    node.link_extension = link_extension
  else
    return nil
  end

  node.link = true
  node.link_to = link_to
  return node
end

---`FsNode` comparator
---@param a FsNode
---@param b FsNode
---@return boolean
function M.fs_node_comparator(a, b)
  if a.type == b.type then
    return a.path < b.path
  else
    return a.type < b.type
  end
end

---@param path string
---@return FsDirectoryNode|FsFileNode|FsDirectoryLinkNode|FsFileLinkNode|nil node
function M.node_for(path)
  -- in case of a link, fs_lstat returns info about the link itself instead of the file it refers to
  local stat = uv.fs_lstat(path)
  local _type = stat and stat.type or nil
  if not _type then
    -- this is most likely caused by a symbolic link pointing to a non-existing file and not really a problem,
    -- or nothing we can do anything about, so just ignore it
    return
  end

  local parent_path = Path:new(path):parent():absolute()
  local name = get_file_name(path)
  if _type == "directory" then
    return directory_node(parent_path, name)
  elseif _type == "file" then
    return file_node(parent_path, name)
  elseif _type == "link" then
    return link_node(parent_path, name)
  end
end

---Scans a directory and returns an array of items extending `FsNode`.
---@param dir string the directory to scan.
---@return FsNode[] nodes
function M.scan_dir(dir)
  ---@type FsNode[]
  local nodes = {}
  local fd = uv.fs_scandir(dir)
  if fd then
    while true do
      ---@type string
      local name, _type = uv.fs_scandir_next(fd)
      if name == nil then
        break
      end
      ---@type FsNode
      local node
      if _type == "directory" then
        node = directory_node(dir, name)
      elseif _type == "file" then
        node = file_node(dir, name)
      elseif _type == "link" then
        node = link_node(dir, name)
      end
      if node then
        nodes[#nodes + 1] = node
      end
    end
  end

  table.sort(nodes, M.fs_node_comparator)
  return nodes
end

---@vararg string path elements
---@return boolean #whether the path exists.
function M.exists(...)
  return Path:new(...):exists()
end

---Recursively copy a directory.
---@param source string source path.
---@param destination string destination path.
---@param replace boolean whether to replace existing files.
---@return boolean success #success or not
function M.copy_dir(source, destination, replace)
  local source_path = Path:new(source)
  local destination_path = Path:new(destination)

  local fd = uv.fs_scandir(source_path:absolute())
  if not fd then
    return false
  end

  local mode = uv.fs_stat(source_path:absolute()).mode
  -- fs_mkdir returns nil if dir alrady exists
  if replace or uv.fs_mkdir(destination_path:absolute(), mode) then
    while true do
      local name, _type = uv.fs_scandir_next(fd)
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
---@param source string source path.
---@param destination string destination path.
---@param replace boolean whether to replace an existing file.
---@return boolean success #success or not.
function M.copy_file(source, destination, replace)
  return uv.fs_copyfile(Path:new(source):absolute(), Path:new(destination):absolute(), { excl = not replace or false })
end

---Rename file or directory.
---@param old string old name.
---@param new string new name.
---@return boolean success #success or not.
function M.rename(old, new)
  return uv.fs_rename(Path:new(old):absolute(), Path:new(new):absolute())
end

---Create a directory.
---@param path string the directory to create
---@return boolean success #success or not.
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

---Create a new file.
---@param file string path.
---@return boolean sucess #success or not.
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

---Recusively remove a directory.
---@param path string the path to remove.
---@return boolean success #success or not.
function M.remove_dir(path)
  local fd = uv.fs_scandir(path)
  if not fd then
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

  return uv.fs_rmdir(path)
end

---Remove a file.
---@param path string the path to remove.
---@return boolean success #success or not.
function M.remove_file(path)
  return uv.fs_unlink(path)
end

return M
