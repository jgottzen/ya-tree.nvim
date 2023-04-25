local lazy = require("ya-tree.lazy")

local diagnostics = lazy.require("ya-tree.diagnostics") ---@module "ya-tree.diagnostics"
local Logger = lazy.require("ya-tree.log") ---@module "ya-tree.log"
local Node = require("ya-tree.nodes.node")
local lsp = lazy.require("ya-tree.lsp") ---@module "ya-tree.lsp"

---@alias Yat.CallHierarchy.Direction "incoming"|"outgoing"

---@class Yat.Node.CallHierarchy : Yat.Node
---@field new fun(self: Yat.Node.CallHierarchy, name: string, path: string, kind: Lsp.Symbol.Kind, detail?: string, position: Lsp.Range, bufnr: integer, file: string, parent?: Yat.Node.CallHierarchy): Yat.Node.CallHierarchy
---@overload fun(name: string, path: string, kind: Lsp.Symbol.Kind, detail?: string, position: Lsp.Range, bufnr: integer, file: string, parent?: Yat.Node.CallHierarchy): Yat.Node.CallHierarchy
---
---@field public TYPE "call_hierarchy"
---@field public parent? Yat.Node.CallHierarchy
---@field private _children? Yat.Node.CallHierarchy[]
---@field private file string
---@field private _bufnr integer
---@field private _lsp_client_id integer
---@field private direction Yat.CallHierarchy.Direction
---@field public kind Lsp.Symbol.Kind
---@field public detail? string
---@field public position Lsp.Range
local CallHierarchyNode = Node:subclass("Yat.Node.CallHierarchy")

---@private
---@param name string
---@param path string
---@param kind Lsp.Symbol.Kind
---@param detail? string
---@param position Lsp.Range
---@param bufnr integer
---@param parent? Yat.Node.CallHierarchy
function CallHierarchyNode:init(name, path, kind, detail, position, bufnr, file, parent)
  Node.init(self, {
    name = name,
    path = path,
    container = false,
  }, parent)
  self.TYPE = "call_hierarchy"
  self.file = file
  self._bufnr = bufnr
  if parent then
    self._lsp_client_id = parent._lsp_client_id
  end
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

---@private
---@param call_hierarchy Lsp.CallHierarchy.IncomingCall|Lsp.CallHierarchy.OutgoingCall
function CallHierarchyNode:add_child(call_hierarchy)
  local item = call_hierarchy.from or call_hierarchy.to
  if not self._children then
    self._children = {}
    self.container = true
  end
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
    for _, from_range in ipairs(call_hierarchy.fromRanges) do
      path = node.path .. "/" .. (#node._children + 1)
      local child = CallHierarchyNode:new(item.name, path, item.kind, item.detail, from_range, self._bufnr, file, self)
      node._children[#node._children + 1] = child
    end
  end
end

---@async
---@param opts {call_site: Lsp.CallHierarchy.Item, direction: Yat.CallHierarchy.Direction}
---  - {opts.call_site?} `Lsp.CallHierarchy.Item` which call site to create a call hierarchy from.
---  - {opts.direction?} `Yat.CallHierarchy.Direction` the direction of calls to genereate.
function CallHierarchyNode:refresh(opts)
  if self.parent then
    return self.parent:refresh(opts)
  end
  Logger.get("nodes").debug("refreshing %q, bufnr=%s", self.name, self.bufnr)

  self._children = {}
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
