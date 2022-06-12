local Path = require("plenary.path")

local fs = require("ya-tree.filesystem")
local git = require("ya-tree.git")
local utils = require("ya-tree.utils")
local log = require("ya-tree.log")

local M = {}

---@alias YaTreeNodeType "FileSystem"|"Buffer"|"GitStatus"

---@class YaTreeNode : FsNode
---@field public parent? YaTreeNode
---@field private type file_type
---@field public children? YaTreeNode[]
---@field public empty? boolean
---@field public extension? string
---@field public executable? boolean
---@field public link boolean
---@field public link_to? string
---@field public link_name? string
---@field public link_extension? string
---@field public repo? GitRepo
---@field public clipboard_status clipboard_action|nil
---@field private scanned? boolean
---@field public expanded? boolean
---@field public depth number
---@field public last_child boolean
local Node = { __node_type = "FileSystem" }
Node.__index = Node

---@param n1 YaTreeNode
---@param n2 YaTreeNode
---@return boolean
Node.__eq = function(n1, n2)
  return n1.path and n1.path == n2.path or false
end

---@param self YaTreeNode
---@return string
Node.__tostring = function(self)
  return self.path
end

---Creates a new node.
---@param fs_node FsDirectoryNode|FsFileNode|FsDirectoryLinkNode|FsFileLinkNode filesystem data.
---@param parent? YaTreeNode the parent node.
---@return YaTreeNode node
function Node:new(fs_node, parent)
  ---@type YaTreeNode
  local this = setmetatable(fs_node, self)

  this.parent = parent
  if this:is_directory() then
    this.children = {}
  end

  -- inherit any git repo
  if parent and parent.repo then
    this.repo = parent.repo
  end

  log.trace("created node %s", this)

  return this
end

---Creates a new node tree root.
---@async
---@param path string the path
---@param old_root? YaTreeNode the previous root
---@param check_for_git_repo? boolean whether to check for a git repo in `path`
---@return YaTreeNode root
function M.root(path, old_root, check_for_git_repo)
  local root = Node:new(fs.node_for(path))

  if check_for_git_repo then
    local repo = git.create_repo(root.path)
    if repo then
      log.debug("node %q is in a git repo with toplevel %q", root.path, repo.toplevel)
      root.repo = repo
      root.repo:refresh_status({ ignored = true })
    end
  end

  -- if the tree root was moved on level up, i.e the new root is the parent of the old root, add it to the tree
  if old_root and Path:new(old_root.path):parent().filename == root.path then
    root.children = { old_root }
    old_root.parent = root
    local repo = old_root.repo
    if repo and root.path:find(repo.toplevel, 1, true) then
      root.repo = repo
    end
  end

  -- force scan of the directory
  root:expand({ force_scan = true })

  return root
end

---@private
---@param fs_node FsDirectoryNode|FsFileNode|FsDirectoryLinkNode|FsFileLinkNode filesystem data.
function Node:_merge_new_data(fs_node)
  for k, v in pairs(fs_node) do
    if type(self[k]) ~= "function" then
      self[k] = v
    else
      log.error("fs_node.%s is a function, this should not happen!", k)
    end
  end
end

---@private
function Node:_scandir()
  log.debug("scanning directory %q", self.path)
  -- keep track of the current children
  ---@type table<string, YaTreeNode>
  local children = {}
  for _, child in ipairs(self.children) do
    children[child.path] = child
  end

  ---@param fs_node FsDirectoryNode|FsFileNode|FsDirectoryLinkNode|FsFileLinkNode
  self.children = vim.tbl_map(function(fs_node)
    local child = children[fs_node.path]
    if child then
      log.trace("merging %q", fs_node.path)
      child:_merge_new_data(fs_node)
      return child
    else
      log.trace("creating new %q", fs_node.path)
      return Node:new(fs_node, self)
    end
  end, fs.scan_dir(self.path))

  self.empty = #self.children == 0
  self.scanned = true
end

---@param repo GitRepo
---@param node YaTreeNode
local function set_git_repo_on_node_and_children(repo, node)
  log.debug("setting repo on node %s", node.path)
  node.repo = repo
  if node.children then
    for _, child in ipairs(node.children) do
      if not child.repo then
        set_git_repo_on_node_and_children(repo, child)
      end
    end
  end
end

---@async
---@return boolean is_git_repo whether a git repo was detected, returns `false` if a repo *already* exists
function Node:check_for_git_repo()
  if self.repo and not self.repo:is_yadm() then
    return false
  end

  local repo = git.create_repo(self.path)
  if repo then
    repo:refresh_status({ ignored = true })
    local toplevel = repo.toplevel
    if toplevel == self.path then
      -- this node is the git toplevel directory, set the property on self
      set_git_repo_on_node_and_children(repo, self)
    else
      if #toplevel < #self.path then
        -- this node is below the git toplevel directory,
        -- walk the tree upwards until we hit the topmost node
        local node = self
        while node.parent and #toplevel <= #node.parent.path do
          node = node.parent
        end
        set_git_repo_on_node_and_children(repo, node)
      else
        log.error("git repo with toplevel %s is somehow below this node %s, this should not be possible", toplevel, self.path)
        log.error("self=%s", self)
        log.error("repo=%s", repo)
      end
    end
    return true
  else
    log.debug("path %s is not in a git repository", self.path)
    return false
  end
end

---@return YaTreeNodeType node_type
function Node:node_type()
  return self.__node_type
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

---@param path string
---@return boolean
function Node:is_ancestor_of(path)
  return self:is_directory() and #self.path < #path and path:find(self.path .. utils.os_sep, 1, true) ~= nil
end

---@return boolean
function Node:is_empty()
  return self.empty or false
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
function Node:get_git_status()
  return self.repo and self.repo:status_of(self.path)
end

---@return boolean
function Node:is_git_repository_root()
  return self.repo and self.repo.toplevel == self.path or false
end

---@param status? clipboard_action
function Node:set_clipboard_status(status)
  self.clipboard_status = status
end

---@alias not_display_reason "filter"|"git"

---@param config YaTreeConfig
---@return boolean displayable, not_display_reason? reason
function Node:is_displayable(config)
  if config.filters.enable then
    if config.filters.dotfiles and self:is_dotfile() then
      return false, "filter"
    elseif config.filters.custom[self.name] then
      return false, "filter"
    end
  end

  if not config.git.show_ignored then
    if self:is_git_ignored() then
      return false, "git"
    end
  end

  return true
end

do
  ---@type table<string, number>
  local diagnostics = {}

  ---@param new_diagnostics table<string, number>
  ---@return table<string, number> previous_diagnostics
  function M.set_diagnostics(new_diagnostics)
    local previous_diagnostics = diagnostics
    diagnostics = new_diagnostics
    return previous_diagnostics
  end

  ---@return number|nil
  function Node:get_diagnostics_severity()
    return diagnostics[self.path]
  end
end

---Returns an iterator function for this `node`s children.
--
---@param opts? { reverse?: boolean, from?: YaTreeNode }
---  - {opts.reverse?} `boolean`
---  - {opts.from?} `YatreeNode`
---@return fun():YaTreeNode iterator
function Node:iterate_children(opts)
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

---Collapses the node, if it is a directory.
--
---@param opts? {children_only?: boolean, recursive?: boolean}
---  - {opts.children_only?} `boolean`
---  - {opts.recursive?} `boolean`
function Node:collapse(opts)
  opts = opts or {}
  if self:is_directory() then
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

---Expands the node, if it is a directory. If the node hasn't been scanned before, will scan the directory.
--
---@param opts? {force_scan?: boolean, to?: string}
---  - {opts.force_scan?} `boolean` rescan directories.
---  - {opts.to?} `string` recursively expand to the specified path and return it.
---@return YaTreeNode|nil node #if {opts.to} is specified, and found.
function Node:expand(opts)
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
    elseif self:is_directory() and self:is_ancestor_of(opts.to) then
      for _, node in ipairs(self.children) do
        if node:is_ancestor_of(opts.to) then
          log.debug("child node %q is parent of %q", node.path, opts.to)
          return node:expand(opts)
        elseif node.path == opts.to then
          return node:is_directory() and node:expand(opts) or node
        end
      end
    else
      log.debug("node %q is not a parent of path %q", self.path, opts.to)
    end
  end
end

---Returns the child node specified by `path` if it has been loaded.
--
---@param path string
---@return YaTreeNode|nil
function Node:get_child_if_loaded(path)
  if self.path == path then
    return self
  end
  if not self:is_directory() then
    return
  end

  if self:is_ancestor_of(path) then
    for _, node in ipairs(self.children) do
      if node.path == path then
        return node
      elseif node:is_ancestor_of(path) then
        return node:get_child_if_loaded(path)
      end
    end
  end
end

---@async
---@param node YaTreeNode
---@param recurse boolean
---@param refresh_git boolean
---@param refreshed_git_repos table<string, boolean>
local function refresh_node(node, recurse, refresh_git, refreshed_git_repos)
  if node:is_directory() and node.scanned then
    if refresh_git and node.repo and not refreshed_git_repos[node.repo.toplevel] then
      node.repo:refresh_status({ ignored = true })
      refreshed_git_repos[node.repo.toplevel] = true
    end
    node:_scandir()

    if recurse then
      for _, child in ipairs(node.children) do
        refresh_node(child, true, refresh_git, refreshed_git_repos)
      end
    end
  end
end

---@async
---@param opts? { recurse?: boolean, refresh_git?: boolean }
---  - {opts.recurse?} `boolean` whether to perform a recursive refresh, default: `false`.
---  - {opts.refresh_git?} `boolean` whether to refrsh the git status, default: `false`.
function Node:refresh(opts)
  opts = opts or {}
  local recurse = opts.recurse or false
  local refresh_git = opts.refresh_git or false
  log.debug("refreshing %q, recurse=%s, refresh_git=%s", self.path, recurse, refresh_git)

  if self:is_directory() then
    refresh_node(self, recurse, refresh_git, {})
  else
    local fs_node = fs.node_for(self.path)
    if fs_node then
      self:_merge_new_data(fs_node)
      if refresh_git and self.repo then
        self.repo:refresh_status_for_file(self.path)
      end
    end
  end
end

---@generic T : YaTreeNode
---@param root T
---@param paths string[]
---@param node_creator fun(fs_node: FsDirectoryNode|FsFileNode|FsDirectoryLinkNode|FsFileLinkNode, parent: T): T
---@return T first_leaf_node
local function create_tree_from_paths(root, paths, node_creator)
  ---@type table<string, YaTreeNode>
  local node_map = {}
  ---@cast root YaTreeNode
  node_map[root.path] = root

  ---@param fs_node FsNode
  ---@param parent YaTreeNode
  local function add_node(fs_node, parent)
    local node = node_creator(fs_node, parent)
    parent.children[#parent.children + 1] = node
    table.sort(parent.children, fs.fs_node_comparator)
    node_map[node.path] = node
  end

  local min_path_size = #root.path
  for _, path in ipairs(paths) do
    local parents
    ---@type string[]
    parents = Path:new(path):parents()
    for i = #parents, 1, -1 do
      local parent_path = parents[i]
      -- skip paths above the node we are searching from
      if #parent_path > min_path_size then
        local parent = node_map[parent_path]
        if not parent then
          local grand_parent = node_map[parents[i + 1]]
          local fs_node = fs.node_for(parent_path)
          if fs_node then
            add_node(fs_node, grand_parent)
          end
        end
      end
    end

    local parent = node_map[parents[1]]
    local fs_node = fs.node_for(path)
    if fs_node then
      add_node(fs_node, parent)
    end
  end

  local first_leaf_node = root
  while first_leaf_node and first_leaf_node:is_directory() do
    if first_leaf_node.children and first_leaf_node.children[1] then
      first_leaf_node = first_leaf_node.children and first_leaf_node.children[1]
    else
      break
    end
  end

  return first_leaf_node
end

---@class YaTreeSearchNode : YaTreeNode
---@field public search_term string

---Creates a separate node tree from the `paths`, with a copy of this `Node` as the root.
---@param paths string[]
---@return YaTreeSearchNode root, YaTreeNode first_leaf_node
function Node:create_search_tree_from_paths(paths)
  local root = Node:new({
    name = self.name,
    type = self.type,
    path = self.path,
    children = {},
    expanded = true,
  })
  local repo = self.repo
  if repo then
    root.repo = repo
  end

  return root,
    create_tree_from_paths(root, paths, function(fs_node, parent)
      local node = Node:new(fs_node, parent)
      if node:is_directory() then
        node.scanned = true
        node.expanded = true
      end
      local child = root:get_child_if_loaded(node.path)
      if child and child.repo then
        node.repo = child.repo
      end
      return node
    end)
end

---@class YaTreeBufferNode : YaTreeNode
---@field private super YaTreeNode
---@field public parent? YaTreeBufferNode
---@field public bufnr? number
---@field public children? YaTreeBufferNode[]
local BufferNode = { super = Node, __node_type = "Buffer" }
BufferNode.__index = BufferNode
BufferNode.__tostring = Node.__tostring
BufferNode.__eq = Node.__eq
setmetatable(BufferNode, { __index = Node })

---Creates a new buffer node.
---@param fs_node FsDirectoryNode|FsFileNode|FsDirectoryLinkNode|FsFileLinkNode filesystem data.
---@param bufnr number the buffer number.
---@param parent? YaTreeBufferNode the parent node.
---@return YaTreeBufferNode node
function BufferNode:new(fs_node, bufnr, parent)
  ---@type YaTreeBufferNode
  local this = Node.new(self, fs_node, parent)
  this.bufnr = bufnr
  if this:is_directory() then
    this.scanned = true
    this.expanded = true
  end
  return this
end

---@private
function BufferNode:_scandir() end

---@return true
function BufferNode:is_displayable()
  return true
end

---@generic T : YaTreeBufferNode|YaTreeGitStatusNode
---@param root T
---@param file string
---@param node_creator fun(fs_node: FsDirectoryNode|FsFileNode|FsDirectoryLinkNode|FsFileLinkNode, parent: T): T
---@return T node
local function add_node(root, file, node_creator)
  if not fs.exists(file) then
    log.error("no file node found for %q", file)
    return
  end

  ---@cast root YaTreeBufferNode|YaTreeGitStatusNode
  local rest = file:sub(#root.path + 1)
  ---@type string[]
  local splits = vim.split(rest, utils.os_sep, { plain = true, trimempty = true })
  local node = root
  for i = 1, #splits do
    local name = splits[i]
    local found = false
    for _, child in ipairs(node.children) do
      ---@cast child YaTreeBufferNode|YaTreeGitStatusNode
      if child.name == name then
        found = true
        node = child
        break
      end
    end
    if not found then
      local child = node_creator(fs.node_for(node.path .. utils.os_sep .. name), node)
      node.children[#node.children + 1] = child
      table.sort(node.children, fs.fs_node_comparator)
      node = child
    end
  end
  return node
end

---@param file string
---@param bufnr number
---@return YaTreeBufferNode node
function BufferNode:add_buffer(file, bufnr)
  return add_node(self, file, function(fs_node, parent)
    return BufferNode:new(fs_node, fs_node.path == file and bufnr or nil, parent)
  end)
end

---@param root YaTreeBufferNode|YaTreeGitStatusNode
---@param file string
local function remove_node(root, file)
  local node = root:get_child_if_loaded(file)
  if node then
    while node and node.parent and node ~= root do
      if node.parent and node.parent.children then
        for index, child in ipairs(node.parent.children) do
          if child == node then
            table.remove(node.parent.children, index)
            break
          end
        end
        if #node.parent.children == 0 then
          node = node.parent
        else
          break
        end
      end
    end
  end
end

---@param file string
function BufferNode:remove_buffer(file)
  remove_node(self, file)
end

---Creates a buffer node tree from the `paths`, with `root_path` as the root.
---@param tree_root_path string
---@return YaTreeBufferNode root, YaTreeBufferNode first_leaf_node
function M.create_buffer_tree_from_paths(tree_root_path)
  local buffers = utils.get_current_buffers()
  ---@type string
  local root_path
  ---@type string
  local paths = vim.tbl_keys(buffers)
  local size = #paths
  if size == 0 then
    root_path = tree_root_path
  elseif size == 1 then
    root_path = Path:new(paths[1]):parent().filename
  else
    root_path = utils.find_common_ancestor(paths) or tree_root_path
  end
  if root_path:find(tree_root_path .. utils.os_sep, 1, true) ~= nil then
    root_path = tree_root_path
  end
  log.debug("creating buffer tree rooted in %q", root_path)

  local root = BufferNode:new(fs.node_for(root_path))
  root.repo = git.get_repo_for_path(root_path)

  return root,
    create_tree_from_paths(root, paths, function(fs_node, parent)
      local node = BufferNode:new(fs_node, buffers[fs_node.path], parent)
      if parent.repo and not parent.repo:is_yadm() then
        node.repo = parent.repo
      else
        node.repo = git.get_repo_for_path(node.path)
      end
      return node
    end)
end

---@class YaTreeGitStatusNode : YaTreeNode
---@field private super YaTreeNode
---@field public parent? YaTreeGitStatusNode
---@field public children? YaTreeGitStatusNode[]
local GitStatusNode = { super = Node, __node_type = "GitStatus" }
GitStatusNode.__index = GitStatusNode
GitStatusNode.__tostring = Node.__tostring
GitStatusNode.__eq = Node.__eq
setmetatable(GitStatusNode, { __index = Node })

---Creates a new git status node.
---@param fs_node FsDirectoryNode|FsFileNode|FsDirectoryLinkNode|FsFileLinkNode filesystem data.
---@param parent? YaTreeGitStatusNode the parent node.
---@return YaTreeGitStatusNode node
function GitStatusNode:new(fs_node, parent)
  ---@type YaTreeGitStatusNode
  local this = Node.new(self, fs_node, parent)
  if this:is_directory() then
    this.scanned = true
    this.expanded = true
  end
  return this
end

---@private
function GitStatusNode:_scandir() end

---@async
---@return YaTreeGitStatusNode first_leaf_node
function GitStatusNode:refresh()
  self.repo:refresh_status({ ignored = true })
  local git_status = self.repo:git_status()
  ---@type string[]
  local paths = {}
  for path in pairs(git_status) do
    if self:is_ancestor_of(path) then
      paths[#paths + 1] = path
    end
  end

  self.children = {}
  return create_tree_from_paths(self, paths, function(fs_node, parent)
    return GitStatusNode:new(fs_node, parent)
  end)
end

---@param node YaTreeGitStatusNode
---@return boolean displayable
local function is_any_child_displayable(node)
  for _, child in ipairs(node.children) do
    ---@cast child YaTreeGitStatusNode
    if child:is_directory() and is_any_child_displayable(child) then
      return true
    elseif not child:is_git_ignored() then
      return true
    end
  end
  return false
end

---@param config YaTreeConfig
---@return boolean displayable, not_display_reason? reason
function GitStatusNode:is_displayable(config)
  if not config.git.show_ignored then
    if self:is_git_ignored() or (self:is_directory() and not is_any_child_displayable(self)) then
      return false, "git"
    end
  end

  return true
end

---@param file string
---@return YaTreeGitStatusNode node
function GitStatusNode:add_file(file)
  return add_node(self, file, function(fs_node, parent)
    return GitStatusNode:new(fs_node, parent)
  end)
end

---@param file string
function GitStatusNode:remove_file(file)
  remove_node(self, file)
end

---Creates a git status node tree from the `paths`, with `root_path` as the root.
---@async
---@param root_path string
---@param repo GitRepo
---@return YaTreeGitStatusNode root, YaTreeGitStatusNode first_leaft_node
function M.create_git_status_tree_from_paths(root_path, repo)
  log.debug("creating git status tree rooted in %q", root_path)
  local root = GitStatusNode:new(fs.node_for(root_path))
  root.repo = repo
  return root, root:refresh()
end

---@param fn fun(node: YaTreeNode):boolean called for each node, if the function returns `true` the `walk` terminates.
function Node:walk(fn)
  if fn(self) then
    return
  end

  if self:is_directory() then
    for _, child in ipairs(self.children) do
      if child:walk(fn) then
        return
      end
    end
  end
end

return M
