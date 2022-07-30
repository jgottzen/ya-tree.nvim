local scheduler = require("plenary.async.util").scheduler
local wrap = require("plenary.async").wrap
local Path = require("plenary.path")

local fs = require("ya-tree.filesystem")
local job = require("ya-tree.job")
local git = require("ya-tree.git")
local utils = require("ya-tree.utils")
local log = require("ya-tree.log")

local fn = vim.fn

local M = {}

---@alias YaTreeNodeType "FileSystem" | "Search" | "Buffer" | "GitStatus"

---@class YaTreeNode : FsNode
---@field private __node_type YaTreeNodeType
---@field public parent? YaTreeNode
---@field private type file_type
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
---@generic T : YaTreeNode
---@param class `T`
---@param fs_node FsNode filesystem data.
---@param parent? `T` the parent node.
---@return `T` node
local function create_node(class, fs_node, parent)
  local this = setmetatable(fs_node, class) --[[@as YaTreeNode]]
  ---@cast parent YaTreeNode?
  this.parent = parent
  if this:is_container() then
    this.children = {}
  end

  -- inherit any git repo
  if parent and parent.repo then
    this.repo = parent.repo
  end

  log.trace("created node %s", this)

  return this
end

---Creates a new node.
---@param fs_node FsNode filesystem data.
---@param parent? YaTreeNode the parent node.
---@return YaTreeNode node
function Node:new(fs_node, parent)
  return create_node(self, fs_node, parent)
end

---Creates a new node tree root.
---@async
---@param path string the path
---@param old_root? YaTreeNode the previous root
---@return YaTreeNode root
function M.root(path, old_root)
  local fs_node = fs.node_for(path) --[[@as FsNode]]
  local root = Node:new(fs_node)

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

---@private
---@param a YaTreeNode
---@param b YaTreeNode
---@return boolean
function Node._node_comparator(a, b)
  if a:is_container() and not b:is_container() then
    return true
  elseif b:is_container() then
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
  table.sort(self.children, self._node_comparator)
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
  function Node:diagnostics_severity()
    return diagnostics[self.path]
  end
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

---@async
---@generic T : YaTreeNode
---@param root `T`
---@param paths string[]
---@param node_creator async fun(path: string, parent: `T`): `T`|nil
---@return `T` first_leaf_node
local function create_tree_from_paths(root, paths, node_creator)
  ---@cast root YaTreeNode
  ---@type table<string, YaTreeNode>
  local node_map = { [root.path] = root }

  ---@param path string
  ---@param parent YaTreeNode
  local function add_node(path, parent)
    local node = node_creator(path, parent)
    if node then
      parent.children[#parent.children + 1] = node
      table.sort(parent.children, root._node_comparator)
      node_map[node.path] = node
    end
  end

  local min_path_size = #root.path
  for _, path in ipairs(paths) do
    if fs.exists(path) then
      ---@type string[]
      local parents = Path:new(path):parents()
      for i = #parents, 1, -1 do
        local parent_path = parents[i]
        -- skip paths 'above' the root node
        if #parent_path > min_path_size then
          local parent = node_map[parent_path]
          if not parent then
            local grand_parent = node_map[parents[i + 1]]
            add_node(parent_path, grand_parent)
          end
        end
      end

      local parent = node_map[parents[1]]
      add_node(path, parent)
    end
  end

  local first_leaf_node = root
  while first_leaf_node and first_leaf_node:is_container() do
    if first_leaf_node.children and first_leaf_node.children[1] then
      first_leaf_node = first_leaf_node.children[1]
    else
      break
    end
  end

  scheduler()
  return first_leaf_node
end

---@class YaTreeSearchNode : YaTreeNode
---@field public parent? YaTreeSearchNode
---@field public children? YaTreeSearchNode[]
local SearchNode = { __node_type = "Search" }
SearchNode.__index = SearchNode
SearchNode.__tostring = Node.__tostring
SearchNode.__eq = Node.__eq
setmetatable(SearchNode, { __index = Node })

---@class YaTreeSearchRootNode : YaTreeSearchNode
---@field public search_term string
---@field private _search_options { cmd: string, args: string[] }

---Creates a new search node.
---@param fs_node FsNode filesystem data.
---@param parent? YaTreeSearchNode the parent node.
---@return YaTreeSearchNode node
function SearchNode:new(fs_node, parent)
  local this = create_node(self, fs_node, parent)
  if this:is_directory() then
    this.scanned = true
    this.expanded = true
  end
  return this
end

---@private
function SearchNode:_scandir() end

do
  ---@param path string
  ---@param cmd string
  ---@param args string[]
  ---@param callback fun(stdout?: string[], stderr?: string)
  ---@type async fun(path: string, cmd: string, args: string[]): string[]?,string
  local search = wrap(function(path, cmd, args, callback)
    log.debug("searching for %q in %q", cmd, path)

    job.run({ cmd = cmd, args = args, cwd = path }, function(code, stdout, stderr)
      if code == 0 then
        ---@type string[]
        local lines = vim.split(stdout or "", "\n", { plain = true, trimempty = true })
        log.debug("%q found %s matches for %q in %q", cmd, #lines, cmd, path)
        callback(lines)
      else
        log.error("%q with args %s failed with code %s and message %s", cmd, args, code, stderr)
        callback(nil, stderr)
      end
    end)
  end, 4)

  ---@async
  ---@param term? string
  ---@param cmd? string
  ---@param args? string[]
  ---@return YaTreeSearchNode|nil first_leaf_node
  ---@return number|string matches_or_error
  function SearchNode:search(term, cmd, args)
    if self.parent then
      return self.parent:search(term, cmd, args)
    end

    ---@cast self YaTreeSearchRootNode
    self.search_term = term and term or self.search_term
    self._search_options = cmd and { cmd = cmd, args = args } or self._search_options
    if not self.search_term or not self._search_options then
      return nil, "No search term or command supplied"
    end

    self.children = {}
    local paths, err = search(self.path, self._search_options.cmd, self._search_options.args)
    if paths then
      local first_leaf_node = create_tree_from_paths(self, paths, function(path, parent)
        local fs_node = fs.node_for(path)
        if fs_node then
          local node = SearchNode:new(fs_node, parent)
          if not parent.repo or parent.repo:is_yadm() then
            node.repo = git.get_repo_for_path(node.path)
          end
          return node
        end
      end)
      return first_leaf_node, #paths
    else
      return nil, err
    end
  end
end

---@async
function SearchNode:refresh()
  if self.parent then
    self.parent:refresh()
  else
    ---@cast self YaTreeSearchRootNode
    if self.search_term and self._search_options then
      self:search()
    end
  end
end

---Creates a search node tree, with `root_path` as the root node.
---@async
---@param root_path string
---@param term string
---@param cmd string
---@param args string[]
---@return YaTreeSearchRootNode root
---@return YaTreeSearchNode|nil first_leaf_node
---@return number|string matches_or_error
function M.create_search_tree(root_path, term, cmd, args)
  local fs_node = fs.node_for(root_path) --[[@as FsNode]]
  local root = SearchNode:new(fs_node) --[[@as YaTreeSearchRootNode]]
  root.repo = git.get_repo_for_path(root_path)
  return root, root:search(term, cmd, args)
end

---@alias buffer_type file_type | "terminal" | "container"

---@class YaTreeBufferNode : YaTreeNode
---@field public parent? YaTreeBufferNode
---@field private type buffer_type
---@field public bufname? string
---@field public bufnr? number
---@field public hidden? boolean
---@field public children? YaTreeBufferNode[]
local BufferNode = { __node_type = "Buffer" }
BufferNode.__index = BufferNode
BufferNode.__tostring = Node.__tostring
BufferNode.__eq = Node.__eq
setmetatable(BufferNode, { __index = Node })

---Creates a new buffer node.
---@param fs_node FsNode filesystem data.
---@param bufname? string the vim buffer name.
---@param bufnr? number the buffer number.
---@param hidden? boolean if the buffer is listed.
---@param parent? YaTreeBufferNode the parent node.
---@return YaTreeBufferNode node
function BufferNode:new(fs_node, bufname, bufnr, hidden, parent)
  local this = create_node(self, fs_node, parent)
  this.bufname = bufname
  this.bufnr = bufnr
  this.hidden = hidden
  if this:is_container() then
    this.scanned = true
    this.expanded = true
  end
  return this
end

---@return boolean is_container
function BufferNode:is_container()
  return self.type == "container" or self.type == "directory"
end

---@return boolean is_terminal
function BufferNode:is_terminal()
  return self.type == "terminal"
end

---@return number? id
function BufferNode:get_toggleterm_id()
  if self.type == "terminal" then
    return self.bufname:match("#toggleterm#(%d+)$")
  end
end

---@private
function BufferNode:_scandir() end

---@param container YaTreeBufferNode
---@return boolean is_container
local function is_terminals_container(container)
  return container and container.type == "container" and container.extension == "terminal" or false
end

---Expands the node, if it is a directory.
--
---@async
---@param opts? {force_scan?: boolean, all?: boolean, to?: string}
---  - {opts.force_scan?} `boolean` rescan directories.
---  - {opts.to?} `string` recursively expand to the specified path and return it.
---@return YaTreeBufferNode|nil node if {opts.to} is specified, and found.
function BufferNode:expand(opts)
  opts = opts or {}
  if opts.to and vim.startswith(opts.to, "term://") then
    if self.parent then
      return self.parent:expand(opts)
    else
      if self.children then
        local container = self.children[#self.children]
        if is_terminals_container(container) then
          for _, child in ipairs(container.children) do
            if child.bufname == opts.to then
              return child
            end
          end
        end
      end
    end
  else
    return Node.expand(self, opts)
  end
end

---@param tree_root_path string
---@param paths string[]
---@return string root_path
local function get_buffers_root_path(tree_root_path, paths)
  local root_path
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
  return root_path
end

---@param parent YaTreeBufferNode
---@return YaTreeBufferNode container
local function create_terminal_buffers_container(parent)
  local container = BufferNode:new({
    name = "Terminals",
    type = "container",
    path = "Terminals",
    extension = "terminal",
  }, nil, nil, nil, parent)
  parent.children[#parent.children + 1] = container
  return container
end

---@param container YaTreeBufferNode
---@param terminal TerminalBufferData
---@return YaTreeBufferNode node
local function add_terminal_buffer_to_container(container, terminal)
  local name = terminal.name:match("term://(.*)//.*")
  local path = fn.fnamemodify(name, ":p")
  local bufinfo = fn.getbufinfo(terminal.bufnr)
  local hidden = bufinfo[1] and bufinfo[1].hidden == 1 or false
  local node = BufferNode:new({
    name = name,
    type = "terminal",
    path = path,
    extension = "terminal",
  }, terminal.name, terminal.bufnr, hidden, container)
  container.children[#container.children + 1] = node
  log.debug("adding terminal buffer %s (%q)", node.bufnr, node.bufname)
  return node
end

---@async
---@param opts? { root_path?: string }
--- -- {opts.root_path?} `string`
---@return YaTreeBufferNode first_leaf_node
function BufferNode:refresh(opts)
  -- only refresh in the root of the tree
  if self.parent then
    return self.parent:refresh(opts)
  end

  opts = opts or {}
  scheduler()
  local buffers, terminals = utils.get_current_buffers()
  ---@type string[]
  local paths = vim.tbl_keys(buffers)
  local root_path = get_buffers_root_path(opts.root_path or self.path, paths)
  if root_path ~= self.path then
    log.debug("setting new root path to %q", root_path)
    local fs_node = fs.node_for(root_path)
    ---@cast fs_node -?
    self:_merge_new_data(fs_node)
    self.expanded = true
    self.scanned = true
    self.repo = git.get_repo_for_path(root_path)
  end

  self.children = {}
  local first_leaf_node = create_tree_from_paths(self, paths, function(path, parent)
    local fs_node = fs.node_for(path)
    if fs_node then
      local is_buffer_node = buffers[fs_node.path] ~= nil
      local node = BufferNode:new(fs_node, is_buffer_node and path or nil, buffers[fs_node.path], false, parent)
      if not parent.repo or parent.repo:is_yadm() then
        node.repo = git.get_repo_for_path(node.path)
      end
      return node
    end
  end)

  if #terminals > 0 then
    local container = create_terminal_buffers_container(self)
    for _, terminal in ipairs(terminals) do
      add_terminal_buffer_to_container(container, terminal)
    end
    if first_leaf_node == self then
      first_leaf_node = container.children[1]
    end
  end

  return first_leaf_node
end

---@async
---@generic T : YaTreeBufferNode|YaTreeGitStatusNode
---@param root `T`
---@param file string
---@param node_creator fun(fs_node: FsNode, parent: `T`): `T`
---@return `T`|nil node
local function add_fs_node(root, file, node_creator)
  if not fs.exists(file) then
    log.error("no file node found for %q", file)
    return nil
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
        node.children[#node.children + 1] = child
        table.sort(node.children, root._node_comparator)
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

---@async
---@param file string
---@param bufnr number
---@return YaTreeBufferNode|nil node
function BufferNode:add_buffer(file, bufnr)
  if self.parent then
    return self.parent:add_buffer(file, bufnr)
  else
    if vim.startswith(file, "term://") then
      local container = self.children[#self.children]
      if not is_terminals_container(container) then
        container = create_terminal_buffers_container(self)
      end
      return add_terminal_buffer_to_container(container, { name = file, bufnr = bufnr })
    else
      return add_fs_node(self, file, function(fs_node, parent)
        local is_buffer_node = fs_node.path == file
        local node = BufferNode:new(fs_node, is_buffer_node and file or nil, is_buffer_node and bufnr or nil, false, parent)
        if not parent.repo or parent.repo:is_yadm() then
          node.repo = git.get_repo_for_path(node.path)
        end
        if is_buffer_node then
          log.debug("adding buffer %s (%q)", node.bufnr, node.bufname)
        end
        return node
      end)
    end
  end
end

---@param file string
---@param bufnr number
---@param hidden boolean
function BufferNode:set_terminal_hidden(file, bufnr, hidden)
  if self.parent then
    self.parent:set_terminal_hidden(file, bufnr, hidden)
  else
    local container = self.children[#self.children]
    if is_terminals_container(container) then
      for _, child in ipairs(container.children) do
        if child.bufname == file and child.bufnr == bufnr then
          child.hidden = hidden
          log.debug("setting buffer %s (%q) 'hidden' to %q", child.bufnr, child.bufname, hidden)
          break
        end
      end
    end
  end
end

---@param root YaTreeBufferNode|YaTreeGitStatusNode
---@param file string
local function remove_fs_node(root, file)
  local node = root:get_child_if_loaded(file)
  while node and node.parent and node ~= root do
    if node.parent and node.parent.children then
      for index, child in ipairs(node.parent.children) do
        if child == node then
          log.debug("removing child %q from parent %q", child.path, node.parent.path)
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

---@param file string
---@param bufnr number
function BufferNode:remove_buffer(file, bufnr)
  if self.parent then
    self.parent:remove_buffer(file, bufnr)
  else
    if vim.startswith(file, "term://") then
      local container = self.children[#self.children]
      if is_terminals_container(container) then
        for index, child in ipairs(container.children) do
          if child.bufname == file and child.bufnr == bufnr then
            table.remove(container.children, index)
            log.debug("removed terminal buffer %s (%q)", child.bufnr, child.bufname)
            break
          end
        end
        if #container.children == 0 then
          table.remove(self.children, #self.children)
          log.debug("no more terminal buffers present, removed container item")
        end
      end
    else
      remove_fs_node(self, file)
    end
  end
end

---Creates a buffer node tree.
---@async
---@param root_path string
---@return YaTreeBufferNode root, YaTreeBufferNode first_leaf_node
function M.create_buffers_tree(root_path)
  local fs_node = fs.node_for(root_path) --[[@as FsNode]]
  local root = BufferNode:new(fs_node)
  root.repo = git.get_repo_for_path(root_path)
  return root, root:refresh()
end

---@class YaTreeGitStatusNode : YaTreeNode
---@field public parent? YaTreeGitStatusNode
---@field public children? YaTreeGitStatusNode[]
---@field public repo GitRepo
local GitStatusNode = { __node_type = "GitStatus" }
GitStatusNode.__index = GitStatusNode
GitStatusNode.__tostring = Node.__tostring
GitStatusNode.__eq = Node.__eq
setmetatable(GitStatusNode, { __index = Node })

---Creates a new git status node.
---@param fs_node FsNode filesystem data.
---@param parent? YaTreeGitStatusNode the parent node.
---@return YaTreeGitStatusNode node
function GitStatusNode:new(fs_node, parent)
  local this = create_node(self, fs_node, parent)
  if this:is_directory() then
    this.scanned = true
    this.expanded = true
  end
  return this
end

---@private
function GitStatusNode:_scandir() end

---@async
---@param opts? { refresh_git?: boolean }
---  - {opts.refresh_git?} `boolean` whether to refresh the git status, default: `true`.
---@return YaTreeGitStatusNode first_leaf_node
function GitStatusNode:refresh(opts)
  -- only refresh in the root of the tree
  if self.parent then
    return self.parent:refresh(opts)
  end

  local refresh_git = opts and opts.refresh_git or true
  log.debug("refreshing git status node %q", self.path)
  if refresh_git then
    self.repo:refresh_status({ ignored = true })
  end

  local git_status = self.repo:git_status()
  ---@type string[]
  local paths = {}
  for path in pairs(git_status) do
    if self:is_ancestor_of(path) then
      paths[#paths + 1] = path
    end
  end

  self.children = {}
  return create_tree_from_paths(self, paths, function(path, parent)
    local fs_node = fs.node_for(path)
    if fs_node then
      return GitStatusNode:new(fs_node, parent)
    end
  end)
end

---@async
---@param file string
---@return YaTreeGitStatusNode|nil node
function GitStatusNode:add_file(file)
  if self.parent then
    return self.parent:add_file(file)
  else
    return add_fs_node(self, file, function(fs_node, parent)
      return GitStatusNode:new(fs_node, parent)
    end)
  end
end

---@param file string
function GitStatusNode:remove_file(file)
  if self.parent then
    self.parent:remove_file(file)
  else
    remove_fs_node(self, file)
  end
end

---Creates a git status node tree, with the `repo` toplevel as the root node.
---@async
---@param repo GitRepo
---@return YaTreeGitStatusNode root, YaTreeGitStatusNode first_leaft_node
function M.create_git_status_tree(repo)
  local fs_node = fs.node_for(repo.toplevel) --[[@as FsNode]]
  local root = GitStatusNode:new(fs_node)
  root.repo = repo
  return root, root:refresh()
end

return M
