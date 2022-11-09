local scheduler = require("plenary.async.util").scheduler
local Path = require("plenary.path")

local Node = require("ya-tree.nodes.node")
local fs = require("ya-tree.fs")
local git = require("ya-tree.git")
local log = require("ya-tree.log")("nodes")
local utils = require("ya-tree.utils")

local api = vim.api
local fn = vim.fn

---@alias Yat.Nodes.Buffer.Type Luv.FileType | "terminal"

---@class Yat.Node.BufferData : Yat.Fs.Node
---@field public _type Yat.Nodes.Buffer.Type

---@class Yat.Nodes.Buffer : Yat.Node
---@field protected __node_type "Buffer"
---@field public parent? Yat.Nodes.Buffer
---@field private _type Yat.Nodes.Buffer.Type
---@field private _children? Yat.Nodes.Buffer[]
---@field public bufname? string
---@field public bufnr? integer
---@field public bufhidden? boolean
local BufferNode = { __node_type = "Buffer" }
BufferNode.__index = BufferNode
BufferNode.__tostring = Node.__tostring

---@param other Yat.Nodes.Buffer
BufferNode.__eq = function(self, other)
  if self._type == "terminal" then
    return other._type == "terminal" and self.bufname == other.bufname or false
  else
    return Node.__eq(self, other)
  end
end

setmetatable(BufferNode, { __index = Node })

local TERMINALS_CONTAINER_PATH = "/yatree://terminals/container"

---Creates a new buffer node.
---@param node_data Yat.Node.BufferData|Yat.Fs.Node node data.
---@param parent? Yat.Nodes.Buffer the parent node.
---@param bufname? string the vim buffer name.
---@param bufnr? integer the buffer number.
---@param modified? boolean if the buffer is modified.
---@param hidden? boolean if the buffer is listed.
---@return Yat.Nodes.Buffer node
function BufferNode:new(node_data, parent, bufname, bufnr, modified, hidden)
  local this = Node.new(self, node_data, parent)
  this.bufname = bufname
  this.bufnr = bufnr
  this.modified = modified or false
  this.bufhidden = hidden
  if this:is_directory() then
    this.empty = true
    this._scanned = true
    this.expanded = true
  end
  return this
end

---@return boolean hidden
function BufferNode:is_hidden()
  return false
end

---@return Yat.Nodes.Buffer.Type
function BufferNode:type()
  return self._type
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

---@return boolean
function BufferNode:is_terminals_container()
  return self.path:find(TERMINALS_CONTAINER_PATH, 1, true) ~= nil
end

---@return integer? index
---@return Yat.Nodes.Buffer? container
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
function BufferNode:set_terminal_hidden(file, bufnr, hidden)
  if self.parent then
    self.parent:set_terminal_hidden(file, bufnr, hidden)
  end

  local _, container = self:get_terminals_container()
  if container and container:is_terminals_container() then
    for _, child in ipairs(container._children) do
      if child.bufname == file and child.bufnr == bufnr then
        child.bufhidden = hidden
        log.debug("setting buffer %s (%q) 'hidden' to %q", child.bufnr, child.bufname, hidden)
        break
      end
    end
  end
end

---@param a Yat.Nodes.Buffer
---@param b Yat.Nodes.Buffer
---@return boolean
function BufferNode.node_comparator(a, b)
  if a:is_terminals_container() then
    return false
  elseif b:is_terminals_container() then
    return true
  end
  return Node.node_comparator(a, b)
end

---@protected
function BufferNode:_scandir() end

---@class Yat.Nodes.Buffer.FileData
---@field bufnr integer
---@field modified boolean

---@class Yat.Nodes.Buffer.TerminalData
---@field bufnr integer
---@field name string

---@return table<string, Yat.Nodes.Buffer.FileData> paths, Yat.Nodes.Buffer.TerminalData[] terminal
local function get_current_buffers()
  ---@type table<string, Yat.Nodes.Buffer.FileData>
  local buffers = {}
  ---@type Yat.Nodes.Buffer.TerminalData[]
  local terminals = {}
  for _, bufnr in ipairs(api.nvim_list_bufs()) do
    ---@cast bufnr integer
    local ok, buftype = pcall(api.nvim_buf_get_option, bufnr, "buftype")
    if ok then
      local path = api.nvim_buf_get_name(bufnr)
      if buftype == "terminal" then
        terminals[#terminals + 1] = {
          name = path,
          bufnr = bufnr,
        }
      elseif buftype == "" and path ~= "" and api.nvim_buf_is_loaded(bufnr) and fn.buflisted(bufnr) == 1 then
        buffers[path] = {
          bufnr = bufnr,
          modified = api.nvim_buf_get_option(bufnr, "modified"), --[[@as boolean]]
        }
      end
    end
  end
  return buffers, terminals
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
  if root_path:find(tree_root_path .. utils.os_sep, 1, true) ~= nil then
    root_path = tree_root_path
  end
  return root_path
end

---@param root Yat.Nodes.Buffer
---@return Yat.Nodes.Buffer container
local function create_terminal_buffers_container(root)
  local container = BufferNode:new({
    name = "Terminals",
    _type = "directory",
    path = root.path .. TERMINALS_CONTAINER_PATH,
    extension = "terminal",
  }, root)
  root:add_child(container)
  return container
end

---@param container Yat.Nodes.Buffer
---@param terminal Yat.Nodes.Buffer.TerminalData
---@return Yat.Nodes.Buffer node
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
  log.debug("adding terminal buffer %s (%q)", node.bufnr, node.bufname)
  return node
end

---@async
---@param opts? { root_path?: string }
--- -- {opts.root_path?} `string`
---@return Yat.Nodes.Buffer first_leaf_node
function BufferNode:refresh(opts)
  if self.parent then
    return self.parent:refresh(opts)
  end

  opts = opts or {}
  scheduler()
  local buffers, terminals = get_current_buffers()
  local paths = vim.tbl_keys(buffers) --[=[@as string[]]=]
  local root_path = get_buffers_root_path(opts.root_path or self.path, paths)
  if root_path ~= self.path then
    log.debug("setting new root path to %q", root_path)
    local fs_node = fs.node_for(root_path) --[[@as Yat.Fs.Node]]
    self:_merge_new_data(fs_node)
    self._scanned = true
    self.expanded = true
  end

  self.repo = git.get_repo_for_path(root_path)
  self._children = {}
  self.empty = true
  local first_leaf_node = self:populate_from_paths(paths, function(path, parent, _)
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
---@param file string
---@param bufnr integer
---@param is_terminal boolean
---@return Yat.Nodes.Buffer|nil node
function BufferNode:add_node(file, bufnr, is_terminal)
  if self.parent then
    return self.parent:add_node(file, bufnr, is_terminal)
  end

  if is_terminal then
    local _, container = self:get_terminals_container()
    if not container then
      container = create_terminal_buffers_container(self)
    end
    return add_terminal_buffer_to_container(container, { name = file, bufnr = bufnr })
  else
    return self:_add_node(file, function(fs_node, parent)
      local is_buffer_node = fs_node.path == file
      local node = BufferNode:new(fs_node, parent, is_buffer_node and file or nil, is_buffer_node and bufnr or nil, false, false)
      if not parent.repo or parent.repo:is_yadm() then
        node.repo = git.get_repo_for_path(node.path)
      end
      if is_buffer_node then
        log.debug("adding buffer %s (%q)", node.bufnr, node.bufname)
      end
      return node
    end)
  end
end

---@param file string
---@param bufnr integer
---@param is_terminal boolean
function BufferNode:remove_node(file, bufnr, is_terminal)
  if self.parent then
    self.parent:remove_node(file, bufnr, is_terminal)
  end

  if is_terminal then
    local index, container = self:get_terminals_container()
    if container then
      for i = #container._children, 1, -1 do
        local child = container._children[i]
        if child.bufname == file and child.bufnr == bufnr then
          table.remove(container._children, i)
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
  else
    self:_remove_node(file, true)
  end
end

return BufferNode
