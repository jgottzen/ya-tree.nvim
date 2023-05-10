local lazy = require("ya-tree.lazy")

local Logger = lazy.require("ya-tree.log") ---@module "ya-tree.log"
local lsp = lazy.require("ya-tree.lsp") ---@module "ya-tree.lsp"
local LspDetailsNode = require("ya-tree.nodes.lsp_details_node")
local Path = lazy.require("ya-tree.path") ---@module "ya-tree.path"

---@alias Yat.CallHierarchy.Direction "incoming"|"outgoing"

---@class Yat.Node.CallHierarchy : Yat.Node.LspDetailsNode
---@field new fun(self: Yat.Node.CallHierarchy, name: string, path: string, kind: Lsp.Symbol.Kind, detail?: string, position: Lsp.Range, file: string, parent?: Yat.Node.CallHierarchy): Yat.Node.CallHierarchy
---
---@field public TYPE "call_hierarchy"
---@field public parent? Yat.Node.CallHierarchy
---@field private _children? Yat.Node.CallHierarchy[]
---@field private direction Yat.CallHierarchy.Direction
local CallHierarchyNode = LspDetailsNode:subclass("Yat.Node.CallHierarchy")

---@private
---@param name string
---@param path string
---@param kind Lsp.Symbol.Kind
---@param detail? string
---@param position Lsp.Range
---@param file string
---@param parent? Yat.Node.CallHierarchy
function CallHierarchyNode:init(name, path, kind, detail, position, file, parent)
  LspDetailsNode.init(self, name, path, kind, false, detail, position, file, parent)
  self.TYPE = "call_hierarchy"
end

---@private
---@param call_hierarchy Lsp.CallHierarchy.IncomingCall|Lsp.CallHierarchy.OutgoingCall
function CallHierarchyNode:add_child(call_hierarchy)
  local item = call_hierarchy.from or call_hierarchy.to
  local file = vim.uri_to_fname(item.uri)
  local path = file .. Path.path.sep .. item.name
  local has_chilren = #call_hierarchy.fromRanges > 1
  local location
  if not has_chilren then
    location = call_hierarchy.fromRanges[1]
  else
    location = item.selectionRange
  end
  local node = CallHierarchyNode:new(item.name, path, item.kind, item.detail, location, file, self)
  self._children[#self._children + 1] = node
  if has_chilren then
    node._children = {}
    node.container = true
    for _, from_range in ipairs(call_hierarchy.fromRanges) do
      path = node.path .. Path.path.sep .. (#node._children + 1)
      local child = CallHierarchyNode:new(item.name, path, item.kind, item.detail, from_range, file, node)
      node._children[#node._children + 1] = child
    end
  end
end

---@async
---@param opts {bufnr?: integer, call_site: Lsp.CallHierarchy.Item, direction: Yat.CallHierarchy.Direction}
---  - {opts.bufnr?} `integer` which buffer to use, default: the currently set buffer.
---  - {opts.call_site} `Lsp.CallHierarchy.Item` which call site to create a call hierarchy from.
---  - {opts.direction} `Yat.CallHierarchy.Direction` the direction of calls to genereate.
function CallHierarchyNode:refresh(opts)
  if self.parent then
    return self.parent:refresh(opts)
  end
  self._bufnr = opts.bufnr or self._bufnr
  if not self._bufnr then
    return
  end
  Logger.get("nodes").debug("refreshing %q, bufnr=%s", self.name, self._bufnr)

  self._children = {}
  self.container = true
  local client_id, call_hierarchy
  if opts.direction == "incoming" then
    client_id, call_hierarchy = lsp.incoming_calls(self._bufnr, opts.call_site)
  else
    client_id, call_hierarchy = lsp.outgoing_calls(self._bufnr, opts.call_site)
  end
  if client_id then
    self._lsp_client_id = client_id
    for _, item in ipairs(call_hierarchy) do
      self:add_child(item)
    end
  end
end

return CallHierarchyNode
