local fs = require("ya-tree.fs")
local log = require("ya-tree.log").get("nodes")
local meta = require("ya-tree.meta")
local Node = require("ya-tree.nodes.node")
local scheduler = require("ya-tree.async").scheduler
local utils = require("ya-tree.utils")

---@class Yat.Node.Git : Yat.Node
---@field new fun(self: Yat.Node.Git, fs_node: Yat.Fs.Node, parent?: Yat.Node.Git): Yat.Node.Git
---@overload fun(fs_node: Yat.Fs.Node, parent?: Yat.Node.Git): Yat.Node.Git
---
---@field public TYPE "git"
---@field public parent? Yat.Node.Git
---@field private _children? Yat.Node.Git[]
---@field public repo Yat.Git.Repo
---@field package editable boolean
local GitNode = meta.create_class("Yat.Node.Git", Node)

---Creates a new git status node.
---@protected
---@param fs_node Yat.Fs.Node filesystem data.
---@param parent? Yat.Node.Git the parent node.
function GitNode:init(fs_node, parent)
  Node.init(self, fs_node, parent)
  self.TYPE = "git"
  self.editable = self._type == "file"
  if self:is_directory() then
    self.empty = true
    self.expanded = true
  end
end

---@param node Yat.Node.Git
---@return boolean displayable
local function is_any_child_displayable(node)
  for _, child in ipairs(node:children()) do
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
---@return Yat.Node.HiddenReason? reason
function GitNode:is_hidden(config)
  if not config.git.show_ignored then
    if self:is_git_ignored() or (self:is_directory() and not is_any_child_displayable(self)) then
      return true, "git"
    end
  end
  return false
end

---@return boolean editable
function GitNode:is_editable()
  return self.editable
end

---@protected
function GitNode:_scandir() end

---@async
---@param opts? {refresh_git?: boolean}
---  - {opts.refresh_git?} `boolean` whether to refresh the git status, default: `true`
---@return Yat.Node.Git first_leaf_node
function GitNode:refresh(opts)
  if self.parent then
    return self.parent:refresh(opts)
  end

  opts = opts or {}
  local refresh_git = opts.refresh_git ~= false
  log.debug("refreshing git status node %q", self.path)
  if refresh_git then
    self.repo:status():refresh({ ignored = true })
  end
  local paths = self.repo:status():changed_paths()

  self._children = {}
  self.empty = true
  local leaf = self:populate_from_paths(paths, function(path, parent, directory)
    local fs_node = fs.node_for(path)
    local exists = fs_node ~= nil
    if not fs_node then
      fs_node = {
        name = utils.get_file_name(path),
        path = path,
        _type = directory and "directory" or "file",
      }
    end
    local node = GitNode:new(fs_node, parent)
    if not exists then
      node.editable = false
    end
    return node
  end)
  scheduler()
  return leaf
end

return GitNode
