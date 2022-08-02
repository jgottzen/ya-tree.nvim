local Node = require("ya-tree.nodes.node")
local fs = require("ya-tree.filesystem")
local log = require("ya-tree.log")
local node_utils = require("ya-tree.nodes.utils")

---@class YaTreeGitNode : YaTreeNode
---@field public parent YaTreeGitRootNode|YaTreeGitNode
---@field public children? YaTreeGitNode[]
---@field public repo GitRepo
local GitNode = { __node_type = "GitStatus" }
GitNode.__index = GitNode
GitNode.__tostring = Node.__tostring
GitNode.__eq = Node.__eq
setmetatable(GitNode, { __index = Node })

---Creates a new git status node.
---@param fs_node FsNode filesystem data.
---@param parent YaTreeGitRootNode|YaTreeGitNode the parent node.
---@return YaTreeGitNode node
function GitNode:new(fs_node, parent)
  local this = node_utils.create_node(self, fs_node, parent)
  if this:is_directory() then
    this.empty = true
    this.scanned = true
    this.expanded = true
  end
  return this
end

---@private
function GitNode:_scandir() end

---@async
---@param opts? { refresh_git?: boolean }
---  - {opts.refresh_git?} `boolean` whether to refresh the git status, default: `true`.
---@return YaTreeGitNode first_leaf_node
function GitNode:refresh(opts)
  return self.parent:refresh(opts)
end

---@class YaTreeGitRootNode : YaTreeGitNode
---@field public parent nil
---@field public children YaTreeGitNode[]
---@field public repo GitRepo
local GitRootNode = { __node_type = "GitStatus" }
GitRootNode.__index = GitRootNode
GitRootNode.__tostring = Node.__tostring
GitRootNode.__eq = Node.__eq
setmetatable(GitRootNode, { __index = GitNode })

---Creates a new git status node.
---@param fs_node FsNode filesystem data.
---@return YaTreeGitRootNode node
function GitRootNode:new(fs_node)
  local this = node_utils.create_node(self, fs_node)
  this.empty = true
  this.scanned = true
  this.expanded = true
  return this
end

---@private
function GitRootNode:_scandir() end

---@async
---@param opts? { refresh_git?: boolean }
---  - {opts.refresh_git?} `boolean` whether to refresh the git status, default: `true`.
---@return YaTreeGitNode first_leaf_node
function GitRootNode:refresh(opts)
  local refresh_git = opts and opts.refresh_git or true
  log.debug("refreshing git status node %q", self.path)
  if refresh_git then
    self.repo:refresh_status({ ignored = true })
  end

  local git_status = self.repo:git_status()
  ---@type string[]
  local paths = {}
  for path in pairs(git_status) do
    if self:is_ancestor_of(path) then
      paths[#paths + 1] = path
    end
  end

  self.children = {}
  self.empty = true
  return node_utils.create_tree_from_paths(self, paths, function(path, parent)
    local fs_node = fs.node_for(path)
    if fs_node then
      return GitNode:new(fs_node, parent)
    end
  end)
end

---@async
---@param file string
---@return YaTreeGitNode|nil node
function GitRootNode:add_file(file)
  return node_utils.add_fs_node(self, file, function(fs_node, parent)
    return GitNode:new(fs_node, parent)
  end)
end

---@param file string
function GitRootNode:remove_file(file)
  node_utils.remove_fs_node(self, file)
end

return {
  GitNode = GitNode,
  GitRootNode = GitRootNode,
}
