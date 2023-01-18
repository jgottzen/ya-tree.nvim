local diagnostics = require("ya-tree.diagnostics")
local log = require("ya-tree.log").get("nodes")
local lsp = require("ya-tree.lsp")
local meta = require("ya-tree.meta")
local Node = require("ya-tree.nodes.node")
local symbol_kind = require("ya-tree.lsp.symbol_kind")

local api = vim.api

---@class Yat.Nodes.Symbol : Yat.Node
---@field new fun(self: Yat.Nodes.Symbol, name: string, path: string, kind: Lsp.Symbol.Kind, detail?: string, position: Yat.Document.Range, parent?: Yat.Nodes.Symbol): Yat.Nodes.Symbol
---@overload fun(name: string, path: string, kind: Lsp.Symbol.Kind, detail?: string, position: Yat.Document.Range, parent?: Yat.Nodes.Symbol): Yat.Nodes.Symbol
---@field class fun(self: Yat.Nodes.Symbol): Yat.Nodes.Symbol
---@field super Yat.Node
---
---@field protected __node_type "symbol"
---@field public parent? Yat.Nodes.Symbol
---@field private _children? Yat.Nodes.Symbol[]
---@field private file string
---@field private _bufnr integer
---@field public kind Lsp.Symbol.Kind
---@field public detail? string
---@field public position Yat.Document.Range
local SymbolNode = meta.create_class("Yat.Nodes.Symbol", Node)
SymbolNode.__node_type = "symbol"

---@private
---@param name string
---@param path string
---@param kind Lsp.Symbol.Kind
---@param detail? string
---@param position Yat.Document.Range
---@param parent? Yat.Nodes.Symbol
function SymbolNode:init(name, path, kind, detail, position, parent)
  self.super:init({
    name = name,
    path = path,
    _type = "file",
  }, parent)
  if kind == symbol_kind.FILE then
    self._children = {}
    self.empty = true
  end
  self.file = parent and parent.file or path
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

---@return boolean editable
function SymbolNode:is_editable()
  return true
end

---@return integer|nil
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
    api.nvim_win_set_cursor(0, { self.position.start.line + 1, self.position.start.character })
  end
end

---@protected
function SymbolNode:_scandir() end

---@param symbol Yat.Symbols.Document
function SymbolNode:add_node(symbol)
  self:add_child(symbol)
end

---@param symbol Yat.Symbols.Document
function SymbolNode:add_child(symbol)
  if not self._children then
    self._children = {}
    self.empty = true
  end
  local path = self.path .. "/" .. symbol.name .. (#self._children + 1)
  local node = SymbolNode:new(symbol.name, path, symbol.kind, symbol.detail, symbol.range, self)
  node._bufnr = self._bufnr
  node.symbol = symbol
  self._children[#self._children + 1] = node
  if symbol.children then
    for _, child_symbol in ipairs(symbol.children) do
      node:add_child(child_symbol)
    end
  end
end

---@async
---@param opts? { bufnr?: integer, use_cache?: boolean }
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
  log.debug("refreshing %q, bufnr=%s, refresh=%s", self.path, bufnr, refresh)

  self._children = {}
  self.empty = true
  local symbols = lsp.get_symbols(bufnr, refresh)
  for _, symbol in ipairs(symbols) do
    self:add_child(symbol)
  end
  self.empty = #self._children ~= 0
end

return SymbolNode
