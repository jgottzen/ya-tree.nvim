local lazy = require("ya-tree.lazy")

local async = lazy.require("ya-tree.async") ---@module "ya-tree.async"
local Config = lazy.require("ya-tree.config") ---@module "ya-tree.config"
local fs = lazy.require("ya-tree.fs") ---@module "ya-tree.fs"
local Logger = lazy.require("ya-tree.log") ---@module "ya-tree.log"
local Node = require("ya-tree.nodes.node")
local Path = lazy.require("ya-tree.path") ---@module "ya-tree.path"

---@class Yat.Node.FsBasedNodeStatic

---@abstract
---@class Yat.Node.FsBasedNode : Yat.Node
---@field public static Yat.Node.FsBasedNodeStatic
---
---@field protected _type Luv.FileType
---@field public parent? Yat.Node.FsBasedNode
---@field protected _children? Yat.Node.FsBasedNode[]
---@field protected empty? boolean
---@field public extension? string
---@field public absolute_link_to? string
---@field public relative_link_to string
---@field public link_orphan? boolean
---@field public link_name? string
---@field public link_extension? string
---@field private link? boolean
---@field public repo? Yat.Git.Repo
local FsBasedNode = Node:subclass("Yat.Node.FsBasedNode")

---@protected
---@param fs_node Yat.Fs.Node filesystem data.
---@param parent? Yat.Node.FsBasedNode the parent node.
function FsBasedNode:init(fs_node, parent)
  if not fs_node.container then
    fs_node.container = fs_node._type == "directory"
  end
  Node.init(self, fs_node, parent)
  -- inherit any git repo
  if parent and parent.repo then
    self.repo = parent.repo
  end
end

---@param a Yat.Node.FsBasedNode
---@param b Yat.Node.FsBasedNode
---@return boolean
function FsBasedNode.static.directory_first_name_case_insensitive_comparator(a, b)
  local ad = a:is_directory()
  local bd = b:is_directory()
  if ad and not bd then
    return true
  elseif not ad and bd then
    return false
  end
  return a.name:lower() < b.name:lower()
end

FsBasedNode.node_comparator = FsBasedNode.static.directory_first_name_case_insensitive_comparator

---@return Luv.FileType
function FsBasedNode:fs_type()
  return self._type
end

---@return boolean editable
function FsBasedNode:is_editable()
  return self._type == "file"
end

---@return boolean
function FsBasedNode:is_empty()
  return self.empty == true
end

---@return boolean
function FsBasedNode:is_link()
  return self.link == true
end

---@return boolean
function FsBasedNode:is_directory()
  return self._type == "directory"
end

---@return boolean
function FsBasedNode:is_file()
  return self._type == "file"
end

---@return boolean
function FsBasedNode:is_fifo()
  return self._type == "fifo"
end

---@return boolean
function FsBasedNode:is_socket()
  return self._type == "socket"
end

---@return boolean
function FsBasedNode:is_char_device()
  return self._type == "char"
end

---@return boolean
function FsBasedNode:is_block_device()
  return self._type == "block"
end

---@return boolean
function FsBasedNode:is_root_directory()
  return Path.path.root(self.path) == self.path
end

---@param node Yat.Node.FsBasedNode
---@return string
function FsBasedNode:relative_path_to(node)
  return Path:new(self.path):make_relative(node.path)
end

---@param path string
---@return boolean
function FsBasedNode:is_ancestor_of(path)
  if self:is_directory() then
    local self_path = self:is_root_directory() and self.path or (self.path .. Path.path.sep)
    return vim.startswith(path, self_path)
  end
  return false
end

---@alias Yat.Node.HiddenReason "filter"|"git"|string

---@return boolean hidden
---@return Yat.Node.HiddenReason? reason
function FsBasedNode:is_hidden()
  local config = Config.config
  if config.filters.enable then
    if config.filters.dotfiles and self.name:sub(1, 1) == "." then
      return true, "filter"
    elseif vim.tbl_contains(config.filters.custom, self.name) then
      return true, "filter"
    end
  end
  if not config.git.show_ignored then
    if self:is_git_ignored() then
      return true, "git"
    end
  end
  return false
end

---@return boolean
function FsBasedNode:is_git_ignored()
  return self.repo and self.repo:is_ignored(self.path, self:is_directory()) or false
end

---@return boolean
function FsBasedNode:is_git_repository_root()
  return self.repo and self.repo.toplevel == self.path or false
end

---@return string|nil
function FsBasedNode:git_status()
  return self.repo and self.repo:status():of(self.path, self:is_directory())
end

---@async
---@return uv.aliases.fs_stat_table|nil stat
function FsBasedNode:fs_stat()
  return fs.lstat(self.path)
end

---@param cmd Yat.Action.Files.Open.Mode
function FsBasedNode:edit(cmd)
  if self:is_editable() then
    vim.cmd({ cmd = cmd, args = { vim.fn.fnameescape(self.path) } })
  end
end

---@param repo Yat.Git.Repo
function FsBasedNode:set_git_repo(repo)
  local log = Logger.get("nodes")
  if self.repo == repo then
    return
  end
  local toplevel = repo.toplevel
  local node = self
  if toplevel == self.path then
    log.debug("node %q is the toplevel of repo %s, setting repo on node and all child nodes", self.path, tostring(repo))
  elseif vim.startswith(self.path, toplevel) then
    log.debug("node %q is not the toplevel of repo %s, walking up the tree", self.path, tostring(repo))
    -- this node is below the git toplevel directory,
    -- walk the tree upwards until we hit the topmost node
    while node.parent do
      node = node.parent --[[@as Yat.Node.FsBasedNode]]
      if node.path == toplevel then
        break
      end
    end
    log.debug("node %q is the top of the tree, setting repo on node and all child nodes", node.path, tostring(repo))
  else
    log.error("trying to set git repo with toplevel %s on node %s", toplevel, self.path)
    return
  end
  node:walk(function(child)
    child.repo = repo
  end)
end

---@async
---@protected
---@generic T : Yat.Node.FsBasedNode
---@param self T
---@param path string
---@param node_creator async fun(path: string, parent: T, _type: "directory"|"unknown"): T?
---@return T|nil node
function FsBasedNode:_add_node(path, node_creator)
  local log = Logger.get("nodes")
  ---@cast self Yat.Node.FsBasedNode
  local rest = path:sub(#self.path + 1)
  local splits = vim.split(rest, Path.path.sep, { plain = true, trimempty = true })
  local node = self
  for i = 1, #splits do
    if not node.container or not node._children then
      error("Tried to add a node to a non-directory node: " .. self.path)
    end
    local name = splits[i]
    local found = false
    for _, child in ipairs(node._children) do
      if child.name == name then
        found = true
        node = child
        break
      end
    end
    if not found then
      local child_path = node.path .. Path.path.sep .. name
      local child = node_creator(child_path, node, i < #splits and "directory" or "unknown")
      if child then
        log.debug("adding child %q to parent %q", child.path, node.path)
        node._children[#node._children + 1] = child
        node.empty = false
        if self.node_comparator then
          table.sort(node._children, self.node_comparator)
        end
        node = child
      else
        log.error("cannot create node for %q", child_path)
        return nil
      end
    end
  end

  async.scheduler()
  return node
end

---@async
---@protected
---@generic T : Yat.Node.FsBasedNode
---@param self T
---@param paths string[]
---@param node_creator async fun(path: string, parent: T, _type: "directory"|"unknown"): T|nil
---@return T first_leaf_node
function FsBasedNode:populate_from_paths(paths, node_creator)
  ---@cast self Yat.Node.FsBasedNode
  ---@type table<string, Yat.Node.FsBasedNode>
  local node_map = { [self.path] = self }

  ---@param path string
  ---@param parent Yat.Node.FsBasedNode
  ---@param _type "directory"|"unknown"
  local function add_node(path, parent, _type)
    ---@diagnostic disable-next-line: invisible
    if not parent.container or not parent._children then
      error("Tried to add a node to a non-directory node: " .. self.path)
    end
    local node = node_creator(path, parent, _type)
    if node then
      ---@diagnostic disable-next-line:invisible
      parent._children[#parent._children + 1] = node
      ---@diagnostic disable-next-line:invisible
      parent.empty = false
      node_map[node.path] = node
    end
  end

  local min_path_size = #self.path
  for _, path in ipairs(paths) do
    if not node_map[path] and vim.startswith(path, self.path) then
      local parents = Path:new(path):parents()
      for i = #parents, 1, -1 do
        local parent_path = parents[i]
        -- skip paths 'above' the root node
        if #parent_path > min_path_size then
          if not node_map[parent_path] then
            local parent = node_map[parents[i + 1]]
            add_node(parent_path, parent, "directory")
          end
        end
      end

      local parent = node_map[parents[1]]
      add_node(path, parent, "unknown")
    end
  end

  ---@param node Yat.Node.FsBasedNode
  local function sort_children(node)
    if self.node_comparator then
      ---@diagnostic disable-next-line:invisible
      table.sort(node._children, self.node_comparator)
      ---@diagnostic disable-next-line:invisible
      for _, child in ipairs(node._children) do
        ---@diagnostic disable-next-line:invisible
        if child._children ~= nil then
          sort_children(child)
        end
      end
    end
  end

  sort_children(self)

  local first_leaf_node = self
  while first_leaf_node and first_leaf_node._children do
    if first_leaf_node._children[1] then
      first_leaf_node = first_leaf_node._children[1]
    else
      break
    end
  end

  async.scheduler()
  return first_leaf_node
end

return FsBasedNode
