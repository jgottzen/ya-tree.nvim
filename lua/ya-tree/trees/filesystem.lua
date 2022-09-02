local scheduler = require("plenary.async.util").scheduler
local Path = require("plenary.path")

local events = require("ya-tree.events")
local fs = require("ya-tree.filesystem")
local git = require("ya-tree.git")
local Node = require("ya-tree.nodes.node")
local Tree = require("ya-tree.trees.tree")
local ui = require("ya-tree.ui")
local log = require("ya-tree.log")

local uv = vim.loop

---@class YaFsTree : YaTree
---@field TYPE "files"
---@field private _singleton false
---@field cwd string
---@field private _repos GitRepo[]
local FilesystemTree = { TYPE = "files", _singleton = false }
FilesystemTree.__index = FilesystemTree
FilesystemTree.__eq = Tree.__eq

---@param self YaFsTree
---@return string
FilesystemTree.__tostring = function(self)
  return string.format("(%s, tabpage=%s, cwd=%s, root=%s)", self.TYPE, vim.inspect(self._tabpage), self.cwd, tostring(self.root))
end

setmetatable(FilesystemTree, { __index = Tree })

---Creates a new filesystem node tree root.
---@async
---@param path string the path
---@param old_root? YaTreeNode the previous root
---@return YaTreeNode root
local function create_root_node(path, old_root)
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

---@param tabpage integer
---@param toplevel string
---@return string id
local function create_git_event_id(tabpage, toplevel)
  return string.format("YA_TREE_FILES_TREE%s_%s_GIT", tabpage, toplevel)
end

---@async
---@param tabpage integer
---@param root? string|YaTreeNode
---@return YaFsTree tree
function FilesystemTree:new(tabpage, root)
  local this = Tree.new(self, tabpage)
  this.cwd = uv.cwd() --[[@as string]]
  this._repos = {}

  local root_node
  if type(root) == "string" then
    root_node = create_root_node(root)
  elseif type(root) == "table" then
    root_node = root --[[@as YaTreeNode]]
  else
    root_node = create_root_node(this.cwd)
  end

  this:check_node_for_repo(root_node)
  this.root = root_node
  this.current_node = this.root

  log.debug("created new tree %s", tostring(this))
  return this
end

function FilesystemTree:delete()
  self:_clear_repos()
end

---@private
function FilesystemTree:_clear_repos()
  local event = require("ya-tree.events.event")
  for _, repo in ipairs(self._repos) do
    events.remove_event_handler(event.GIT, create_git_event_id(self._tabpage, repo.toplevel))
  end
  self._repos = {}
end

---@async
---@param node YaTreeNode
---@return boolean
function FilesystemTree:check_node_for_repo(node)
  if require("ya-tree.config").config.git.enable then
    local repo = git.create_repo(node.path)
    if repo then
      self._repos[#self._repos + 1] = repo

      node:set_git_repo(repo)
      repo:refresh_status({ ignored = true })
      events.on_git_event(create_git_event_id(self._tabpage, repo.toplevel), function(event_repo, fs_changes)
        self:on_git_event(event_repo, fs_changes)
      end)
      return true
    end
  end
  return false
end

---@async
---@param repo GitRepo
---@param fs_changes boolean
function FilesystemTree:on_git_event(repo, fs_changes)
  if vim.v.exiting ~= vim.NIL or not vim.tbl_contains(self._repos, repo) then
    return
  end
  log.debug("git repo %s changed", tostring(repo))

  if fs_changes then
    log.debug("git listener called with fs_changes=true, refreshing tree")
    local node = self.root:get_child_if_loaded(repo.toplevel)
    if node then
      log.debug("repo %s is loaded in node %q", tostring(repo), node.path)
      node:refresh({ recurse = true })
    elseif self.root.path:find(repo.toplevel, 1, true) ~= nil then
      log.debug("tree root %q is a subdirectory of repo %s", self.root.path, tostring(repo))
      self.root:refresh({ recurse = true })
    end
  end
  scheduler()
  if ui.is_open(self.TYPE) then
    -- get the current node to keep the cursor on it
    ui.update(self, ui.get_current_node())
  end
end

---@async
---@param self YaFsTree
---@param new_root string
---@return boolean `false` if the current tree cannot walk up or down to reach the specified directory.
local function update_tree_root_node(self, new_root)
  if self.root.path ~= new_root then
    local root
    if self.root:is_ancestor_of(new_root) then
      log.debug("current tree %s is ancestor of new root %q, expanding to it", tostring(self), new_root)
      -- the new root is located 'below' the current root,
      -- if it's already loaded in the tree, use that node as the root, else expand to it
      root = self.root:get_child_if_loaded(new_root)
      if root then
        root:expand({ force_scan = true })
      else
        root = self.root:expand({ force_scan = true, to = new_root })
      end
    elseif self.root.path:find(Path:new(new_root):absolute(), 1, true) then
      log.debug("current tree %s is a child of new root %q, creating parents up to it", tostring(self), new_root)
      -- the new root is located 'above' the current root,
      -- walk upwards from the current root's parent and see if it's already loaded, if so, us it
      root = self.root
      while root.parent do
        root = root.parent --[[@as YaTreeNode]]
        root:refresh()
        if root.path == new_root then
          break
        end
      end

      while root.path ~= new_root do
        root = create_root_node(Path:new(root.path):parent().filename, root)
      end
    else
      log.debug("current tree %s is not a child or ancestor of %q", tostring(self), new_root)
    end

    if not root then
      log.debug("cannot walk the tree to find a node for %q, returning nil", new_root)
      return false
    else
      self.root = root
    end
  else
    log.debug("the new root %q is the same as the current root %s, skipping", new_root, tostring(self.root))
  end
  return true
end

---@async
---@param new_root string|YaTreeNode
function FilesystemTree:change_root_node(new_root)
  local old_root = self.root
  if type(new_root) == "string" then
    if not fs.is_directory(new_root) then
      new_root = Path:new(new_root):parent():absolute() --[[@as string]]
    end
    if not update_tree_root_node(self, new_root) then
      self:_clear_repos()
      self.root = create_root_node(new_root, self.root)
    end
  else
    ---@cast new_root YaTreeNode
    self.root = new_root
    self.root:expand({ force_scan = true })

    local tree_root = new_root
    while tree_root.parent do
      tree_root = tree_root.parent --[[@as YaTreeNode]]
    end
    ---@type table<string, boolean>
    local found_toplevels = {}
    tree_root:walk(function(node)
      if node.repo and not found_toplevels[node.repo.toplevel] then
        found_toplevels[node.repo.toplevel] = true
      end
    end)
    local event = require("ya-tree.events.event")
    for _, repo in ipairs(self._repos) do
      if not found_toplevels[repo.toplevel] then
        events.remove_event_handler(event.GIT, create_git_event_id(self._tabpage, repo.toplevel))
      end
    end
  end

  if not self.root.repo then
    self:check_node_for_repo(self.root)
  end
  log.debug("updated tree to %s, old root was %s", tostring(self), tostring(old_root))
end

return FilesystemTree
