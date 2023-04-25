local lazy = require("ya-tree.lazy")

local async = lazy.require("ya-tree.async") ---@module "ya-tree.async"
local fs = lazy.require("ya-tree.fs") ---@module "ya-tree.fs"
local FsBasedNode = require("ya-tree.nodes.fs_based_node")
local git = lazy.require("ya-tree.git") ---@module "ya-tree.git"
local Logger = lazy.require("ya-tree.log") ---@module "ya-tree.log"
local Path = lazy.require("ya-tree.path") ---@module "ya-tree.path"
local utils = lazy.require("ya-tree.utils") ---@module "ya-tree.utils"

local api = vim.api
local fn = vim.fn

---@alias Yat.Node.Buffer.Type Luv.FileType|"terminal"

---@class Yat.Node.BufferData : Yat.Fs.Node
---@field public _type Yat.Node.Buffer.Type

---@class Yat.Node.Buffer : Yat.Node.FsBasedNode
---@field new fun(self: Yat.Node.Buffer, node_data: Yat.Node.BufferData|Yat.Fs.Node, parent?: Yat.Node.Buffer, bufname?: string, bufnr?: integer, modified?: boolean, hidden?: boolean): Yat.Node.Buffer
---@overload fun(node_data: Yat.Node.BufferData|Yat.Fs.Node, parent?: Yat.Node.Buffer, bufname?: string, bufnr?: integer, modified?: boolean, hidden?: boolean): Yat.Node.Buffer
---
---@field public type fun(self: Yat.Node.Buffer): Yat.Node.Buffer.Type
---
---@field public TYPE "buffer"
---@field public parent? Yat.Node.Buffer
---@field private _type Yat.Node.Buffer.Type
---@field private _children? Yat.Node.Buffer[]
---@field public bufname? string
---@field public bufnr? integer
---@field public bufhidden? boolean
local BufferNode = FsBasedNode:subclass("Yat.Node.Buffer")

---@param other Yat.Node.Buffer
function BufferNode.__eq(self, other)
  if self._type == "terminal" then
    return other._type == "terminal" and self.bufname == other.bufname
  else
    return FsBasedNode.__eq(self, other)
  end
end

local TERMINALS_CONTAINER_PATH = "/yatree://terminals/container"

---Creates a new buffer node.
---@protected
---@param node_data Yat.Node.BufferData node data.
---@param parent? Yat.Node.Buffer the parent node.
---@param bufname? string the vim buffer name.
---@param bufnr? integer the buffer number.
---@param modified? boolean if the buffer is modified.
---@param hidden? boolean if the buffer is listed.
function BufferNode:init(node_data, parent, bufname, bufnr, modified, hidden)
  FsBasedNode.init(self, node_data, parent)
  self.TYPE = "buffer"
  self.bufname = bufname
  self.bufnr = bufnr
  self.modified = modified or false
  self.bufhidden = hidden or false
  if self:is_container() then
    self.empty = true
    self.expanded = true
  end
end

---@return boolean editable
function BufferNode:is_editable()
  return self._type == "file" or self._type == "terminal"
end

---@return boolean hidden
function BufferNode:is_hidden()
  return false
end

---@return boolean is_terminal
function BufferNode:is_terminal()
  return self._type == "terminal"
end

---@return integer? id
function BufferNode:toggleterm_id()
  if self._type == "terminal" then
    return self.bufname:match("#toggleterm#(%d+)$")
  end
end

---@param path string
---@return boolean
local function is_path_neovim_terminal(path)
  return vim.startswith(path, "term://")
end

---@param path string
---@return boolean
function BufferNode:is_ancestor_of(path)
  if is_path_neovim_terminal(path) then
    return self.parent == nil or self:is_terminals_container()
  elseif self:is_terminals_container() and path:find(TERMINALS_CONTAINER_PATH, 1, true) ~= nil then
    return true
  else
    return FsBasedNode.is_ancestor_of(self, path)
  end
end

---@param cmd Yat.Action.Files.Open.Mode
function BufferNode:edit(cmd)
  if self._type == "file" then
    FsBasedNode.edit(self, cmd)
  else
    for _, win in ipairs(api.nvim_list_wins()) do
      if api.nvim_win_get_buf(win) == self.bufnr then
        api.nvim_set_current_win(win)
        return
      end
    end
    local id = self:toggleterm_id()
    if id then
      pcall(vim.cmd --[[@as function]], id .. "ToggleTerm")
    end
  end
end

---@param name string
---@return string
function BufferNode:terminal_name_to_path(name)
  if self.parent then
    return self.parent:terminal_name_to_path(name)
  end
  return self.path .. TERMINALS_CONTAINER_PATH .. "/" .. name
end

---@return boolean
function BufferNode:is_terminals_container()
  return self.container and self.extension == "terminal" and vim.endswith(self.path, TERMINALS_CONTAINER_PATH)
end

---@private
---@return integer? index
---@return Yat.Node.Buffer? container
function BufferNode:get_terminals_container()
  for index, child in ipairs(self._children) do
    if child:is_terminals_container() then
      return index, child
    end
  end
end

---@param file string
---@param bufnr integer
---@param hidden boolean
---@return boolean updated
function BufferNode:set_terminal_hidden(file, bufnr, hidden)
  if self.parent then
    self.parent:set_terminal_hidden(file, bufnr, hidden)
  end

  local _, container = self:get_terminals_container()
  if container then
    for _, child in ipairs(container._children) do
      if child.bufname == file and child.bufnr == bufnr then
        child.bufhidden = hidden
        Logger.get("nodes").debug("setting buffer %s (%q) 'hidden' to %q", child.bufnr, child.bufname, hidden)
        return true
      end
    end
  end
  return false
end

---@param a Yat.Node.Buffer
---@param b Yat.Node.Buffer
---@return boolean
function BufferNode.node_comparator(a, b)
  if a:is_terminals_container() then
    return false
  elseif b:is_terminals_container() then
    return true
  end
  return FsBasedNode.node_comparator(a, b)
end

---Expands the node, if it is a directory. If the node hasn't been scanned before, will scan the directory.
---@async
---@param opts? {to?: string}
---  - {opts.to?} `string` recursively expand to the specified path and return it.
---@return Yat.Node.Buffer|nil node if {opts.to} is specified, and found.
function BufferNode:expand(opts)
  if opts and opts.to and is_path_neovim_terminal(opts.to) then
    opts.to = self:terminal_name_to_path(opts.to)
  end
  return FsBasedNode.expand(self, opts)
end

---@package
---@param node Yat.Node.Buffer
function BufferNode:add_child(node)
  if self._children then
    self._children[#self._children + 1] = node
    self.empty = false
    table.sort(self._children, self.node_comparator)
  end
end

---@param root Yat.Node.Buffer
---@return Yat.Node.Buffer container
local function create_terminal_buffers_container(root)
  local container = BufferNode:new({
    name = "Terminals",
    container = true,
    path = root.path .. TERMINALS_CONTAINER_PATH,
    extension = "terminal",
  }, root)
  root:add_child(container)
  return container
end

---@param container Yat.Node.Buffer
---@param terminal Yat.Node.Buffer.TerminalData
---@return Yat.Node.Buffer node
local function add_terminal_buffer_to_container(container, terminal)
  local name = terminal.name:match("term://(.*)//.*")
  local bufinfo = fn.getbufinfo(terminal.bufnr)
  local hidden = bufinfo[1] and bufinfo[1].hidden == 1 or false
  local node = BufferNode:new({
    name = name,
    _type = "terminal",
    path = container.path .. "/" .. terminal.name,
    extension = "terminal",
  }, container, terminal.name, terminal.bufnr, false, hidden)
  container:add_child(node)
  Logger.get("nodes").debug("adding terminal buffer %s (%q)", node.bufnr, node.bufname)
  return node
end

---@param paths string[]
---@return string[] paths
local function clean_paths(paths)
  local cleaned = {}
  for _, path in ipairs(paths) do
    if fs.exists(path) then
      cleaned[#cleaned + 1] = path
    end
  end
  return cleaned
end

---@param tree_root_path string
---@param paths string[]
---@return string root_path
local function get_buffers_root_path(tree_root_path, paths)
  local root_path
  local size = #paths
  if size == 0 then
    root_path = tree_root_path
  elseif size == 1 then
    root_path = Path:new(paths[1]):parent().filename
  else
    root_path = utils.find_common_ancestor(paths) or tree_root_path
  end
  if vim.startswith(root_path, tree_root_path .. utils.os_sep) then
    root_path = tree_root_path
  end
  return root_path
end

---@async
---@param opts? {root_path?: string}
--- -- {opts.root_path?} `string`
---@return Yat.Node.Buffer first_leaf_node
function BufferNode:refresh(opts)
  if self.parent then
    return self.parent:refresh(opts)
  end

  opts = opts or {}
  async.scheduler()
  local buffers, terminals = utils.get_current_buffers()
  local paths = clean_paths(vim.tbl_keys(buffers))
  local root_path = get_buffers_root_path(opts.root_path or self.path, paths)
  if root_path ~= self.path then
    Logger.get("nodes").debug("setting new root path to %q", root_path)
    local fs_node = fs.node_for(root_path) --[[@as Yat.Fs.Node]]
    self:merge_new_data(fs_node)
    self.expanded = true
  end

  self.repo = git.get_repo_for_path(root_path)
  self._children = {}
  self.empty = true
  local first_leaf_node = self:populate_from_paths(paths, function(path, parent)
    local fs_node = fs.node_for(path)
    if fs_node then
      local buffer_node = buffers[fs_node.path]
      local bufnr = buffer_node and buffer_node.bufnr or nil
      local modified = buffer_node and buffer_node.modified or false
      local node = BufferNode:new(fs_node, parent, buffer_node and path or nil, bufnr, modified, false)
      if not parent.repo or parent.repo:is_yadm() then
        node.repo = git.get_repo_for_path(node.path)
      end
      return node
    end
  end)

  if #terminals > 0 then
    local container = create_terminal_buffers_container(self)
    for _, terminal in ipairs(terminals) do
      add_terminal_buffer_to_container(container, terminal)
    end
    if first_leaf_node == self then
      first_leaf_node = container._children[1]
    end
  end

  return first_leaf_node
end

---@async
---@param path string
---@param bufnr integer
---@param is_terminal boolean
---@return Yat.Node.Buffer|nil node
function BufferNode:add_node(path, bufnr, is_terminal)
  if self.parent then
    return self.parent:add_node(path, bufnr, is_terminal)
  end

  if is_terminal then
    local _, container = self:get_terminals_container()
    if not container then
      container = create_terminal_buffers_container(self)
    end
    return add_terminal_buffer_to_container(container, { name = path, bufnr = bufnr })
  else
    return self:_add_node(path, function(path_part, parent)
      local fs_node = fs.node_for(path_part)
      if fs_node then
        local is_buffer_node = fs_node.path == path
        local node = BufferNode:new(fs_node, parent, is_buffer_node and path or nil, is_buffer_node and bufnr or nil, false, false)
        if not parent.repo or parent.repo:is_yadm() then
          node.repo = git.get_repo_for_path(node.path)
        end
        if is_buffer_node then
          Logger.get("nodes").debug("adding buffer %s (%q)", node.bufnr, node.bufname)
        end
        return node
      end
    end)
  end
end

---@param path string
---@param bufnr integer
---@param is_terminal boolean
---@return boolean updated
function BufferNode:remove_node(path, bufnr, is_terminal)
  local log = Logger.get("nodes")
  if self.parent then
    self.parent:remove_node(path, bufnr, is_terminal)
  end

  if is_terminal then
    local updated = false
    local index, container = self:get_terminals_container()
    if container then
      for i = #container._children, 1, -1 do
        local child = container._children[i]
        if child.bufname == path and child.bufnr == bufnr then
          table.remove(container._children, i)
          updated = true
          log.debug("removed terminal buffer %s (%q)", child.bufnr, child.bufname)
          break
        end
      end
      if #container._children == 0 then
        table.remove(self._children, index)
        self.empty = #self._children == 0
        log.debug("no more terminal buffers present, removed container item")
      end
    end
    return updated
  else
    return FsBasedNode.remove_node(self, path, true)
  end
end

return BufferNode
