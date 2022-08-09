local scheduler = require("plenary.async.util").scheduler

local diagnostics = require("ya-tree.diagnostics")
local fs = require("ya-tree.filesystem")
local log = require("ya-tree.log")
local node_utils = require("ya-tree.nodes.utils")
local utils = require("ya-tree.utils")

---@alias YaTreeNodeType "FileSystem" | "Search" | "Buffer" | "GitStatus"

---@class YaTreeNode : FsNode
---@field private __node_type YaTreeNodeType
---@field public parent? YaTreeNode
---@field private type file_type
---@field private _stat? uv_fs_stat
---@field public children? YaTreeNode[]
---@field public empty? boolean
---@field public extension? string
---@field public executable? boolean
---@field public link boolean
---@field public absolute_link_to? string
---@field public relative_link_to string
---@field public link_orphan? boolean
---@field public link_name? string
---@field public link_extension? string
---@field public repo? GitRepo
---@field public clipboard_status clipboard_action|nil
---@field private scanned? boolean
---@field public expanded? boolean
---@field public depth integer
---@field public last_child boolean
local Node = { __node_type = "FileSystem" }
Node.__index = Node

---@param self YaTreeNode
---@param other YaTreeNode
---@return boolean
Node.__eq = function(self, other)
  return self.path == other.path
end

---@param self YaTreeNode
---@return string
Node.__tostring = function(self)
  return string.format("(%s, %s)", self.__node_type, self.path)
end

---Creates a new node.
---@param fs_node FsNode filesystem data.
---@param parent? YaTreeNode the parent node.
---@return YaTreeNode node
function Node:new(fs_node, parent)
  return node_utils.create_node(self, fs_node, parent)
end

---@param visitor fun(node: YaTreeNode):boolean called for each node, if the function returns `true` the `walk` terminates.
function Node:walk(visitor)
  if visitor(self) then
    return
  end

  if self:is_container() then
    for _, child in ipairs(self.children) do
      if child:walk(visitor) then
        return
      end
    end
  end
end

---@param output_to_log? boolean
---@return table<string, any>
function Node:get_debug_info(output_to_log)
  local t = { __node_type = self.__node_type }
  for k, v in pairs(self) do
    if type(v) == "table" then
      if k == "parent" or k == "repo" then
        t[k] = tostring(v)
      elseif k == "children" then
        local children = {}
        for _, child in ipairs(v) do
          children[#children + 1] = tostring(child)
        end
        t[k] = children
      else
        t[k] = v
      end
    elseif type(v) ~= "function" then
      t[k] = v
    end
  end
  if output_to_log then
    log.info(t)
  end
  return t
end

---@private
---@param fs_node FsNode filesystem data.
function Node:_merge_new_data(fs_node)
  for k, v in pairs(fs_node) do
    if type(self[k]) ~= "function" then
      self[k] = v
    else
      log.error("self.%s is a function, this should not happen!", k)
    end
  end
end

---@param a YaTreeNode
---@param b YaTreeNode
---@return boolean
function Node.node_comparator(a, b)
  local ac = a:is_container()
  local bc = b:is_container()
  if ac and not bc then
    return true
  elseif not ac and bc then
    return false
  end
  return a.path < b.path
end

---@async
---@private
function Node:_scandir()
  log.debug("scanning directory %q", self.path)
  -- keep track of the current children
  ---@type table<string, YaTreeNode>
  local children = {}
  for _, child in ipairs(self.children) do
    children[child.path] = child
  end

  ---@param fs_node FsNode
  self.children = vim.tbl_map(function(fs_node)
    local child = children[fs_node.path]
    if child then
      log.trace("merging node %q with new data", fs_node.path)
      child:_merge_new_data(fs_node)
    else
      log.trace("creating new node for %q", fs_node.path)
      child = Node:new(fs_node, self)
      child.clipboard_status = self.clipboard_status
    end
    return child
  end, fs.scan_dir(self.path))
  table.sort(self.children, self.node_comparator)
  self.empty = #self.children == 0
  self.scanned = true

  scheduler()
end

---@param repo GitRepo
---@param node YaTreeNode
local function set_git_repo_on_node_and_children(repo, node)
  node.repo = repo
  if node.children then
    for _, child in ipairs(node.children) do
      if not child.repo then
        set_git_repo_on_node_and_children(repo, child)
      end
    end
  end
end

---@param repo GitRepo
function Node:set_git_repo(repo)
  local toplevel = repo.toplevel
  if toplevel == self.path then
    log.debug("node %q is the toplevel of repo %s, setting repo on node and all child nodes", self.path, tostring(repo))
    -- this node is the git toplevel directory, set the property on self
    set_git_repo_on_node_and_children(repo, self)
  else
    log.debug("node %q is not the toplevel of repo %s, walking up the tree", self.path, tostring(repo))
    if #toplevel < #self.path then
      -- this node is below the git toplevel directory,
      -- walk the tree upwards until we hit the topmost node
      local node = self
      while node.parent and #toplevel <= #node.parent.path do
        node = node.parent --[[@as YaTreeNode]]
      end
      log.debug("node %q is the top of the tree, setting repo on node and all child nodes", node.path, tostring(repo))
      set_git_repo_on_node_and_children(repo, node)
    else
      log.error("git repo with toplevel %s is somehow below this node %s, this should not be possible", toplevel, self.path)
      log.error("self=%s", self)
      log.error("repo=%s", repo)
    end
  end
end

---@return YaTreeNodeType node_type
function Node:node_type()
  return self.__node_type
end

---@return boolean is_container
function Node:is_container()
  return self.type == "directory"
end

---@return boolean
function Node:is_directory()
  return self.type == "directory"
end

---@return boolean
function Node:is_file()
  return self.type == "file"
end

---@return boolean
function Node:is_link()
  return self.link == true
end

---@return boolean
function Node:is_fifo()
  return self.type == "fifo"
end

---@return boolean
function Node:is_socket()
  return self.type == "socket"
end

---@return boolean
function Node:is_char_device()
  return self.type == "char"
end

---@return boolean
function Node:is_block_device()
  return self.type == "block"
end

---@async
---@return uv_fs_stat stat
function Node:fs_stat()
  if not self._stat then
    self._stat = fs.lstat(self.path)
  end
  return self._stat
end

---@param path string
---@return boolean
function Node:is_ancestor_of(path)
  return self:is_directory() and #self.path < #path and path:find(self.path .. utils.os_sep, 1, true) ~= nil
end

---@return boolean
function Node:is_empty()
  return self.empty == true
end

---@return boolean
function Node:is_dotfile()
  return self.name:sub(1, 1) == "."
end

---@return boolean
function Node:is_git_ignored()
  return self.repo and self.repo:is_ignored(self.path, self.type) or false
end

---@return string|nil
function Node:git_status()
  return self.repo and self.repo:status_of(self.path)
end

---@return boolean
function Node:is_git_repository_root()
  return self.repo and self.repo.toplevel == self.path or false
end

---@param status clipboard_action
function Node:set_clipboard_status(status)
  self.clipboard_status = status
  if self:is_directory() then
    for _, child in ipairs(self.children) do
      child:set_clipboard_status(status)
    end
  end
end

function Node:clear_clipboard_status()
  self:set_clipboard_status(nil)
end

---@return number|nil
function Node:diagnostics_severity()
  return diagnostics.of(self.path)
end

---Returns an iterator function for this `node`s children.
--
---@generic T : YaTreeNode
---@param self `T`
---@param opts? { reverse?: boolean, from?: `T` }
---  - {opts.reverse?} `boolean`
---  - {opts.from?} `T`
---@return fun():`T` iterator
function Node.iterate_children(self, opts)
  ---@cast self YaTreeNode
  if not self.children or #self.children == 0 then
    return function() end
  end

  opts = opts or {}
  local start = 0
  if opts.reverse then
    start = #self.children + 1
  end
  if opts.from then
    for i, child in ipairs(self.children) do
      if child == opts.from then
        start = i
        break
      end
    end
  end

  local pos = start
  if opts.reverse then
    return function()
      pos = pos - 1
      if pos >= 1 then
        return self.children[pos]
      end
    end
  else
    return function()
      pos = pos + 1
      if pos <= #self.children then
        return self.children[pos]
      end
    end
  end
end

---Collapses the node, if it is a container.
--
---@param opts? {children_only?: boolean, recursive?: boolean}
---  - {opts.children_only?} `boolean`
---  - {opts.recursive?} `boolean`
function Node:collapse(opts)
  opts = opts or {}
  if self:is_container() then
    if not opts.children_only then
      self.expanded = false
    end

    if opts.recursive then
      for _, child in ipairs(self.children) do
        child:collapse({ recursive = opts.recursive })
      end
    end
  end
end

---Expands the node, if it is a container. If the node hasn't been scanned before, will scan the directory.
--
---@async
---@generic T : YaTreeNode
---@param self `T`
---@param opts? {force_scan?: boolean, to?: string}
---  - {opts.force_scan?} `boolean` rescan directories.
---  - {opts.to?} `string` recursively expand to the specified path and return it.
---@return `T`|nil node if {opts.to} is specified, and found.
function Node.expand(self, opts)
  ---@cast self YaTreeNode
  log.debug("expanding %q", self.path)
  opts = opts or {}
  if self:is_container() then
    if not self.scanned or opts.force_scan then
      self:_scandir()
    end
    self.expanded = true
  end

  if opts.to then
    if self.path == opts.to then
      log.debug("self %q is equal to path %q", self.path, opts.to)
      return self
    elseif self:is_container() and self:is_ancestor_of(opts.to) then
      for _, child in ipairs(self.children) do
        if child:is_ancestor_of(opts.to) then
          log.debug("child node %q is parent of %q", child.path, opts.to)
          return child:expand(opts)
        elseif child.path == opts.to then
          if child:is_container() then
            child:expand(opts)
          end
          return child
        end
      end
    else
      log.debug("node %q is not a parent of path %q", self.path, opts.to)
    end
  end
end

---Returns the child node specified by `path` if it has been loaded.
---@generic T : YaTreeNode
---@param self `T`
---@param path string
---@return `T`|nil
function Node.get_child_if_loaded(self, path)
  ---@cast self YaTreeNode
  if self.path == path then
    return self
  end
  if not self:is_directory() then
    return
  end

  if self:is_ancestor_of(path) then
    for _, child in ipairs(self.children) do
      if child.path == path then
        return child
      elseif child:is_ancestor_of(path) then
        return child:get_child_if_loaded(path)
      end
    end
  end
end

do
  ---@async
  ---@param node YaTreeNode
  ---@param recurse boolean
  ---@param refresh_git boolean
  ---@param refreshed_git_repos table<string, boolean>
  local function refresh_directory_node(node, recurse, refresh_git, refreshed_git_repos)
    if refresh_git and node.repo and not refreshed_git_repos[node.repo.toplevel] then
      node.repo:refresh_status({ ignored = true })
      refreshed_git_repos[node.repo.toplevel] = true
    end
    if node.scanned then
      node:_scandir()

      if recurse then
        for _, child in ipairs(node.children) do
          if child:is_directory() then
            refresh_directory_node(child, true, refresh_git, refreshed_git_repos)
          end
        end
      end
    end
  end

  ---@async
  ---@param opts? { recurse?: boolean, refresh_git?: boolean }
  ---  - {opts.recurse?} `boolean` whether to perform a recursive refresh, default: `false`.
  ---  - {opts.refresh_git?} `boolean` whether to refresh the git status, default: `false`.
  function Node:refresh(opts)
    opts = opts or {}
    local recurse = opts.recurse or false
    local refresh_git = opts.refresh_git or false
    log.debug("refreshing %q, recurse=%s, refresh_git=%s", self.path, recurse, refresh_git)

    if self:is_directory() then
      refresh_directory_node(self, recurse, refresh_git, {})
    else
      local fs_node = fs.node_for(self.path)
      scheduler()
      if fs_node then
        self:_merge_new_data(fs_node)
        if refresh_git and self.repo then
          self.repo:refresh_status_for_file(self.path)
        end
      end
    end
  end
end

return Node
