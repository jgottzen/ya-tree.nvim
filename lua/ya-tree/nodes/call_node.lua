local diagnostics = require("ya-tree.diagnostics")
local log = require("ya-tree.log").get("nodes")
local lsp = require("ya-tree.lsp")
local meta = require("ya-tree.meta")
local Node = require("ya-tree.nodes.node")

---@alias Yat.CallHierarchy.Direction "incoming"|"outgoing"

---@class Yat.Nodes.CallHierarchy : Yat.Node
---@field new fun(self: Yat.Nodes.CallHierarchy, name: string, path: string, kind: Lsp.Symbol.Kind, detail?: string, position: Lsp.Range, bufnr: integer, file: string, parent?: Yat.Nodes.CallHierarchy): Yat.Nodes.CallHierarchy
---@overload fun(name: string, path: string, kind: Lsp.Symbol.Kind, detail?: string, position: Lsp.Range, bufnr: integer, file: string, parent?: Yat.Nodes.CallHierarchy): Yat.Nodes.CallHierarchy
---@field class fun(self: Yat.Nodes.CallHierarchy): Yat.Nodes.CallHierarchy
---@field super Yat.Node
---
---@field protected __node_type "call_hierarchy"
---@field public parent? Yat.Nodes.CallHierarchy
---@field private _children? Yat.Nodes.CallHierarchy[]
---@field private file string
---@field private _bufnr integer
---@field private _lsp_client_id? integer
---@field private direction Yat.CallHierarchy.Direction
---@field public kind Lsp.Symbol.Kind
---@field public detail? string
---@field public position Lsp.Range
local CallHierarchyNode = meta.create_class("Yat.Nodes.CallHierarchy", Node)
CallHierarchyNode.__node_type = "call_hierarchy"

---@private
---@param name string
---@param path string
---@param kind Lsp.Symbol.Kind
---@param detail? string
---@param position Lsp.Range
---@param bufnr integer
---@param parent? Yat.Nodes.CallHierarchy
function CallHierarchyNode:init(name, path, kind, detail, position, bufnr, file, parent)
  self.super:init({
    name = name,
    path = path,
    _type = "file",
  }, parent)
  self.file = file
  self._bufnr = bufnr
  self._lsp_client_id = parent and parent._lsp_client_id
  self.kind = kind
  if detail then
    self.detail = detail:gsub("[\n\r]", " "):gsub("%s+", " ")
  end
  self.position = position
end

---@return integer
function CallHierarchyNode:bufnr()
  return self._bufnr
end

---@return boolean editable
function CallHierarchyNode:is_editable()
  return true
end

---@return DiagnosticSeverity|nil
function CallHierarchyNode:diagnostic_severity()
  if not self.parent then
    -- self is the root node
    return diagnostics.severity_of(self.path)
  end
  local full_diagnostics = diagnostics.diagnostics_of(self.file)
  local severity
  if full_diagnostics then
    for _, diagnostic in ipairs(full_diagnostics) do
      if diagnostic.lnum >= self.position.start.line and diagnostic.end_lnum <= self.position["end"].line then
        if not severity or diagnostic.severity < severity then
          severity = diagnostic.severity
        end
      end
    end
  end
  return severity
end

---@param cmd Yat.Action.Files.Open.Mode
function CallHierarchyNode:edit(cmd)
  vim.cmd({ cmd = cmd, args = { vim.fn.fnameescape(self.file) } })
  lsp.open_location(self._lsp_client_id, self.file, self.position)
end

---@protected
function CallHierarchyNode:_scandir() end

---@param call_hierarchy Lsp.CallHierarchy.IncomingCall|Lsp.CallHierarchy.OutgoingCall
function CallHierarchyNode:add_node(call_hierarchy)
  self:add_child(call_hierarchy)
end

---@param call_hierarchy Lsp.CallHierarchy.IncomingCall|Lsp.CallHierarchy.OutgoingCall
function CallHierarchyNode:add_child(call_hierarchy)
  local item = call_hierarchy.from or call_hierarchy.to
  if not self._children then
    self._children = {}
  end
  self.empty = false
  local file = vim.uri_to_fname(item.uri)
  local path = file .. "/" .. item.name
  local has_chilren = #call_hierarchy.fromRanges > 1
  local location
  if not has_chilren then
    location = call_hierarchy.fromRanges[1]
  else
    location = item.selectionRange
  end
  local node = CallHierarchyNode:new(item.name, path, item.kind, item.detail, location, self._bufnr, file, self)
  self._children[#self._children + 1] = node
  if has_chilren then
    node._children = {}
    node.empty = false
    for _, from_range in ipairs(call_hierarchy.fromRanges) do
      path = node.path .. "/" .. (#node._children + 1)
      local child = CallHierarchyNode:new(item.name, path, item.kind, item.detail, from_range, self._bufnr, file, self)
      node._children[#node._children + 1] = child
    end
  end
end

---@async
---@param opts { call_site: Lsp.CallHierarchy.Item, direction: Yat.CallHierarchy.Direction }
function CallHierarchyNode:refresh(opts)
  if self.parent then
    return self.parent:refresh(opts)
  end
  log.debug("refreshing %q, bufnr=%s", self.name, self.bufnr)

  self._children = {}
  self.empty = true
  local client_id, call_hierarchy
  if opts.direction == "incoming" then
    client_id, call_hierarchy = lsp.incoming_calls(self._bufnr, opts.call_site)
  else
    client_id, call_hierarchy = lsp.outgoing_calls(self._bufnr, opts.call_site)
  end
  self._lsp_client_id = client_id
  for _, item in ipairs(call_hierarchy) do
    self:add_child(item)
  end
end

return CallHierarchyNode
