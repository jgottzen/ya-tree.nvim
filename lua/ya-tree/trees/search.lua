local events = require("ya-tree.events")
local fs = require("ya-tree.filesystem")
local git = require("ya-tree.git")
local SearchNode = require("ya-tree.nodes.search_node")
local Tree = require("ya-tree.trees.tree")
local ui = require("ya-tree.ui")
local log = require("ya-tree.log")

local api = vim.api

---@class YaSearchTree : YaTree
---@field TYPE "search"
---@field private _singleton false
---@field root YaTreeSearchNode
---@field current_node? YaTreeSearchNode
local SearchTree = { TYPE = "search", _singleton = false }
SearchTree.__index = SearchTree
SearchTree.__eq = Tree.__eq
SearchTree.__tostring = Tree.__tostring
setmetatable(SearchTree, { __index = Tree })

---@async
---@param tabpage integer
---@param path string
---@return YaSearchTree tree
function SearchTree:new(tabpage, path)
  local this = Tree.new(self, tabpage)
  this:_init(path)

  local event = require("ya-tree.events.event")
  events.on_git_event(this:create_event_id(event.GIT), function(repo)
    this:on_git_event(repo)
  end)

  log.debug("created new tree %s", tostring(this))
  return this
end

function SearchTree:delete()
  local event = require("ya-tree.events.event")
  events.remove_event_handler(event.GIT, self:create_event_id(event.GIT))
end

---@async
---@private
---@param self YaSearchTree
---@param path string
function SearchTree:_init(path)
  local fs_node = fs.node_for(path) --[[@as FsNode]]
  self.root = SearchNode:new(fs_node)
  self.root.repo = git.get_repo_for_path(self.root.path)
end

---@async
---@param repo GitRepo
function SearchTree:on_git_event(repo)
  if
    vim.v.exiting == vim.NIL
    and (self.root:is_ancestor_of(repo.toplevel) or repo.toplevel:find(self.root.path, 1, true) ~= nil)
    and self:is_shown_in_ui(api.nvim_get_current_tabpage())
  then
    log.debug("git repo %s changed", tostring(repo))
    ui.update(self)
  end
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
