local Node = require("ya-tree.nodes.node")
local fs = require("ya-tree.fs")
local log = require("ya-tree.log")("nodes")

---@class Yat.Nodes.Git : Yat.Node
---@field private __node_type "Git"
---@field public parent? Yat.Nodes.Git
---@field private _children? Yat.Nodes.Git[]
---@field public repo Yat.Git.Repo
local GitNode = { __node_type = "Git" }
GitNode.__index = GitNode
GitNode.__eq = Node.__eq
GitNode.__tostring = Node.__tostring
setmetatable(GitNode, { __index = Node })

---Creates a new git status node.
---@param fs_node Yat.Fs.Node filesystem data.
---@param parent? Yat.Nodes.Git the parent node.
---@return Yat.Nodes.Git node
function GitNode:new(fs_node, parent)
  local this = Node.new(self, fs_node, parent)
  if this:is_directory() then
    this.empty = true
    this._scanned = true
    this.expanded = true
  end
  return this
end

---@param node Yat.Nodes.Git
---@return boolean displayable
local function is_any_child_displayable(node)
  for _, child in ipairs(node._children) do
    if not child:is_git_ignored() then
      if child:is_directory() and is_any_child_displayable(child) then
        return true
      elseif child:is_file() then
        return true
      end
    end
  end
  return false
end

---@param config Yat.Config
---@return boolean hidden
---@return Yat.Nodes.HiddenReason? reason
function GitNode:is_hidden(config)
  if not config.git.show_ignored then
    if self:is_git_ignored() or (self:is_directory() and not is_any_child_displayable(self)) then
      return true, "git"
    end
  end
  return false
end

---@private
function GitNode:_scandir() end

---@async
---@param opts? { refresh_git?: boolean }
---  - {opts.refresh_git?} `boolean` whether to refresh the git status, default: `true`
---@return Yat.Nodes.Git first_leaf_node
function GitNode:refresh(opts)
  if self.parent then
    return self.parent:refresh(opts)
  end

  opts = opts or {}
  local refresh_git = opts.refresh_git ~= false
  log.debug("refreshing git status node %q", self.path)
  if refresh_git then
    self.repo:refresh_status({ ignored = true })
  end
  local paths = self.repo:working_tree_changed_paths()

  self._children = {}
  self.empty = true
  return self:populate_from_paths(paths, function(path, parent, directory)
    local fs_node = fs.node_for(path)
    if not fs_node then
      fs_node = {
        name = fs.get_file_name(path),
        path = path,
        type = directory and "directory" or "file",
      }
    end
    local node = GitNode:new(fs_node, parent)
    node.is_editable = function(_)
      return false
    end
    return node
  end)
end

return GitNode
