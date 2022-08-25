local scheduler = require("plenary.async.util").scheduler
local Path = require("plenary.path")

local Node = require("ya-tree.nodes.node")
local fs = require("ya-tree.filesystem")
local git = require("ya-tree.git")
local log = require("ya-tree.log")
local node_utils = require("ya-tree.nodes.utils")
local utils = require("ya-tree.utils")

local api = vim.api
local fn = vim.fn

---@alias buffer_type file_type | "terminal" | "container"

---@class YaTreeBufferNode : YaTreeNode
---@field public parent? YaTreeBufferNode
---@field private type buffer_type
---@field public bufname? string
---@field public bufnr? number
---@field public hidden? boolean
---@field public children? YaTreeBufferNode[]
local BufferNode = { __node_type = "Buffer" }
BufferNode.__index = BufferNode
BufferNode.__tostring = Node.__tostring
BufferNode.__eq = Node.__eq
setmetatable(BufferNode, { __index = Node })

---Creates a new buffer node.
---@param fs_node FsNode filesystem data.
---@param parent? YaTreeBufferNode the parent node.
---@param bufname? string the vim buffer name.
---@param bufnr? number the buffer number.
---@param modified? boolean if the buffer is modified.
---@param hidden? boolean if the buffer is listed.
---@return YaTreeBufferNode node
function BufferNode:new(fs_node, parent, bufname, bufnr, modified, hidden)
  local this = node_utils.create_node(self, fs_node, parent)
  this.bufname = bufname
  this.bufnr = bufnr
  this.modified = modified or false
  this.hidden = hidden
  if this:is_container() then
    this.empty = true
    this.scanned = true
    this.expanded = true
  end
  return this
end

---@return boolean is_container
function BufferNode:is_container()
  return self.type == "container" or self.type == "directory"
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

---@param node? YaTreeBufferNode
---@return boolean is_container
local function is_terminals_container(node)
  return node and node.type == "container" and node.extension == "terminal" or false
end

---@param a YaTreeBufferNode
---@param b YaTreeBufferNode
---@return boolean
function BufferNode.node_comparator(a, b)
  if is_terminals_container(a) then
    return false
  elseif is_terminals_container(b) then
    return true
  end
  return Node.node_comparator(a, b)
end

---@private
function BufferNode:_scandir() end

---@class FileBufferData
---@field bufnr number
---@field modified boolean

---@class TerminalBufferData
---@field name string
---@field bufnr number

---@return table<string, FileBufferData> paths, TerminalBufferData[] terminal
local function get_current_buffers()
  ---@type table<string, FileBufferData>
  local buffers = {}
  ---@type TerminalBufferData[]
  local terminals = {}
  for _, bufnr in ipairs(api.nvim_list_bufs()) do
    ---@cast bufnr number
    local ok, buftype = pcall(api.nvim_buf_get_option, bufnr, "buftype")
    if ok then
      ---@type string
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

---@param root YaTreeBufferNode
---@return YaTreeBufferNode container
local function create_terminal_buffers_container(root)
  local container = BufferNode:new({
    name = "Terminals",
    type = "container",
    path = "Terminals",
    extension = "terminal",
  }, root)
  root.children[#root.children + 1] = container
  root.empty = false
  return container
end

---@param container YaTreeBufferNode
---@param terminal TerminalBufferData
---@return YaTreeBufferNode node
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
  }, container, terminal.name, terminal.bufnr, hidden)
  container.children[#container.children + 1] = node
  container.empty = false
  log.debug("adding terminal buffer %s (%q)", node.bufnr, node.bufname)
  return node
end

---@async
---@param opts? { root_path?: string }
--- -- {opts.root_path?} `string`
---@return YaTreeBufferNode first_leaf_node
function BufferNode:refresh(opts)
  if self.parent then
    return self.parent:refresh(opts)
  end

  opts = opts or {}
  scheduler()
  local buffers, terminals = get_current_buffers()
  ---@type string[]
  local paths = vim.tbl_keys(buffers)
  local root_path = get_buffers_root_path(opts.root_path or self.path, paths)
  if root_path ~= self.path then
    log.debug("setting new root path to %q", root_path)
    local fs_node = fs.node_for(root_path) --[[@as FsNode]]
    self:_merge_new_data(fs_node)
    self.scanned = true
    self.expanded = true
    self.repo = git.get_repo_for_path(root_path)
  end

  self.children = {}
  self.empty = true
  local first_leaf_node = node_utils.create_tree_from_paths(self, paths, function(path, parent)
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
      first_leaf_node = container.children[1]
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
---@return YaTreeBufferNode|nil node if {opts.to} is specified, and found.
function BufferNode:expand(opts)
  opts = opts or {}
  if opts.to and vim.startswith(opts.to, "term://") then
    if self.children then
      local container = self.children[#self.children]
      if is_terminals_container(container) then
        for _, child in ipairs(container.children) do
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
---@return YaTreeBufferNode|nil node
function BufferNode:add_buffer(file, bufnr, is_terminal)
  if self.parent then
    return self.parent:add_buffer(file, bufnr, is_terminal)
  end

  if is_terminal then
    local container = self.children[#self.children]
    if not is_terminals_container(container) then
      container = create_terminal_buffers_container(self)
    end
    return add_terminal_buffer_to_container(container, { name = file, bufnr = bufnr })
  else
    return node_utils.add_fs_node(self, file, function(fs_node, parent)
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

  local container = self.children[#self.children]
  if is_terminals_container(container) then
    for _, child in ipairs(container.children) do
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
    local container = self.children[#self.children]
    if is_terminals_container(container) then
      for index, child in ipairs(container.children) do
        if child.bufname == file and child.bufnr == bufnr then
          table.remove(container.children, index)
          log.debug("removed terminal buffer %s (%q)", child.bufnr, child.bufname)
          break
        end
      end
      if #container.children == 0 then
        table.remove(self.children, #self.children)
        self.empty = #self.children == 0
        log.debug("no more terminal buffers present, removed container item")
      end
    end
  else
    node_utils.remove_fs_node(self, file)
  end
end

return BufferNode
