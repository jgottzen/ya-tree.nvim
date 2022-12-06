local Node = require("ya-tree.nodes.node")
local fs = require("ya-tree.fs")
local meta = require("ya-tree.meta")
local log = require("ya-tree.log")("nodes")

---@class Yat.Nodes.Git : Yat.Node
---@field new fun(self: Yat.Nodes.Git, fs_node: Yat.Fs.Node, parent?: Yat.Nodes.Git): Yat.Nodes.Git
---@overload fun(fs_node: Yat.Fs.Node, parent?: Yat.Nodes.Git): Yat.Nodes.Git
---@field class fun(self: Yat.Nodes.Git): Yat.Nodes.Git
---@field super Yat.Node
---
---@field add_node fun(self: Yat.Nodes.Git, path: string): Yat.Nodes.Git?
---@field protected __node_type "Git"
---@field public parent? Yat.Nodes.Git
---@field private _children? Yat.Nodes.Git[]
---@field public repo Yat.Git.Repo
---@field package editable boolean
local GitNode = meta.create_class("Yat.Nodes.Git", Node)
GitNode.__node_type = "Git"

---Creates a new git status node.
---@protected
---@param fs_node Yat.Fs.Node filesystem data.
---@param parent? Yat.Nodes.Git the parent node.
function GitNode:init(fs_node, parent)
  self.super:init(fs_node, parent)
  self.editable = self._type == "file"
  if self:is_directory() then
    self.empty = true
    self.scanned = true
    self.expanded = true
  end
end

---@param node Yat.Nodes.Git
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
---@return Yat.Nodes.HiddenReason? reason
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
    self.repo:status():refresh({ ignored = true })
  end
  local paths = self.repo:status():changed_paths()

  self._children = {}
  self.empty = true
  return self:populate_from_paths(paths, function(path, parent, directory)
    local fs_node = fs.node_for(path)
    local exists = fs_node ~= nil
    if not fs_node then
      fs_node = {
        name = fs.get_file_name(path),
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
end

return GitNode
