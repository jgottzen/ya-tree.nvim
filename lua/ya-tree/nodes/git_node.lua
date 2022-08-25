local Node = require("ya-tree.nodes.node")
local fs = require("ya-tree.filesystem")
local log = require("ya-tree.log")
local node_utils = require("ya-tree.nodes.utils")

---@class YaTreeGitNode : YaTreeNode
---@field public parent? YaTreeGitNode
---@field public children? YaTreeGitNode[]
---@field public repo GitRepo
local GitNode = { __node_type = "Git" }
GitNode.__index = GitNode
GitNode.__tostring = Node.__tostring
GitNode.__eq = Node.__eq
setmetatable(GitNode, { __index = Node })

---Creates a new git status node.
---@param fs_node FsNode filesystem data.
---@param parent? YaTreeGitNode the parent node.
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
---  - {opts.refresh_git?} `boolean` whether to refresh the git status, default: `true`
---@return YaTreeGitNode first_leaf_node
function GitNode:refresh(opts)
  if self.parent then
    return self.parent:refresh(opts)
  end

  local refresh_git = opts and opts.refresh_git or true
  log.debug("refreshing git status node %q", self.path)
  if refresh_git then
    self.repo:refresh_status({ ignored = true })
  end
  local paths = self.repo:working_tree_changed_paths()

  self.children = {}
  self.empty = true
  return node_utils.create_tree_from_paths(self, paths, function(path, parent, directory)
    local fs_node = fs.node_for(path)
    if not fs_node then
      fs_node = {
        name = fs.get_file_name(path),
        path = path,
        type = directory and "directory" or "file",
      }
    end
    return GitNode:new(fs_node, parent)
  end)
end

---@async
---@param file string
---@return YaTreeGitNode|nil node
function GitNode:add_file(file)
  if self.parent then
    return self.parent:add_file(file)
  end

  return node_utils.add_fs_node(self, file, function(fs_node, parent)
    return GitNode:new(fs_node, parent)
  end)
end

---@param file string
function GitNode:remove_file(file)
  if self.parent then
    return self.parent:remove_file(file)
  end

  node_utils.remove_fs_node(self, file)
end

return GitNode
