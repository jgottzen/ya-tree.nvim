local fs = require("ya-tree.filesystem")
local git = require("ya-tree.git")
local SearchNode = require("ya-tree.nodes.search_node")
local Tree = require("ya-tree.trees.tree")
local log = require("ya-tree.log")("trees")

---@class Yat.Trees.Search : Yat.Tree
---@field TYPE "search"
---@field root Yat.Nodes.Search
---@field current_node Yat.Nodes.Search
---@field supported_actions Yat.Trees.Search.SupportedActions[]
---@field complete_func fun(self: Yat.Trees.Search, bufnr: integer)
local SearchTree = { TYPE = "search" }
SearchTree.__index = SearchTree
SearchTree.__eq = Tree.__eq
SearchTree.__tostring = Tree.__tostring
setmetatable(SearchTree, { __index = Tree })

---@alias Yat.Trees.Search.SupportedActions
---| "cd_to"
---| "toggle_ignored"
---| "toggle_filter"
---
---| "search_for_node_in_tree"
---| "search_interactively"
---| "search_once"
---
---| "goto_node_in_files_tree"
---| "show_files_tree"
---
---| "rescan_dir_for_git"
---| "focus_prev_git_item"
---| "focus_prev_git_item"
---
---| "focus_prev_diagnostic_item"
---| "focus_next_diagnostic_item"
---
---| Yat.Trees.Tree.SupportedActions

do
  local builtin = require("ya-tree.actions.builtin")

  ---@diagnostic disable-next-line:missing-parameter
  SearchTree.supported_actions = vim.fn.uniq({
    builtin.files.cd_to,
    builtin.files.toggle_ignored,
    builtin.files.toggle_filter,

    builtin.search.search_for_node_in_tree,
    builtin.search.search_interactively,
    builtin.search.search_once,

    builtin.tree_specific.goto_node_in_files_tree,
    builtin.tree_specific.show_files_tree,

    builtin.git.rescan_dir_for_git,
    builtin.git.focus_prev_git_item,
    builtin.git.focus_next_git_item,

    builtin.diagnostics.focus_prev_diagnostic_item,
    builtin.diagnostics.focus_next_diagnostic_item,

    unpack(Tree.supported_actions),
  })
end

SearchTree.complete_func = Tree.complete_func_loaded_nodes

---@async
---@param tabpage integer
---@param path string
---@return Yat.Trees.Search tree
function SearchTree:new(tabpage, path)
  local this = Tree.new(self, tabpage)
  this:_init(path)

  log.debug("created new tree %s", tostring(this))
  return this
end

---@async
---@private
---@param self Yat.Trees.Search
---@param path string
function SearchTree:_init(path)
  local fs_node = fs.node_for(path) --[[@as Yat.Fs.Node]]
  self.root = SearchNode:new(fs_node)
  self.current_node = self.root
  self.root.repo = git.get_repo_for_path(self.root.path)
end

---@async
---@param path string
function SearchTree:change_root_node(path)
  local old_root = self.root
  self:_init(path)
  log.debug("updated tree to %s, old root was %s", tostring(self), tostring(old_root))
end

---@async
---@param term string
---@return integer|string matches_or_error
function SearchTree:search(term)
  local result_node, matches_or_error = self.root:search(term)
  if result_node then
    self.current_node = result_node
  end
  return matches_or_error
end

return SearchTree
