local scheduler = require("plenary.async.util").scheduler
local Path = require("plenary.path")

local diagnostics = require("ya-tree.diagnostics")
local fs = require("ya-tree.fs")
local fs_watcher = require("ya-tree.fs.watcher")
local log = require("ya-tree.log")("nodes")
local utils = require("ya-tree.utils")

---@alias Yat.Nodes.Type "FileSystem" | "Search" | "Buffer" | "Git" | "Text"

---@class Yat.Node
---@field protected __node_type "FileSystem"
---@field public name string
---@field public path string
---@field public parent? Yat.Node
---@field protected _type Luv.FileType
---@field private _children? Yat.Node[]
---@field public empty? boolean
---@field public extension? string
---@field public executable? boolean
---@field public link boolean
---@field public absolute_link_to? string
---@field public relative_link_to string
---@field public link_orphan? boolean
---@field public link_name? string
---@field public link_extension? string
---@field public modified boolean
---@field public repo? Yat.Git.Repo
---@field protected _clipboard_status Yat.Actions.Clipboard.Action|nil
---@field protected scanned? boolean
---@field public expanded? boolean
---@field package _fs_event_registered boolean
local Node = { __node_type = "FileSystem" }
Node.__index = Node

---@param other Yat.Node
Node.__eq = function(self, other)
  return self.path == other.path
end

Node.__tostring = function(self)
  return string.format("(%s, %s)", self.__node_type, self.path)
end

---Creates a new node.
---@generic T : Yat.Node
---@param class T
---@param fs_node Yat.Fs.Node filesystem data.
---@param parent? T the parent node.
---@return T node
function Node.new(class, fs_node, parent)
  local self = setmetatable(fs_node, class) --[[@as Yat.Node]]
  ---@cast parent Yat.Node?
  self.parent = parent
  self.modified = false
  if self:is_directory() then
    self._children = {}
  end

  -- inherit any git repo
  if parent and parent.repo then
    self.repo = parent.repo
  end

  log.trace("created node %s", self)

  return self
end

---Recursively calls `visitor` for this node and each child node, if the function returns `true` the `walk` doens't recurse into
---any children of that node, but continues with the next child, if any.
---@param visitor fun(node: Yat.Node):boolean?
function Node:walk(visitor)
  if visitor(self) then
    return
  end

  if self._children then
    for _, child in ipairs(self._children) do
      child:walk(visitor)
    end
  end
end

---@param output_to_log? boolean
---@return table<string, any>
function Node:get_debug_info(output_to_log)
  local t = {}
  t.__node_type = self.__node_type
  for k, v in pairs(self) do
    if type(v) == "table" then
      if k == "parent" or k == "repo" then
        t[k] = tostring(v)
      elseif k == "_children" then
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

---@package
---@param fs_node Yat.Fs.Node filesystem data.
function Node:_merge_new_data(fs_node)
  if self:is_directory() and fs_node._type ~= "directory" and self._fs_event_registered then
    self._fs_event_registered = false
    fs_watcher.remove_watcher(self.path)
  elseif not self:is_directory() and fs_node._type == "directory" and not self._fs_event_registered then
    self._fs_event_registered = true
    fs_watcher.watch_dir(self.path)
  end
  for k, v in pairs(fs_node) do
    if type(self[k]) ~= "function" then
      self[k] = v
    else
      log.error("self.%s is a function, this should not happen!", k)
    end
  end
end

---@param a Yat.Node
---@param b Yat.Node
---@return boolean
function Node.node_comparator(a, b)
  local ac = a:is_directory()
  local bc = b:is_directory()
  if ac and not bc then
    return true
  elseif not ac and bc then
    return false
  end
  return a.path < b.path
end

---@async
---@param node Yat.Node
local function maybe_remove_watcher(node)
  if node:is_directory() and node._fs_event_registered then
    node._fs_event_registered = false
    fs_watcher.remove_watcher(node.path)
  end
end

---@param node Yat.Node
local function maybe_add_watcher(node)
  if node:is_directory() and not node._fs_event_registered then
    node._fs_event_registered = true
    fs_watcher.watch_dir(node.path)
  end
end

---@protected
function Node:_scandir()
  log.debug("scanning directory %q", self.path)
  -- keep track of the current children
  ---@type table<string, Yat.Node>
  local children = {}
  for _, child in ipairs(self._children) do
    children[child.path] = child
  end

  ---@param fs_node Yat.Fs.Node
  self._children = vim.tbl_map(function(fs_node)
    local child = children[fs_node.path]
    if child then
      log.trace("merging node %q with new data", fs_node.path)
      child:_merge_new_data(fs_node)
      children[fs_node.path] = nil
    else
      log.trace("creating new node for %q", fs_node.path)
      child = Node:new(fs_node, self)
      child._clipboard_status = self._clipboard_status
      maybe_add_watcher(child)
    end
    return child
  end, fs.scan_dir(self.path))
  table.sort(self._children, self.node_comparator)
  self.empty = #self._children == 0
  maybe_add_watcher(self)
  -- remove any watchers for any children that was remomved
  for _, child in pairs(children) do
    if child:is_directory() then
      child:walk(maybe_remove_watcher)
      maybe_remove_watcher(child)
    end
  end
  self.scanned = true

  scheduler()
end

---@protected
---@param repo Yat.Git.Repo
function Node:_set_git_repo_on_node_and_children(repo)
  self.repo = repo
  if self._children then
    for _, child in ipairs(self._children) do
      if not child.repo then
        child:_set_git_repo_on_node_and_children(repo)
      end
    end
  end
end

---@param repo Yat.Git.Repo
function Node:set_git_repo(repo)
  local toplevel = repo.toplevel
  if toplevel == self.path then
    log.debug("node %q is the toplevel of repo %s, setting repo on node and all child nodes", self.path, tostring(repo))
    -- this node is the git toplevel directory, set the property on self
    self:_set_git_repo_on_node_and_children(repo)
  else
    log.debug("node %q is not the toplevel of repo %s, walking up the tree", self.path, tostring(repo))
    if #toplevel < #self.path then
      -- this node is below the git toplevel directory,
      -- walk the tree upwards until we hit the topmost node
      local node = self
      while node.parent and #toplevel <= #node.parent.path do
        node = node.parent --[[@as Yat.Node]]
      end
      log.debug("node %q is the top of the tree, setting repo on node and all child nodes", node.path, tostring(repo))
      node:_set_git_repo_on_node_and_children(repo)
    else
      log.error("git repo with toplevel %s is somehow below this node %s, this should not be possible", toplevel, self.path)
      log.error("self=%s", self)
      log.error("repo=%s", repo)
    end
  end
end

---@return Yat.Nodes.Type node_type
function Node:class()
  return self.__node_type
end

---@return Luv.FileType
function Node:type()
  return self._type
end

---@return boolean editable
function Node:is_editable()
  return self._type == "file"
end

---@return boolean
function Node:is_directory()
  return self._type == "directory"
end

---@return boolean
function Node:is_file()
  return self._type == "file"
end

---@return boolean
function Node:is_link()
  return self.link == true
end

---@return boolean
function Node:is_fifo()
  return self._type == "fifo"
end

---@return boolean
function Node:is_socket()
  return self._type == "socket"
end

---@return boolean
function Node:is_char_device()
  return self._type == "char"
end

---@return boolean
function Node:is_block_device()
  return self._type == "block"
end

---@async
---@return uv_fs_stat? stat
function Node:fs_stat()
  return fs.lstat(self.path)
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
function Node:has_children()
  return self._children ~= nil
end

---@generic T : Yat.Node
---@param self T
---@return T[] children
function Node.children(self)
  ---@cast self Yat.Node
  return self._children
end

---@return boolean
function Node:is_dotfile()
  return self.name:sub(1, 1) == "."
end

---@return boolean
function Node:is_git_ignored()
  return self.repo and self.repo:is_ignored(self.path, self._type) or false
end

---@return string|nil
function Node:git_status()
  return self.repo and self.repo:status_of(self.path, self._type)
end

---@return boolean
function Node:is_git_repository_root()
  return self.repo and self.repo.toplevel == self.path or false
end

---@param status Yat.Actions.Clipboard.Action|nil
function Node:set_clipboard_status(status)
  self._clipboard_status = status
  if self:is_directory() then
    for _, child in ipairs(self._children) do
      child:set_clipboard_status(status)
    end
  end
end

---@return Yat.Actions.Clipboard.Action|nil status
function Node:clipboard_status()
  return self._clipboard_status
end

---@return integer|nil
function Node:diagnostic_severity()
  return diagnostics.severity_of(self.path)
end

---@async
---@generic T : Yat.Node
---@param self T
---@param path string
---@return T? node
function Node.add_node(self, path)
  ---@cast self Yat.Node
  return self:_add_node(path, function(fs_node, parent)
    local node = self.__index.new(self.__index, fs_node, parent)
    if node:class() == "FileSystem" then
      maybe_add_watcher(node)
    end
    return node
  end)
end

---@async
---@protected
---@generic T : Yat.Node
---@param self T
---@param path string
---@param node_creator fun(fs_node: Yat.Fs.Node, parent: T): T
---@return T|nil node
function Node._add_node(self, path, node_creator)
  if not fs.exists(path) then
    log.error("no file node found for %q", path)
    return nil
  end

  ---@cast self Yat.Node
  local rest = path:sub(#self.path + 1)
  local splits = vim.split(rest, utils.os_sep, { plain = true, trimempty = true }) --[=[@as string[]]=]
  local node = self
  for i = 1, #splits do
    local name = splits[i]
    local found = false
    for _, child in ipairs(node._children) do
      if child.name == name then
        found = true
        node = child
        break
      end
    end
    if not found then
      local fs_node = fs.node_for(node.path .. utils.os_sep .. name)
      if fs_node then
        local child = node_creator(fs_node, node)
        log.debug("adding child %q to parent %q", child.path, node.path)
        node._children[#node._children + 1] = child
        node.empty = false
        table.sort(node._children, self.node_comparator)
        node = child
      else
        log.error("cannot create fs node for %q", node.path .. utils.os_sep .. name)
        return nil
      end
    end
  end

  scheduler()
  return node
end

---@param path string
function Node:remove_node(path)
  return self:_remove_node(path, false)
end

---@protected
---@param path string
---@param remove_empty_parents boolean
function Node:_remove_node(path, remove_empty_parents)
  local node = self:get_child_if_loaded(path)
  while node and node.parent and node ~= self do
    if node.parent and node.parent._children then
      for i = #node.parent._children, 1, -1 do
        local child = node.parent._children[i]
        if child == node then
          log.debug("removing child %q from parent %q", child.path, node.parent.path)
          if child.__node_type == "FileSystem" then
            maybe_remove_watcher(child)
          end
          table.remove(node.parent._children, i)
          break
        end
      end
      if #node.parent._children == 0 then
        node.parent.empty = true
        node = node.parent
        if not remove_empty_parents then
          return
        end
      else
        break
      end
    end
  end
end

---@param node Yat.Node
function Node:add_child(node)
  if self._children then
    self._children[#self._children + 1] = node
    self.empty = false
    table.sort(self._children, self.node_comparator)
  end
end

---@async
---@generic T : Yat.Node
---@param self T
---@param paths string[]
---@param node_creator async fun(path: string, parent: T, directory: boolean): T|nil
---@return T first_leaf_node
function Node.populate_from_paths(self, paths, node_creator)
  ---@cast self Yat.Node
  ---@type table<string, Yat.Node>
  local node_map = { [self.path] = self }

  ---@param path string
  ---@param parent Yat.Node
  ---@param directory boolean
  local function add_node(path, parent, directory)
    local node = node_creator(path, parent, directory)
    if node then
      parent:add_child(node)
      node_map[node.path] = node
    end
  end

  local min_path_size = #self.path
  for _, path in ipairs(paths) do
    local parents = Path:new(path):parents() --[=[@as string[]]=]
    for i = #parents, 1, -1 do
      local parent_path = parents[i]
      -- skip paths 'above' the root node
      if #parent_path > min_path_size then
        local parent = node_map[parent_path]
        if not parent then
          local grand_parent = node_map[parents[i + 1]]
          add_node(parent_path, grand_parent, true)
        end
      end
    end

    local parent = node_map[parents[1]]
    add_node(path, parent, false)
  end

  -- FIXME: doesn't take node:is_hidden into account
  local first_leaf_node = self
  while first_leaf_node and first_leaf_node._children do
    if first_leaf_node._children[1] then
      first_leaf_node = first_leaf_node._children[1]
    else
      break
    end
  end

  scheduler()
  return first_leaf_node
end

---@alias Yat.Nodes.HiddenReason "filter" | "git"

---@param config Yat.Config
---@return boolean hidden
---@return Yat.Nodes.HiddenReason? reason
function Node:is_hidden(config)
  if config.filters.enable then
    if config.filters.dotfiles and self:is_dotfile() then
      return true, "filter"
    elseif vim.tbl_contains(config.filters.custom, self.name) then
      return true, "filter"
    end
  end
  if not config.git.show_ignored then
    if self:is_git_ignored() then
      return true, "git"
    end
  end
  return false
end

---Returns an iterator function for this `node`'s children.
---@generic T : Yat.Node
---@param self T
---@param opts? { reverse?: boolean, from?: T }
---  - {opts.reverse?} `boolean`
---  - {opts.from?} T
---@return fun(): integer, T iterator
function Node.iterate_children(self, opts)
  ---@cast self Yat.Node
  local children = self._children
  if not children or #children == 0 then
    return function() end
  end

  opts = opts or {}
  local start = 0
  if opts.reverse then
    start = #children + 1
  end
  if opts.from then
    for i, child in ipairs(children) do
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
        return pos, children[pos]
      end
    end
  else
    return function()
      pos = pos + 1
      if pos <= #children then
        return pos, children[pos]
      end
    end
  end
end

---Collapses the node, if it is a container.
---@param opts? {children_only?: boolean, recursive?: boolean}
---  - {opts.children_only?} `boolean`
---  - {opts.recursive?} `boolean`
function Node:collapse(opts)
  opts = opts or {}
  if self._children then
    if not opts.children_only then
      self.expanded = false
    end

    if opts.recursive then
      for _, child in ipairs(self._children) do
        child:collapse({ recursive = opts.recursive })
      end
    end
  end
end

---Expands the node, if it is a container. If the node hasn't been scanned before, will scan the directory.
---@async
---@generic T : Yat.Node
---@param self T
---@param opts? {force_scan?: boolean, to?: string}
---  - {opts.force_scan?} `boolean` rescan directories.
---  - {opts.to?} `string` recursively expand to the specified path and return it.
---@return T|nil node if {opts.to} is specified, and found.
function Node.expand(self, opts)
  ---@cast self Yat.Node
  log.debug("expanding %q", self.path)
  opts = opts or {}
  if self:is_directory() then
    if not self.scanned or opts.force_scan then
      self:_scandir()
    end
    self.expanded = true
  end

  if opts.to then
    if self.path == opts.to then
      log.debug("self %q is equal to path %q", self.path, opts.to)
      return self
    elseif self:is_ancestor_of(opts.to) then
      for _, child in ipairs(self._children) do
        if child:is_ancestor_of(opts.to) then
          log.debug("child node %q is parent of %q", child.path, opts.to)
          return child:expand(opts)
        elseif child.path == opts.to then
          if child:is_directory() then
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
---@generic T :Yat.Node
---@param self T
---@param path string
---@return T|nil
function Node.get_child_if_loaded(self, path)
  local self_path = self.path --[[@as string]]
  if self_path == path then
    return self
  end
  if not self:is_directory() then
    return
  end

  if self:is_ancestor_of(path) then
    for _, child in ipairs(self._children) do
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
  ---@param node Yat.Node
  ---@param recurse boolean
  ---@param refresh_git boolean
  ---@param refreshed_git_repos table<string, boolean>
  local function refresh_directory_node(node, recurse, refresh_git, refreshed_git_repos)
    if refresh_git and node.repo and not refreshed_git_repos[node.repo.toplevel] then
      node.repo:refresh_status({ ignored = true })
      refreshed_git_repos[node.repo.toplevel] = true
    end
    ---@diagnostic disable-next-line:invisible
    if node.scanned then
    ---@diagnostic disable-next-line:invisible
      node:_scandir()

      if recurse then
        for _, child in ipairs(node:children()) do
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
      if fs_node then
        self:_merge_new_data(fs_node)
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
        self.repo:refresh_status_for_path(self.path)
      end
    end
  end
end

return Node
