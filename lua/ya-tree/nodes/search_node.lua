local wrap = require("plenary.async").wrap

local Node = require("ya-tree.nodes.node")
local fs = require("ya-tree.filesystem")
local git = require("ya-tree.git")
local job = require("ya-tree.job")
local log = require("ya-tree.log")
local node_utils = require("ya-tree.nodes.utils")
local utils = require("ya-tree.utils")

---@class YaTreeSearchNode : YaTreeNode
---@field public parent? YaTreeSearchNode
---@field public children? YaTreeSearchNode[]
---@field public search_term? string
---@field private _search_options? { cmd: string, args: string[] }
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
        local lines = vim.split(stdout or "", "\n", { plain = true, trimempty = true }) --[=[@as string[]]=]
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
  ---@return YaTreeSearchNode|nil first_leaf_node
  ---@return number|string nr_of_matches_or_error
  function SearchNode:search(term)
    if self.parent then
      return self.parent:search(term)
    end

    if term then
      local cmd, args = utils.build_search_arguments(term, self.path)
      if not cmd then
        return nil, "No suitable search command found!"
      end
      self.search_term = term
      self._search_options = { cmd = cmd, args = args }
    end

    if not self.search_term or not self._search_options then
      return nil, "No search term or command supplied"
    end

    self.children = {}
    self.empty = true
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
      return nil, err
    end
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

return SearchNode
