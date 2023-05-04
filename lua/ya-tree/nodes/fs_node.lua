local lazy = require("ya-tree.lazy")

local async = lazy.require("ya-tree.async") ---@module "ya-tree.async"
local fs = lazy.require("ya-tree.fs") ---@module "ya-tree.fs"
local FsBasedNode = require("ya-tree.nodes.fs_based_node")
local fs_watcher = lazy.require("ya-tree.fs.watcher") ---@module "ya-tree.fs.watcher"
local Logger = lazy.require("ya-tree.log") ---@module "ya-tree.log"
local utils = lazy.require("ya-tree.utils") ---@module "ya-tree.utils"

---@class Yat.Node.FilesystemStatic : Yat.Node.FsBasedNodeStatic

---@class Yat.Node.Filesystem : Yat.Node.FsBasedNode
---@field new fun(self: Yat.Node.Filesystem, fs_node: Yat.Fs.Node, parent?: Yat.Node.Filesystem): Yat.Node.Filesystem
---@field public static Yat.Node.FilesystemStatic
---
---@field public TYPE "filesystem"
---@field public parent? Yat.Node.Filesystem
---@field private _children? Yat.Node.Filesystem[]
---@field private scanned? boolean
---@field private fs_event_registered boolean
local FilesystemNode = FsBasedNode:subclass("Yat.Node.Filesystem")

---@protected
---@param fs_node Yat.Fs.Node filesystem data.
---@param parent? Yat.Node.Filesystem the parent node.
function FilesystemNode:init(fs_node, parent)
  FsBasedNode.init(self, fs_node, parent)
  self.TYPE = "filesystem"
end

---@param directories_first boolean
---@param case_sensitive boolean
---@param by Yat.Node.Filesystem.SortBy
---@return fun(a: Yat.Node.Filesystem, b: Yat.Node.Filesystem):boolean
function FilesystemNode.static.create_comparator(directories_first, case_sensitive, by)
  return function(a, b)
    if directories_first then
      local ad = a:is_directory()
      local bd = b:is_directory()
      if ad and not bd then
        return true
      elseif not ad and bd then
        return false
      end
    end
    local aby, bby
    if by == "type" then
      aby = a:is_link() and "link" or a:fs_type()
      bby = b:is_link() and "link" or b:fs_type()
    elseif by == "extension" then
      aby = a.extension and a.extension ~= "" and a.extension or a.name
      bby = b.extension and b.extension ~= "" and b.extension or b.name
    else
      aby = a.name
      bby = b.name
    end
    if not case_sensitive then
      aby = aby:lower()
      bby = bby:lower()
    end
    return aby < bby
  end
end

---@private
---@param fs_node Yat.Fs.Node filesystem data.
function FilesystemNode:merge_new_data(fs_node)
  if self:is_directory() and fs_node._type ~= "directory" and self.fs_event_registered then
    self.fs_event_registered = false
    fs_watcher.remove_watcher(self.path)
  elseif not self:is_directory() and fs_node._type == "directory" and not self.fs_event_registered then
    self.fs_event_registered = true
    fs_watcher.watch_dir(self.path)
  end
  FsBasedNode.merge_new_data(self, fs_node)
end

---@async
---@param recurse? boolean
function FilesystemNode:remove_watcher(recurse)
  if self:is_directory() and self.fs_event_registered then
    self.fs_event_registered = false
    fs_watcher.remove_watcher(self.path)
    if recurse then
      for _, child in ipairs(self._children) do
        child:remove_watcher(recurse)
      end
    end
  end
end

function FilesystemNode:add_watcher()
  if self:is_directory() and not self.fs_event_registered then
    self.fs_event_registered = true
    fs_watcher.watch_dir(self.path)
  end
end

---@package
function FilesystemNode:scandir()
  local log = Logger.get("nodes")
  log.debug("scanning directory %q", self.path)
  -- keep track of the current children
  ---@type table<string, Yat.Node.Filesystem>
  local children = {}
  for _, child in ipairs(self._children) do
    children[child.path] = child
  end

  self._children = {}
  for _, fs_node in ipairs(fs.scan_dir(self.path)) do
    local child = children[fs_node.path]
    if child then
      log.trace("merging node %q with new data", fs_node.path)
      child:merge_new_data(fs_node)
      children[fs_node.path] = nil
    else
      log.trace("creating new node for %q", fs_node.path)
      child = FilesystemNode:new(fs_node, self)
      child._clipboard_status = self._clipboard_status
      child:add_watcher()
    end
    self._children[#self._children + 1] = child
  end
  table.sort(self._children, self.node_comparator)
  self.empty = #self._children == 0
  self.scanned = true
  self:add_watcher()

  -- remove any watchers for any children that was remomved
  for _, child in pairs(children) do
    child:remove_watcher(true)
  end

  async.scheduler()

  local buffers = utils.get_current_buffers()
  for _, child in ipairs(self._children) do
    local buffer = buffers[child.path]
    child.modified = buffer and buffer.modified or false
  end
end

---@async
---@param path string
---@return Yat.Node.Filesystem|nil node
function FilesystemNode:add_node(path)
  return self:_add_node(path, function(path_part, parent)
    local fs_node = fs.node_for(path_part)
    if fs_node then
      local node = FilesystemNode:new(fs_node, parent)
      node:add_watcher()
      return node
    end
  end)
end

---@protected
function FilesystemNode:on_node_removed()
  self:remove_watcher(true)
end

---@param node Yat.Node.Filesystem
function FilesystemNode:add_child(node)
  if self._children then
    self._children[#self._children + 1] = node
    self.empty = false
    table.sort(self._children, self.node_comparator)
  end
end

---Expands the node, if it is a directory. If the node hasn't been scanned before, will scan the directory.
---@async
---@param opts? {force_scan?: boolean, to?: string}
---  - {opts.force_scan?} `boolean` rescan directories.
---  - {opts.to?} `string` recursively expand to the specified path and return it.
---@return Yat.Node.Filesystem|nil node if {opts.to} is specified, and found.
function FilesystemNode:expand(opts)
  opts = opts or {}
  if self._children and (not self.scanned or opts.force_scan) then
    self:scandir()
  end

  return FsBasedNode.expand(self, opts)
end

---@async
---@private
---@param recurse boolean
---@param refresh_git boolean
---@param refreshed_git_repos table<string, boolean>
function FilesystemNode:refresh_directory_node(recurse, refresh_git, refreshed_git_repos)
  if refresh_git and self.repo and not refreshed_git_repos[self.repo.toplevel] then
    self.repo:status():refresh({ ignored = true })
    refreshed_git_repos[self.repo.toplevel] = true
  end
  if self.scanned then
    self:scandir()

    if recurse then
      for _, child in ipairs(self._children) do
        if child:is_directory() then
          child:refresh_directory_node(recurse, refresh_git, refreshed_git_repos)
        end
      end
    end
  end
end

---@async
---@param opts? {recurse?: boolean, refresh_git?: boolean}
---  - {opts.recurse?} `boolean` whether to perform a recursive refresh, default: `false`.
---  - {opts.refresh_git?} `boolean` whether to refresh the git status, default: `false`.
function FilesystemNode:refresh(opts)
  opts = opts or {}
  local recurse = opts.recurse == true
  local refresh_git = opts.refresh_git == true
  Logger.get("nodes").debug("refreshing %q, recurse=%s, refresh_git=%s", self.path, recurse, refresh_git)

  if self:is_directory() then
    self:refresh_directory_node(recurse, refresh_git, {})
  else
    local fs_node = fs.node_for(self.path)
    if fs_node then
      self:merge_new_data(fs_node)
    else
      for i = #self.parent._children, 1, -1 do
        local child = self.parent._children[i]
        if child == self then
          table.remove(self.parent._children, i)
          break
        end
      end
    end
    if refresh_git and self.repo then
      self.repo:status():refresh_path(self.path)
    end
  end
end

return FilesystemNode
