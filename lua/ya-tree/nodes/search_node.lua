local wrap = require("plenary.async").wrap

local Node = require("ya-tree.nodes.node")
local fs = require("ya-tree.filesystem")
local git = require("ya-tree.git")
local job = require("ya-tree.job")
local log = require("ya-tree.log")
local node_utils = require("ya-tree.nodes.utils")

---@class YaTreeSearchNode : YaTreeNode
---@field public parent YaTreeSearchRootNode|YaTreeSearchNode
---@field public children? YaTreeSearchNode[]
local SearchNode = { __node_type = "Search" }
SearchNode.__index = SearchNode
SearchNode.__tostring = Node.__tostring
SearchNode.__eq = Node.__eq
setmetatable(SearchNode, { __index = Node })

---Creates a new search node.
---@param fs_node FsNode filesystem data.
---@param parent? YaTreeSearchNode the parent node.
---@return YaTreeSearchNode node
function SearchNode:new(fs_node, parent)
  local this = node_utils.create_node(self, fs_node, parent)
  if this:is_directory() then
    this.empty = true
    this.scanned = true
    this.expanded = true
  end
  return this
end

---@private
function SearchNode:_scandir() end

---@async
function SearchNode:refresh()
  self.parent:refresh()
end

---@class YaTreeSearchRootNode : YaTreeSearchNode
---@field public search_term string
---@field private _search_options { cmd: string, args: string[] }
---@field public parent nil
---@field public children YaTreeSearchNode[]
local SearchRootNode = { __node_type = "Search" }
SearchRootNode.__index = SearchRootNode
SearchRootNode.__tostring = Node.__tostring
SearchRootNode.__eq = Node.__eq
setmetatable(SearchRootNode, { __index = SearchNode })

---Creates a new search node.
---@param fs_node FsNode filesystem data.
---@return YaTreeSearchRootNode node
function SearchRootNode:new(fs_node)
  local this = node_utils.create_node(self, fs_node)
  this.empty = true
  this.scanned = true
  this.expanded = true
  return this
end

---@private
function SearchRootNode:_scandir() end

do
  ---@param path string
  ---@param cmd string
  ---@param args string[]
  ---@param callback fun(stdout?: string[], stderr?: string)
  ---@type async fun(path: string, cmd: string, args: string[]): string[]?,string
  local search = wrap(function(path, cmd, args, callback)
    log.debug("searching for %q in %q", cmd, path)

    job.run({ cmd = cmd, args = args, cwd = path }, function(code, stdout, stderr)
      if code == 0 then
        ---@type string[]
        local lines = vim.split(stdout or "", "\n", { plain = true, trimempty = true })
        log.debug("%q found %s matches for %q in %q", cmd, #lines, cmd, path)
        callback(lines)
      else
        log.error("%q with args %s failed with code %s and message %s", cmd, args, code, stderr)
        callback(nil, stderr)
      end
    end)
  end, 4)

  ---@async
  ---@param term? string
  ---@param cmd? string
  ---@param args? string[]
  ---@return YaTreeSearchNode|nil first_leaf_node
  ---@return number|string matches_or_error
  function SearchRootNode:search(term, cmd, args)
    self.search_term = term and term or self.search_term
    self._search_options = cmd and { cmd = cmd, args = args } or self._search_options
    if not self.search_term or not self._search_options then
      return nil, "No search term or command supplied"
    end

    self.children = {}
    local paths, err = search(self.path, self._search_options.cmd, self._search_options.args)
    if paths then
      local first_leaf_node = node_utils.create_tree_from_paths(self, paths, function(path, parent)
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
      self.empty = true
      return nil, err
    end
  end
end

---@async
function SearchRootNode:refresh()
  if self.search_term and self._search_options then
    self:search()
  end
end

return {
  SearchNode = SearchNode,
  SearchRootNode = SearchRootNode
}
