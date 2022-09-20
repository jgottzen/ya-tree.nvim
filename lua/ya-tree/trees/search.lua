local fs = require("ya-tree.filesystem")
local git = require("ya-tree.git")
local SearchNode = require("ya-tree.nodes.search_node")
local Tree = require("ya-tree.trees.tree")
local log = require("ya-tree.log")

---@class Yat.Trees.Search : Yat.Tree
---@field TYPE "search"
---@field private _singleton false
---@field root Yat.Nodes.Search
---@field current_node? Yat.Nodes.Search
local SearchTree = { TYPE = "search", _singleton = false }
SearchTree.__index = SearchTree
SearchTree.__eq = Tree.__eq
SearchTree.__tostring = Tree.__tostring
setmetatable(SearchTree, { __index = Tree })

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
