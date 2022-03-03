local Path = require("plenary.path")

local fs = require("ya-tree.filesystem")
local git = require("ya-tree.git")
local utils = require("ya-tree.utils")
local log = require("ya-tree.log")

local fn = vim.fn

local Tree = {
  Node = {},
}

local Node = Tree.Node
Node.__index = Node
Node.__eq = function(n1, n2)
  return n1 and n2 and n1.path ~= nil and n1.path == n2.path
end
Node.__tostring = function(self)
  return self.path
end

do
  local node_cache = {}

  function Tree.node_for_path(path)
    return node_cache[path]
  end

  function Node:new(nodedata, parent, use_cache)
    local node
    if use_cache then
      -- if the node already exist, copy some data over
      node = node_cache[nodedata.path]
      if node then
        nodedata.expanded = node.expanded
        nodedata.scanned = node.scanned
        nodedata.children = node.children
        nodedata.clipboard_status = node.clipboard_status
        nodedata.repo = node.repo
      end
    end

    log.trace("creating node for %q", nodedata.path)

    node = setmetatable(nodedata, Node)
    node.parent = parent

    -- inherit any git repo
    if parent and parent.repo then
      node.repo = parent.repo
    end

    if use_cache then
      node_cache[node.path] = node
    end

    return node
  end

  function Node:_scandir()
    log.debug("scanning directory %q", self.path)
    -- keep track of the current children
    local paths = {}
    for _, child in ipairs(self.children) do
      paths[child.path] = true
    end
    self.children = vim.tbl_map(function(node)
      paths[node.path] = nil -- the node is still present
      return Node:new(node, self, true)
    end, fs.scan_dir(self.path))

    -- for any path still present, it does no longer exist in the directory of this node
    -- remove it from the cache
    for path, _ in pairs(paths) do
      node_cache[path] = nil
    end

    self.empty = #self.children == 0
    self.scanned = true
  end

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
        local node = node_cache[toplevel]
        if node then
          -- the git toplevel directory is loaded in the tree, set the repo property on that node
          set_git_repo_on_node_and_children(repo, node)
        else
          -- the git toplevel directory is not loaded in the tree
          if #toplevel < #self.path then
            -- this node is below the git toplevel directory,
            -- walk the tree upwards until we hit the topmost node
            node = self
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
      end
    else
      log.debug("path %s is not in a git repository", self.path)
    end
  end

  function Tree.root(cwd, old_root)
    local root = node_cache[cwd]
    if not root then
      root = Node:new({
        name = fn.fnamemodify(cwd, ":t"),
        type = "directory",
        path = cwd,
        children = {},
      }, nil, true)
    end

    root.repo = git.Repo:new(root.path)
    if root.repo then
      log.debug("node %q is in a git repo with toplevel %q", root.path, root.repo.toplevel)
      root.repo:refresh_status({ ignored = true })
    end
    root:expand()

    -- if the old root is a child of the new root, add its children
    if old_root then
      for _, node in ipairs(root.children) do
        if node.path == old_root.path then
          node.children = old_root.children
          break
        end
      end
    end

    return root
  end
end

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

function Node:is_directory()
  return self.type == "directory"
end

function Node:is_file()
  return self.type == "file"
end

function Node:is_link()
  return self.link == true
end

function Node:is_parent_of(path)
  return self:is_directory() and path:find(self.path .. utils.os_sep, 1, true)
end

function Node:is_empty()
  return self.empty
end

function Node:is_dotfile()
  return self.name:sub(1, 1) == "."
end

function Node:is_git_ignored()
  return self.repo and self.repo:is_ignored(self.path, self.type)
end

function Node:get_git_status()
  return self.repo and self.repo:status_of(self.path)
end

function Node:is_git_repository_root()
  return self.repo and self.repo.toplevel == self.path
end

function Node:set_clipboard_status(status)
  self.clipboard_status = status
end

do
  local diagnostics = {}

  function Tree.set_diagnostics(new_diagnostics)
    diagnostics = new_diagnostics
  end

  function Node:get_diagnostics_severity()
    return diagnostics[self.path]
  end
end

-- function Node:get_diagnostics_severity()
--   return self.tree.diagnostics[self.path]
-- end

function Node:iterate_children(opts)
  if not self.children or #self.children == 0 then
    return function() end, nil, nil
  end

  opts = opts or {}
  opts.reverse = opts.reverse or false
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

function Node:collapse()
  if self:is_directory() then
    self.expanded = false
  end

  return self
end

function Node:expand(to)
  if self:is_directory() then
    if not self.scanned then
      self:_scandir()
    end
    self.expanded = true
  end

  if to then
    log.debug("node %q is expanding to path=%q", self.path, to)
    if self.path == to then
      log.debug("self %q is equal to path=%q", self.path, to)
      return self
    elseif self:is_directory() then
      for _, node in ipairs(self.children) do
        if node:is_parent_of(to) then
          log.debug("child node %q is parent of %q, expanding...", node.path, to)
          return node:expand(to)
        elseif node.path == to then
          log.debug("found node %q equal to path=%q", node.path, to)
          return node
        end
      end
    end
  end

  return self
end

local function refresh_node(node, recurse)
  if node:is_directory() and node.scanned then
    node:_scandir()

    if recurse then
      for _, child in ipairs(node.children) do
        refresh_node(child, true)
      end
    end
  end
end

function Node:refresh()
  for _, repo in pairs(git.repos) do
    if repo then
      repo:refresh_status({ ignored = true })
    end
  end

  refresh_node(self, true)
end

function Node:create_search_tree(search_results)
  local search_root = Node:new({
    name = self.name,
    type = self.type,
    path = self.path,
    children = {},
    expanded = true,
  }, nil, false)
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
          parent = Node:new(fs.node_for(parent_path), grand_parent, false)
          parent.expanded = true
          grand_parent.children[#grand_parent.children + 1] = parent
          table.sort(grand_parent.children, fs.file_item_sorter)
          node_map[parent_path] = parent
        end
      end
    end

    local parent = node_map[parents[1]]
    local node = Node:new(fs.node_for(path), parent, false)
    node.expanded = true
    parent.children[#parent.children + 1] = node
    table.sort(parent.children, fs.file_item_sorter)
    node_map[node.path] = node
  end

  local first_node = search_root
  while first_node and first_node:is_directory() do
    first_node = first_node.children and first_node.children[1]
  end

  return search_root, first_node
end

return Tree
