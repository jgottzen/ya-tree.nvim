local lazy = require("ya-tree.lazy")

local Config = lazy.require("ya-tree.config") ---@module "ya-tree.config"
local fs = lazy.require("ya-tree.fs") ---@module "ya-tree.fs"
local FsBasedNode = require("ya-tree.nodes.fs_based_node")
local git = lazy.require("ya-tree.git") ---@module "ya-tree.git"
local job = lazy.require("ya-tree.job") ---@module "ya-tree.job"
local Logger = lazy.require("ya-tree.log") ---@module "ya-tree.log"
local utils = lazy.require("ya-tree.utils") ---@module "ya-tree.utils"

---@class Yat.Node.Search : Yat.Node.FsBasedNode
---@field new fun(self: Yat.Node.Search, fs_node: Yat.Fs.Node, parent?: Yat.Node.Search): Yat.Node.Search
---
---@field public TYPE "search"
---@field public parent? Yat.Node.Search
---@field private _children? Yat.Node.Search[]
---@field public search_term? string
---@field private _search_options? { cmd: string, args: string[] }
local SearchNode = FsBasedNode:subclass("Yat.Node.Search")

---Creates a new search node.
---@protected
---@param fs_node Yat.Fs.Node filesystem data.
---@param parent? Yat.Node.Search the parent node.
function SearchNode:init(fs_node, parent)
  FsBasedNode.init(self, fs_node, parent)
  self.TYPE = "search"
  if self:is_directory() then
    self.empty = true
    self.expanded = true
  end
end

---@return boolean hidden
function SearchNode:is_hidden()
  return false
end

---@async
---@param term? string
---@return Yat.Node.Search|nil first_leaf_node
---@return integer|string nr_of_matches_or_error
function SearchNode:search(term)
  if self.parent then
    return self.parent:search(term)
  end

  if term then
    local cmd, args = utils.build_search_arguments(term, self.path, false, Config.config)
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

  local log = Logger.get("nodes")
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

-- selene: allow(unused_variable)

---@async
---@param opts? table<string, any>
---@diagnostic disable-next-line: unused-local
function SearchNode:refresh(opts)
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
