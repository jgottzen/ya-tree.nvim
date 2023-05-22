local lazy = require("ya-tree.lazy")

local diagnostics = lazy.require("ya-tree.diagnostics") ---@module "ya-tree.diagnostics"
local lsp = lazy.require("ya-tree.lsp") ---@module "ya-tree.lsp"
local Node = require("ya-tree.nodes.node")
local symbol_kind = lazy.require("ya-tree.lsp.symbol_kind") ---@module "ya-tree.lsp.symbol_kind"

---@class Yat.Node.LspDetailsNode : Yat.Node
---
---@field public parent? Yat.Node.LspDetailsNode
---@field protected _abbreviated_path string
---@field protected _children? Yat.Node.LspDetailsNode[]
---@field protected file string
---@field protected _bufnr integer
---@field protected _lsp_client_id integer
---@field public kind Lsp.Symbol.Kind
---@field public detail? string
---@field public position Lsp.Range
local LspDetailsNode = Node:subclass("Yat.Node.LspDetailsNode")

---@protected
---@param name string
---@param path string
---@param kind Lsp.Symbol.Kind
---@param detail? string
---@param position Lsp.Range
---@param file string
---@param parent? Yat.Node.LspDetailsNode
function LspDetailsNode:init(name, path, kind, container, detail, position, file, parent)
  Node.init(self, {
    name = name,
    path = path,
    container = container,
  }, parent)
  if parent then
    self._bufnr = parent._bufnr
    self._lsp_client_id = parent._lsp_client_id
    self._abbreviated_path = parent._abbreviated_path .. "  " .. name
  else
    self._abbreviated_path = path
  end
  self.kind = kind
  if detail then
    self.detail = detail:gsub("[\n\r]", " "):gsub("%s+", " ")
  end
  self.position = position
  self.file = file
end

---@return string
function LspDetailsNode:abbreviated_path()
  return self._abbreviated_path
end

---@return integer
function LspDetailsNode:bufnr()
  return self._bufnr
end

---@return integer? lsp_client_id
function LspDetailsNode:lsp_client_id()
  return self._lsp_client_id
end

---@return boolean editable
function LspDetailsNode:is_editable()
  return true
end

---@return DiagnosticSeverity|nil
function LspDetailsNode:diagnostic_severity()
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
function LspDetailsNode:edit(cmd)
  vim.cmd({ cmd = cmd, args = { vim.fn.fnameescape(self.file) } })
  if self.kind ~= symbol_kind.File then
    lsp.open_location(self._lsp_client_id, self.file, self.position)
  end
end

return LspDetailsNode
