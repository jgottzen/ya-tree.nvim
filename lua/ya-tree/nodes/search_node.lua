local fs = require("ya-tree.fs")
local git = require("ya-tree.git")
local job = require("ya-tree.job")
local log = require("ya-tree.log").get("nodes")
local meta = require("ya-tree.meta")
local Node = require("ya-tree.nodes.node")
local utils = require("ya-tree.utils")

---@class Yat.Nodes.Search : Yat.Node
---@field new fun(self: Yat.Nodes.Search, fs_node: Yat.Fs.Node, parent?: Yat.Nodes.Search): Yat.Nodes.Search
---@overload fun(fs_node: Yat.Fs.Node, parent?: Yat.Nodes.Search): Yat.Nodes.Search
---@field class fun(self: Yat.Nodes.Search): Yat.Nodes.Search
---@field super Yat.Node
---
---@field protected __node_type "search"
---@field public parent? Yat.Nodes.Search
---@field private _children? Yat.Nodes.Search[]
---@field public search_term? string
---@field private _search_options? { cmd: string, args: string[] }
local SearchNode = meta.create_class("Yat.Nodes.Search", Node)
SearchNode.__node_type = "search"

---Creates a new search node.
---@protected
---@param fs_node Yat.Fs.Node filesystem data.
---@param parent? Yat.Nodes.Search the parent node.
function SearchNode:init(fs_node, parent)
  self.super:init(fs_node, parent)
  if self:is_directory() then
    self.empty = true
    self.expanded = true
  end
end

---@protected
function SearchNode:_scandir() end

---@return boolean hidden
function SearchNode:is_hidden()
  return false
end

---@async
---@param term? string
---@return Yat.Nodes.Search|nil first_leaf_node
---@return integer|string nr_of_matches_or_error
function SearchNode:search(term)
  if self.parent then
    return self.parent:search(term)
  end

  if term then
    local cmd, args = utils.build_search_arguments(term, self.path, true)
    if not cmd then
      return nil, "No suitable search command found!"
    end
    self.search_term = term
    self._search_options = { cmd = cmd, args = args }
  end

  if not self.search_term or not self._search_options then
    return nil, "No search term or command supplied"
  end
  local cmd, args = self._search_options.cmd, self._search_options.args

  self._children = {}
  self.empty = true
  local code, stdout, stderr = job.async_run({ cmd = cmd, args = args, cwd = self.path })
  if not stderr then
    local paths = vim.split(stdout or "", "\n", { plain = true, trimempty = true })
    log.debug("%q found %s matches for %q in %q", cmd, #paths, cmd, self.path)

    local first_leaf_node = self:populate_from_paths(paths, function(path, parent)
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
    log.error("%q with args %s failed with code %s and message %s", cmd, args, code, stderr)
    return nil, stderr
  end
end

---@async
function SearchNode:refresh()
  if self.parent then
    return self.parent:refresh()
  end

  if self.search_term and self._search_options then
    self:search()
  end
end

function SearchNode:clear()
  if self.parent then
    return self.parent:clear()
  end

  self._children = {}
  self.empty = true
  self.search_term = nil
  self._search_options = nil
end

return SearchNode
