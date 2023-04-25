local lazy = require("ya-tree.lazy")

local diagnostics = lazy.require("ya-tree.diagnostics") ---@module "ya-tree.diagnostics"
local Logger = lazy.require("ya-tree.log") ---@module "ya-tree.log"
local lsp = lazy.require("ya-tree.lsp") ---@module "ya-tree.lsp"
local Node = require("ya-tree.nodes.node")
local symbol_kind = lazy.require("ya-tree.lsp.symbol_kind") ---@module "ya-tree.lsp.symbol_kind"

---@class Yat.Node.Symbol : Yat.Node
---@field new fun(self: Yat.Node.Symbol, name: string, path: string, kind: Lsp.Symbol.Kind, detail?: string, position: Lsp.Range, parent?: Yat.Node.Symbol): Yat.Node.Symbol
---@overload fun(name: string, path: string, kind: Lsp.Symbol.Kind, detail?: string, position: Lsp.Range, parent?: Yat.Node.Symbol): Yat.Node.Symbol
---
---@field public TYPE "symbol"
---@field public parent? Yat.Node.Symbol
---@field private _children? Yat.Node.Symbol[]
---@field private file string
---@field private _bufnr integer
---@field private _lsp_client_id integer
---@field private _tags Lsp.Symbol.Tag[]
---@field public kind Lsp.Symbol.Kind
---@field public detail? string
---@field public position Lsp.Range
local SymbolNode = Node:subclass("Yat.Node.Symbol")

---@private
---@param name string
---@param path string
---@param kind Lsp.Symbol.Kind
---@param detail? string
---@param position Lsp.Range
---@param parent? Yat.Node.Symbol
function SymbolNode:init(name, path, kind, detail, position, parent)
  Node.init(self, {
    name = name,
    path = path,
    container = kind == symbol_kind.FILE,
  }, parent)
  self.TYPE = "symbol"
  if kind == symbol_kind.FILE then
    self._children = {}
  end
  self.file = parent and parent.file or path
  if parent then
    self._bufnr = parent._bufnr
    self._lsp_client_id = parent._lsp_client_id
  end
  self._tags = {}
  self.kind = kind
  if detail then
    self.detail = detail:gsub("[\n\r]", " "):gsub("%s+", " ")
  end
  self.position = position
end

---@return integer
function SymbolNode:bufnr()
  return self._bufnr
end

---@return integer? lsp_client_id
function SymbolNode:lsp_client_id()
  return self._lsp_client_id
end

---@return Lsp.Symbol.Tag[]
function SymbolNode:tags()
  return self._tags
end

---@return boolean editable
function SymbolNode:is_editable()
  return true
end

---@return DiagnosticSeverity|nil
function SymbolNode:diagnostic_severity()
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
function SymbolNode:edit(cmd)
  vim.cmd({ cmd = cmd, args = { vim.fn.fnameescape(self.file) } })
  if self.kind ~= symbol_kind.FILE then
    lsp.open_location(self._lsp_client_id, self.file, self.position)
  end
end

---@private
---@param symbol Lsp.Symbol.Document
function SymbolNode:add_child(symbol)
  local path = self.path .. "/" .. symbol.name .. (#self._children + 1)
  local node = SymbolNode:new(symbol.name, path, symbol.kind, symbol.detail, symbol.range, self)
  node.symbol = symbol
  if symbol.tags then
    node._tags = symbol.tags
  end
  self._children[#self._children + 1] = node
  if symbol.children then
    node._children = {}
    node.container = true
    for _, child_symbol in ipairs(symbol.children) do
      node:add_child(child_symbol)
    end
  end
end

---@async
---@param opts? {bufnr?: integer, use_cache?: boolean}
---  - {opts.bufnr?} `integer` which buffer to use, default: the currently set buffer.
---  - {opts.use_cache?} `boolean` whether to use cached data, default: `false`.
function SymbolNode:refresh(opts)
  opts = opts or {}
  if self.parent then
    return self.parent:refresh(opts)
  end
  local bufnr = opts.bufnr or self._bufnr
  if not bufnr then
    return
  end
  local refresh = opts.use_cache ~= true
  self._bufnr = bufnr
  Logger.get("nodes").debug("refreshing %q, bufnr=%s, refresh=%s", self.path, bufnr, refresh)

  self._children = {}
  self.container = true
  local client_id, symbols = lsp.symbols(bufnr, refresh)
  if client_id then
    self._lsp_client_id = client_id
    for _, symbol in ipairs(symbols) do
      self:add_child(symbol)
    end
  end
end

return SymbolNode
