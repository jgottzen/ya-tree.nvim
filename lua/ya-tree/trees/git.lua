local scheduler = require("plenary.async.util").scheduler

local fs = require("ya-tree.filesystem")
local git = require("ya-tree.git")
local GitNode = require("ya-tree.nodes.git_node")
local Tree = require("ya-tree.trees.tree")
local ui = require("ya-tree.ui")
local log = require("ya-tree.log")
local utils = require("ya-tree.utils")

local api = vim.api

---@class Yat.Trees.Git : Yat.Tree
---@field TYPE "git"
---@field root Yat.Nodes.Git
---@field current_node? Yat.Nodes.Git
local GitTree = { TYPE = "git" }
GitTree.__index = GitTree
GitTree.__eq = Tree.__eq
GitTree.__tostring = Tree.__tostring
setmetatable(GitTree, { __index = Tree })

---@async
---@param tabpage integer
---@param repo_or_toplevel Yat.Git.Repo|string
---@return Yat.Trees.Git tree
function GitTree:new(tabpage, repo_or_toplevel)
  local this = Tree.new(self, tabpage)
  local repo
  if type(repo_or_toplevel) == "string" then
    repo = git.create_repo(repo_or_toplevel)
  else
    repo = repo_or_toplevel --[[@as Yat.Git.Repo]]
  end
  if not repo then
    log.error("%q is either not a path to a git repo or a git repo object", tostring(repo_or_toplevel))
    utils.warn(string.format("%q is either not a path to a git repo or a git repo object", tostring(repo_or_toplevel)))
  else
    this:_init(repo)
  end

  log.debug("created new tree %s", tostring(this))
  return this
end

---@async
---@private
---@param repo Yat.Git.Repo
function GitTree:_init(repo)
  local fs_node = fs.node_for(repo.toplevel) --[[@as Yat.Fs.Node]]
  self.root = GitNode:new(fs_node)
  self.root.repo = repo
  self.current_node = self.root:refresh()
end

---@async
---@param repo Yat.Git.Repo
function GitTree:on_git_event(repo)
  if vim.v.exiting ~= vim.NIL or self.root.repo ~= repo then
    return
  end
  log.debug("git repo %s changed", tostring(self.root.repo))

  self.root:refresh({ refresh_git = false })
  scheduler()
  if self:is_shown_in_ui(api.nvim_get_current_tabpage()) then
    -- get the current node to keep the cursor on it, if the tree changed
    ui.update(self, ui.get_current_node())
  end
end

---@async
---@param _ integer
---@param file string
function GitTree:on_buffer_saved(_, file)
  if self.root:is_ancestor_of(file) then
    log.debug("changed file %q is in tree %s", file, tostring(self))
    local node = self.root:get_child_if_loaded(file)
    if node then
      node.modified = false
    end
    local git_status_changed = self.root.repo:refresh_status_for_file(file)
    if not node and git_status_changed then
      self.root:add_file(file)
    elseif node and git_status_changed then
      if not node:git_status() then
        self.root:remove_file(file)
      end
    end

    scheduler()
    if self:is_shown_in_ui(api.nvim_get_current_tabpage()) then
      ui.update(self)
    end
  end
end

---@async
---@param repo Yat.Git.Repo
function GitTree:change_root_node(repo)
  local old_root = self.root
  self:_init(repo)
  log.debug("updated tree to %s, old root was %s", tostring(self), tostring(old_root))
end

return GitTree
