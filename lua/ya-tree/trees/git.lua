local scheduler = require("plenary.async.util").scheduler

local fs = require("ya-tree.fs")
local git = require("ya-tree.git")
local GitNode = require("ya-tree.nodes.git_node")
local Tree = require("ya-tree.trees.tree")
local ui = require("ya-tree.ui")
local utils = require("ya-tree.utils")
local log = require("ya-tree.log")("trees")

local api = vim.api

---@class Yat.Trees.Git : Yat.Tree
---@field TYPE "git"
---@field root Yat.Nodes.Git
---@field current_node Yat.Nodes.Git
---@field supported_actions Yat.Trees.Git.SupportedActions[]
---@field complete_func fun(self: Yat.Trees.Git, bufnr: integer)
local GitTree = { TYPE = "git" }
GitTree.__index = GitTree
GitTree.__eq = Tree.__eq
GitTree.__tostring = Tree.__tostring
setmetatable(GitTree, { __index = Tree })

---@alias Yat.Trees.Git.SupportedActions
---| "cd_to"
---| "toggle_ignored"
---| "toggle_filter"
---
---| "search_for_node_in_tree"
---
---| "goto_node_in_filesystem_tree"
---
---| "focus_prev_git_item"
---| "focus_prev_git_item"
---
---| "focus_prev_diagnostic_item"
---| "focus_next_diagnostic_item"
---
---| Yat.Trees.Tree.SupportedActions

do
  local builtin = require("ya-tree.actions.builtin")

  GitTree.supported_actions = utils.tbl_unique({
    builtin.files.cd_to,
    builtin.files.toggle_ignored,
    builtin.files.toggle_filter,

    builtin.search.search_for_node_in_tree,

    builtin.tree_specific.goto_node_in_filesystem_tree,

    builtin.git.focus_prev_git_item,
    builtin.git.focus_next_git_item,

    builtin.diagnostics.focus_prev_diagnostic_item,
    builtin.diagnostics.focus_next_diagnostic_item,

    unpack(Tree.supported_actions),
  })
end

GitTree.complete_func = Tree.complete_func_loaded_nodes

---@async
---@param repo_or_path? Yat.Git.Repo|string
---@return Yat.Nodes.Git|nil
local function create_root_node(repo_or_path)
  local repo
  if type(repo_or_path) == "string" then
    repo = git.create_repo(repo_or_path)
  else
    repo = repo_or_path
  end
  if type(repo) == "table" then
    local fs_node = fs.node_for(repo.toplevel) --[[@as Yat.Fs.Node]]
    local root = GitNode:new(fs_node)
    root.repo = repo
    return root
  else
    log.error("%q is either not a path to a git repo or a git repo object", tostring(repo_or_path))
    local path = type(repo_or_path) == "string" and repo_or_path or (repo_or_path and repo_or_path.toplevel or "unknown")
    utils.warn(string.format("%q is not a path to a Git repo", path))
    return nil
  end
end

---@async
---@param tabpage integer
---@param repo_or_path? Yat.Git.Repo|string
---@return Yat.Trees.Git|nil tree
function GitTree:new(tabpage, repo_or_path)
  repo_or_path = repo_or_path or vim.loop.cwd()
  local root = create_root_node(repo_or_path)
  if not root then
    return nil
  end
  local this = Tree.new(self, tabpage, root.path)
  this:enable_events(true)
  local persistent = require("ya-tree.config").config.trees.git.persistent
  this.persistent = persistent or false
  this.root = root
  this.current_node = this.root:refresh()

  log.debug("created new tree %s", tostring(this))
  return this
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
    local git_status_changed = self.root.repo:refresh_status_for_path(file)
    if not node and git_status_changed then
      self.root:add_node(file)
    elseif node and git_status_changed then
      if not node:git_status() then
        self.root:remove_node(file)
      end
    end

    scheduler()
    if self:is_shown_in_ui(api.nvim_get_current_tabpage()) then
      ui.update(self)
    end
  end
end

---@async
---@param repo_or_path Yat.Git.Repo|string
---@return boolean
---@nodiscard
function GitTree:change_root_node(repo_or_path)
  local old_root = self.root
  local root = create_root_node(repo_or_path)
  if root then
    self.root = root
    self.current_node = self.root:refresh()
    log.debug("updated tree root to %s, old root was %s", tostring(self.root), tostring(old_root))
  end
  return root ~= nil
end

return GitTree
