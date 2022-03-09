local Path = require("plenary.path")

local fs = require("ya-tree.filesystem")
local git = require("ya-tree.git")
local utils = require("ya-tree.utils")
local log = require("ya-tree.log")

local fn = vim.fn

local M = {}

---@class Node
---@field public parent? Node
---@field public name string
---@field public path string
---@field public type "'directory'" | "'file'"
---@field public children? Node[]
---@field public empty? boolean
---@field public extension? string
---@field public executable? boolean
---@field public link boolean
---@field public link_to? string
---@field public link_name? string
---@field public link_extension? string
---@field public repo? Repo
---@field public clipboard_status clipboard_action | nil
---@field private scanned? boolean
---@field private expanded? boolean
local Node = {}

--- Creates a new node.
---@param nodedata table filesystem data.
---@param parent? Node the parent node.
---@return Node
local function create_node(nodedata, parent)
  log.trace("creating node for %q", nodedata.path)

  ---@type Node
  local self = setmetatable(nodedata, {
    __index = Node,
    __eq = function(n1, n2)
      return n1 and n2 and n1.path ~= nil and n1.path == n2.path
    end,
    __tostring = function(self)
      return self.path
    end,
  })
  self.parent = parent
  if self:is_directory() then
    self.children = {}
  end

  -- inherit any git repo
  if parent and parent.repo then
    self.repo = parent.repo
  end

  return self
end

--- Creates a new node tree root.
---@param cwd string the path
---@param old_root? Node the previous root
---@return Node
function M.root(cwd, old_root)
  local root = create_node({
    name = fn.fnamemodify(cwd, ":t"),
    type = "directory",
    path = cwd,
    children = {},
  }, nil)

  root.repo = git.Repo:new(root.path)
  if root.repo then
    log.debug("node %q is in a git repo with toplevel %q", root.path, root.repo.toplevel)
    root.repo:refresh_status({ ignored = true })
  end

  -- if the tree root was moved on level up, i.e the new root is the parent of the old root,
  -- add it to the tree
  if old_root then
    if Path:new(old_root.path):parent().filename == root.path then
      root.children[#root.children + 1] = old_root
      old_root.parent = root
    end
  end

  -- force rescan of the directory
  root:expand({ force_scan = true })

  return root
end

---@private
function Node:_merge_new_data(nodedata)
  for k, v in pairs(nodedata) do
    if type(self[k]) ~= "function" then
      self[k] = v
    else
      log.error("nodedata.%s is a function, this should not happen!", k)
    end
  end
end

---@private
function Node:_scandir()
  log.debug("scanning directory %q", self.path)
  -- keep track of the current children
  local children = {}
  for _, child in ipairs(self.children) do
    children[child.path] = child
  end

  self.children = vim.tbl_map(function(nodedata)
    local child = children[nodedata.path]
    if child then
      log.trace("_scandir: merging %q", nodedata.path)
      child:_merge_new_data(nodedata)
      children[nodedata.path] = nil -- the node is still present
      return child
    else
      log.trace("_scandir: creating new %q", nodedata.path)
      return create_node(nodedata, self)
    end
  end, fs.scan_dir(self.path))

  self.empty = #self.children == 0
  self.scanned = true
end

---@param repo Repo
---@param node Node
local function set_git_repo_on_node_and_children(repo, node)
  log.debug("setting repo on node %s", node.path)
  node.repo = repo
  if node.children then
    for _, child in ipairs(node.children) do
      set_git_repo_on_node_and_children(repo, child)
    end
  end
end

function Node:check_for_git_repo()
  local repo = git.Repo:new(self.path)
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
        while node.parent and toplevel < #node.parent.path do
          node = node.parent
        end
        set_git_repo_on_node_and_children(repo, node)
      else
        log.error("git repo with toplevel %s is somehow below this node %s, this should not be possible", toplevel, self.path)
        log.error("self=%s", self)
        log.error("repo=%s", repo)
      end
    end
  else
    log.debug("path %s is not in a git repository", self.path)
  end
end

---@private
function Node:_debug_table()
  local t = { path = self.path }
  if self:is_directory() then
    t.children = {}
    for _, child in ipairs(self.children) do
      t.children[#t.children + 1] = child:_debug_table()
    end
  end
  return t
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
  return self:is_directory() and #self.path <= #path and path:find(self.path .. utils.os_sep, 1, true)
end

---@return boolean
function Node:is_empty()
  return self.empty
end

---@return boolean
function Node:is_dotfile()
  return self.name:sub(1, 1) == "."
end

---@return boolean
function Node:is_git_ignored()
  return self.repo and self.repo:is_ignored(self.path, self.type)
end

---@return string
function Node:get_git_status()
  return self.repo and self.repo:status_of(self.path)
end

---@return boolean
function Node:is_git_repository_root()
  return self.repo and self.repo.toplevel == self.path
end

---@param status clipboard_action
function Node:set_clipboard_status(status)
  self.clipboard_status = status
end

do
  local diagnostics = {}

  ---@param new_diagnostics table<string, number>
  function M.set_diagnostics(new_diagnostics)
    diagnostics = new_diagnostics
  end

  ---@return number | nil
  function Node:get_diagnostics_severity()
    return diagnostics[self.path]
  end
end

---@param opts { reverse?: boolean, from?: Node }
---@return fun():Node | nil
function Node:iterate_children(opts)
  if not self.children or #self.children == 0 then
    return function() end, nil, nil
  end

  opts = opts or {}
  local start = 0
  if opts.reverse then
    start = #self.children + 1
  end
  if opts.from then
    for k, v in ipairs(self.children) do
      if v == opts.from then
        start = k
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

--- Collapses the node, it it is a directory.
---@param opts {children_only?: boolean, recursive?: boolean}
---  - {opts.children_only} `boolean`
---  - {opts.recursive} `boolean`
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

--- Expands the node, if it is a directory. If the node hasn't been scanned before, will scan the directory.
---@param opts {force_scan?: boolean, to?: string}
---  - {opts.force_scan} `boolean`.
---  - {opts.to} `string` expand all the way to the specified path and returns it.
---@return Node | nil #if {opts.to} is specified, and found.
function Node:expand(opts)
  opts = opts or {}
  if self:is_directory() then
    if not self.scanned or opts.force_scan then
      self:_scandir()
    end
    self.expanded = true
  end

  if opts.to then
    local to = opts.to
    log.debug("node %q is expanding to path=%q", self.path, to)
    if self.path == to then
      log.debug("self %q is equal to path=%q", self.path, to)
      return self
    elseif self:is_directory() then
      for _, node in ipairs(self.children) do
        if node:is_ancestor_of(to) then
          log.debug("child node %q is parent of %q, expanding...", node.path, to)
          return node:expand(opts)
        elseif node.path == to then
          log.debug("found node %q equal to path=%q", node.path, to)
          return node
        end
      end
    end
  end
end

--- Returns the child node specified by `path` if it has been loaded.
---@param path string
---@return Node | nil
function Node:get_child_if_loaded(path)
  if self.path == path then
    return self
  end
  if not self:is_directory() then
    return
  end

  for _, node in ipairs(self.children) do
    if node.path == path then
      return node
    elseif node:is_ancestor_of(path) then
      return node:get_child_if_loaded(path)
    end
  end
end

---@private
---@param node Node
---@param recurse boolean
---@param refreshed_git_repos table<string, boolean> | nil
local function refresh_node(node, recurse, refreshed_git_repos)
  refreshed_git_repos = refreshed_git_repos or {}

  if node:is_directory() and node.scanned then
    if node.repo and not refreshed_git_repos[node.repo.toplevel] then
      node.repo:refresh_status({ ignored = true })
      refreshed_git_repos[node.repo.toplevel] = true
    end
    node:_scandir()

    if recurse then
      for _, child in ipairs(node.children) do
        refresh_node(child, true, refreshed_git_repos)
      end
    end
  end
end

function Node:refresh()
  log.debug("refreshing %q", self.path)
  refresh_node(self, true)
end

--- Creates a separate node search tree from the `search_result`.
---@param search_results string[]
---@return Node search_root, Node first_node
function Node:create_search_tree(search_results)
  local search_root = create_node({
    name = self.name,
    type = self.type,
    path = self.path,
    children = {},
    expanded = true,
  }, nil)
  local node_map = {}
  node_map[self.path] = search_root

  local min_path_size = #self.path
  for _, path in ipairs(search_results) do
    local parents = Path:new(path):parents()
    for i = #parents, 1, -1 do
      local parent_path = parents[i]
      -- skip paths above the node we are searching from
      if #parent_path > min_path_size then
        local parent = node_map[parent_path]
        if not parent then
          local grand_parent = node_map[parents[i + 1]]
          local nodedata = fs.node_for(parent_path)
          if nodedata then
            parent = create_node(nodedata, grand_parent)
            parent.expanded = true
            grand_parent.children[#grand_parent.children + 1] = parent
            table.sort(grand_parent.children, fs.file_item_sorter)
            node_map[parent_path] = parent
          end
        end
      end
    end

    local parent = node_map[parents[1]]
    local nodedata = fs.node_for(path)
    if nodedata then
      local node = create_node(nodedata, parent)
      node.expanded = true
      parent.children[#parent.children + 1] = node
      table.sort(parent.children, fs.file_item_sorter)
      node_map[node.path] = node
    end
  end

  local first_node = search_root
  while first_node and first_node:is_directory() do
    first_node = first_node.children and first_node.children[1]
  end

  return search_root, first_node
end

return M