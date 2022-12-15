local fs = require("ya-tree.fs")
local git = require("ya-tree.git")
local GitNode = require("ya-tree.nodes.git_node")
local meta = require("ya-tree.meta")
local TextNode = require("ya-tree.nodes.text_node")
local Tree = require("ya-tree.trees.tree")
local utils = require("ya-tree.utils")
local log = require("ya-tree.log").get("trees")

---@class Yat.Trees.Git : Yat.Tree
---@field new async fun(self: Yat.Trees.Git, tabpage: integer, repo_or_path?: Yat.Git.Repo|string): Yat.Trees.Git
---@overload async fun(tabpage: integer, repo_or_path?: Yat.Git.Repo|string): Yat.Trees.Git
---@field class fun(self: Yat.Trees.Git): Yat.Trees.Git
---@field super Yat.Tree
---@field static Yat.Trees.Git
---
---@field TYPE "git"
---@field root Yat.Nodes.Git|Yat.Nodes.Text
---@field current_node Yat.Nodes.Git|Yat.Nodes.Text
---@field supported_actions Yat.Trees.Git.SupportedActions[]
---@field supported_events { autocmd: Yat.Trees.AutocmdEventsLookupTable, git: Yat.Trees.GitEventsLookupTable, yatree: Yat.Trees.YaTreeEventsLookupTable }
---@field complete_func fun(self: Yat.Trees.Git, bufnr: integer)
local GitTree = meta.create_class("Yat.Trees.Git", Tree)
GitTree.TYPE = "git"

---@alias Yat.Trees.Git.SupportedActions
---| "rename"
---
---| "cd_to"
---| "toggle_ignored"
---| "toggle_filter"
---
---| "search_for_node_in_tree"
---
---| "goto_node_in_filesystem_tree"
---
---| "focus_prev_git_item"
---| "focus_next_git_item"
---| "git_stage"
---| "git_unstage"
---| "git_revert"
---
---| "focus_prev_diagnostic_item"
---| "focus_next_diagnostic_item"
---
---| Yat.Trees.Tree.SupportedActions

do
  local builtin = require("ya-tree.actions.builtin")
  GitTree.supported_actions = utils.tbl_unique({
    builtin.files.rename,

    builtin.files.cd_to,
    builtin.files.toggle_ignored,
    builtin.files.toggle_filter,

    builtin.search.search_for_node_in_tree,

    builtin.tree_specific.goto_node_in_filesystem_tree,

    builtin.git.focus_prev_git_item,
    builtin.git.focus_next_git_item,
    builtin.git.git_stage,
    builtin.git.git_unstage,
    builtin.git.git_revert,

    builtin.diagnostics.focus_prev_diagnostic_item,
    builtin.diagnostics.focus_next_diagnostic_item,

    unpack(vim.deepcopy(Tree.static.supported_actions)),
  })
end

---@param config Yat.Config
---@return boolean enabled
function GitTree.setup(config)
  if not config.git.enable then
    return false
  end

  GitTree.complete_func = Tree.static.complete_func_loaded_nodes
  GitTree.renderers = Tree.static.create_renderers(GitTree.static.TYPE, config)

  local ae = require("ya-tree.events.event").autocmd
  local ge = require("ya-tree.events.event").git
  local ye = require("ya-tree.events.event").ya_tree
  local supported_events = {
    autocmd = {
      [ae.BUFFER_SAVED] = GitTree.static.on_buffer_saved,
      [ae.BUFFER_MODIFIED] = Tree.static.on_buffer_modified,
    },
    git = {},
    yatree = {},
  }
  if config.git.enable then
    supported_events.git[ge.DOT_GIT_DIR_CHANGED] = GitTree.static.on_git_event
  end
  if config.diagnostics.enable then
    supported_events.yatree[ye.DIAGNOSTICS_CHANGED] = Tree.static.on_diagnostics_event
  end
  GitTree.supported_events = supported_events

  GitTree.keymap = Tree.static.create_mappings(config, GitTree.static.TYPE, GitTree.static.supported_actions)

  return true
end

---@async
---@param repo_or_path Yat.Git.Repo|string
---@reutrn Yat.Git.Repo|nil repo
local function get_repo(repo_or_path)
  if type(repo_or_path) == "string" then
    return git.create_repo(repo_or_path)
  elseif type(repo_or_path) == "table" and type(repo_or_path.toplevel) == "string" then
    return repo_or_path
  end
end

---@async
---@param repo Yat.Git.Repo
---@return Yat.Nodes.Git
local function create_root_node(repo)
  local fs_node = fs.node_for(repo.toplevel) --[[@as Yat.Fs.Node]]
  local root = GitNode:new(fs_node)
  root.repo = repo
  return root
end

---@async
---@private
---@param tabpage integer
---@param repo_or_path Yat.Git.Repo|string
function GitTree:init(tabpage, repo_or_path)
  local repo = get_repo(repo_or_path)
  local root
  if repo then
    root = create_root_node(repo)
  else
    local path = type(repo_or_path) == "string" and repo_or_path or "unknown"
    root = TextNode:new(path .. " is not a Git repository", path, false)
  end
  local current_node = root:refresh() or root
  self.super:init(self.TYPE, tabpage, root, current_node)

  log.info("created new tree %s", tostring(self))
end

---@async
---@param repo Yat.Git.Repo
---@return boolean
function GitTree:on_git_event(repo)
  if vim.v.exiting == vim.NIL and self.root.repo == repo then
    log.debug("git repo %s changed", tostring(self.root.repo))

    self.root:refresh({ refresh_git = false })
    return true
  end
  return false
end

---@async
---@param _ integer
---@param file string
---@return boolean
function GitTree:on_buffer_saved(_, file)
  if self.root:is_ancestor_of(file) then
    log.debug("changed file %q is in tree %s", file, tostring(self))
    local node = self.root:get_child_if_loaded(file)
    if node then
      node.modified = false
    end
    local git_status = self.root.repo:status():of(file, "file")
    if not node and git_status then
      self.root:add_node(file)
    elseif node and not git_status then
      self.root:remove_node(file)
    end

    return true
  end
  return false
end

---@async
---@param path string
function GitTree:change_root_node(path)
  local repo = get_repo(path)
  if not repo or repo == self.root.repo then
    return
  end
  local old_root = self.root
  self.root = create_root_node(repo)
  self.current_node = self.root:refresh() --[[@as Yat.Nodes.Git]]
  log.debug("updated tree root to %s, old root was %s", tostring(self.root), tostring(old_root))
end

return GitTree
