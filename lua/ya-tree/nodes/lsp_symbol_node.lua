local lazy = require("ya-tree.lazy")

local Logger = lazy.require("ya-tree.log") ---@module "ya-tree.log"
local lsp = lazy.require("ya-tree.lsp") ---@module "ya-tree.lsp"
local LspDetailsNode = require("ya-tree.nodes.lsp_details_node")
local Path = lazy.require("ya-tree.path") ---@module "ya-tree.path"
local symbol_kind = lazy.require("ya-tree.lsp.symbol_kind") ---@module "ya-tree.lsp.symbol_kind"

---@class Yat.Node.LspSymbol : Yat.Node.LspDetailsNode
---@field new fun(self: Yat.Node.LspSymbol, name: string, path: string, kind: Lsp.Symbol.Kind, detail?: string, position: Lsp.Range, parent?: Yat.Node.LspSymbol): Yat.Node.LspSymbol
---
---@field public TYPE "symbol"
---@field public parent? Yat.Node.LspSymbol
---@field private _children? Yat.Node.LspSymbol[]
---@field private _tags Lsp.Symbol.Tag[]
local LspSymbolNode = LspDetailsNode:subclass("Yat.Node.LspSymbol")

---@private
---@param name string
---@param path string
---@param kind Lsp.Symbol.Kind
---@param detail? string
---@param position Lsp.Range
---@param parent? Yat.Node.LspSymbol
function LspSymbolNode:init(name, path, kind, detail, position, parent)
  LspDetailsNode.init(self, name, path, kind, kind == symbol_kind.File, detail, position, parent and parent.file or path, parent)
  self.TYPE = "symbol"
  self._tags = {}
end

---@return Lsp.Symbol.Tag[]
function LspSymbolNode:tags()
  return self._tags
end

---@private
---@param symbol Lsp.Symbol.Document
function LspSymbolNode:add_child(symbol)
  local path = self.path .. Path.path.sep .. symbol.name .. (#self._children + 1)
  local node = LspSymbolNode:new(symbol.name, path, symbol.kind, symbol.detail, symbol.range, self)
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
function LspSymbolNode:refresh(opts)
  if self.parent then
    return self.parent:refresh(opts)
  end
  opts = opts or {}
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

return LspSymbolNode
