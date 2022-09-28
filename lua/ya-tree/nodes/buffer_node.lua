local scheduler = require("plenary.async.util").scheduler
local Path = require("plenary.path")

local Node = require("ya-tree.nodes.node")
local fs = require("ya-tree.filesystem")
local git = require("ya-tree.git")
local log = require("ya-tree.log")("nodes")
local utils = require("ya-tree.utils")

local api = vim.api
local fn = vim.fn

---@alias Yat.Nodes.Buffer.Type Luv.FileType | "terminal"

---@class Yat.Nodes.Buffer : Yat.Node
---@field private __node_type "Buffer"
---@field public parent? Yat.Nodes.Buffer
---@field private type Yat.Nodes.Buffer.Type
---@field private _children? Yat.Nodes.Buffer[]
---@field private terminals_container? boolean
---@field public bufname? string
---@field public bufnr? number
---@field public hidden? boolean
local BufferNode = { __node_type = "Buffer" }
BufferNode.__index = BufferNode
BufferNode.__tostring = Node.__tostring

---@param self Yat.Nodes.Buffer
---@param other Yat.Nodes.Buffer
---@return boolean
BufferNode.__eq = function(self, other)
  if self.type == "terminal" then
    return other.type == "terminal" and self.bufname == other.bufname or false
  else
    return Node.__eq(self, other)
  end
end

setmetatable(BufferNode, { __index = Node })

---Creates a new buffer node.
---@param fs_node Yat.Fs.Node filesystem data.
---@param parent? Yat.Nodes.Buffer the parent node.
---@param bufname? string the vim buffer name.
---@param bufnr? number the buffer number.
---@param modified? boolean if the buffer is modified.
---@param hidden? boolean if the buffer is listed.
---@return Yat.Nodes.Buffer node
function BufferNode:new(fs_node, parent, bufname, bufnr, modified, hidden)
  local this = Node.new(self, fs_node, parent)
  this.bufname = bufname
  this.bufnr = bufnr
  this.modified = modified or false
  this.hidden = hidden
  if this:is_directory() then
    this.empty = true
    this.scanned = true
    this.expanded = true
  end
  return this
end

---@return boolean hidden
function BufferNode:is_hidden()
  return false
end

---@return boolean is_terminal
function BufferNode:is_terminal()
  return self.type == "terminal"
end

---@return number? id
function BufferNode:toggleterm_id()
  if self.type == "terminal" then
    return self.bufname:match("#toggleterm#(%d+)$")
  end
end

---@return boolean
function BufferNode:is_terminals_container()
  return self.terminals_container or false
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

---@private
function BufferNode:_scandir() end

---@class Yat.Nodes.Buffer.FileData
---@field bufnr number
---@field modified boolean

---@class Yat.Nodes.Buffer.TerminalData
---@field name string
---@field bufnr number

---@return table<string, Yat.Nodes.Buffer.FileData> paths, Yat.Nodes.Buffer.TerminalData[] terminal
local function get_current_buffers()
  ---@type table<string, Yat.Nodes.Buffer.FileData>
  local buffers = {}
  ---@type Yat.Nodes.Buffer.TerminalData[]
  local terminals = {}
  for _, bufnr in ipairs(api.nvim_list_bufs()) do
    ---@cast bufnr number
    local ok, buftype = pcall(api.nvim_buf_get_option, bufnr, "buftype")
    if ok then
      local path = api.nvim_buf_get_name(bufnr) --[[@as string]]
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
    type = "directory",
    path = "Terminals",
    extension = "terminal",
  }, root)
  container.terminals_container = true
  root._children[#root._children + 1] = container
  root.empty = false
  return container
end

---@param container Yat.Nodes.Buffer
---@param terminal Yat.Nodes.Buffer.TerminalData
---@return Yat.Nodes.Buffer node
local function add_terminal_buffer_to_container(container, terminal)
  local name = terminal.name:match("term://(.*)//.*")
  local path = fn.fnamemodify(name, ":p")
  local bufinfo = fn.getbufinfo(terminal.bufnr)
  local hidden = bufinfo[1] and bufinfo[1].hidden == 1 or false
  local node = BufferNode:new({
    name = name,
    type = "terminal",
    path = path,
    extension = "terminal",
  }, container, terminal.name, terminal.bufnr, false, hidden)
  container._children[#container._children + 1] = node
  container.empty = false
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
    self.scanned = true
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

---Expands the node, if it is a directory.
--
---@async
---@param opts? {force_scan?: boolean, all?: boolean, to?: string}
---  - {opts.force_scan?} `boolean` rescan directories.
---  - {opts.to?} `string` recursively expand to the specified path and return it.
---@return Yat.Nodes.Buffer|nil node if {opts.to} is specified, and found.
function BufferNode:expand(opts)
  opts = opts or {}
  if opts.to and vim.startswith(opts.to, "term://") then
    if self._children then
      local container = self._children[#self._children]
      if container and container:is_terminals_container() then
        for _, child in ipairs(container._children) do
          if child.bufname == opts.to then
            container.expanded = true
            return child
          end
        end
      end
    end
  else
    return Node.expand(self, opts)
  end
end

---@async
---@param file string
---@param bufnr number
---@param is_terminal boolean
---@return Yat.Nodes.Buffer|nil node
function BufferNode:add_buffer(file, bufnr, is_terminal)
  if self.parent then
    return self.parent:add_buffer(file, bufnr, is_terminal)
  end

  if is_terminal then
    local container = self._children[#self._children]
    if not container or not container:is_terminals_container() then
      container = create_terminal_buffers_container(self)
    end
    return add_terminal_buffer_to_container(container, { name = file, bufnr = bufnr })
  else
    return self:add_node(file, function(fs_node, parent)
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
---@param bufnr number
---@param hidden boolean
function BufferNode:set_terminal_hidden(file, bufnr, hidden)
  if self.parent then
    self.parent:set_terminal_hidden(file, bufnr, hidden)
  end

  local container = self._children[#self._children]
  if container and container:is_terminals_container() then
    for _, child in ipairs(container._children) do
      if child.bufname == file and child.bufnr == bufnr then
        child.hidden = hidden
        log.debug("setting buffer %s (%q) 'hidden' to %q", child.bufnr, child.bufname, hidden)
        break
      end
    end
  end
end

---@param file string
---@param bufnr number
---@param is_terminal boolean
function BufferNode:remove_buffer(file, bufnr, is_terminal)
  if self.parent then
    self.parent:remove_buffer(file, bufnr, is_terminal)
  end

  if is_terminal then
    local container = self._children[#self._children]
    if container and container:is_terminals_container() then
      for i = #container._children, 1, -1 do
        local child = container._children[i]
        if child.bufname == file and child.bufnr == bufnr then
          table.remove(container._children, i)
          log.debug("removed terminal buffer %s (%q)", child.bufnr, child.bufname)
          break
        end
      end
      if #container._children == 0 then
        table.remove(self._children, #self._children)
        self.empty = #self._children == 0
        log.debug("no more terminal buffers present, removed container item")
      end
    end
  else
    self:remove_node(file)
  end
end

return BufferNode
