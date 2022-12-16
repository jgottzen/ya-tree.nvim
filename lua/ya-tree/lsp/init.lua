local wrap = require("ya-tree.async").wrap
local log = require("ya-tree.log").get("lsp")

local lsp = vim.lsp

---@class Yat.Document.Position
---@field line integer
---@field character integer

---@class Yat.Document.Range
---@field start Yat.Document.Position
---@field end Yat.Document.Position

---@class Yat.Symbols.Document
---@field name string
---@field detail? string
---@field kind Lsp.Symbol.Kind
---@field deprecated? boolean
---@field range Yat.Document.Range
---@field selection_range Yat.Document.Range
---@field children? Yat.Symbols.Document[]

local DOCUMENT_SYMBOL_METHOD = "textDocument/documentSymbol"

local M = {
  ---@private
  ---@type table<integer, Yat.Symbols.Document[]>
  symbols_cache = {},
}

---@param bufnr integer
---@param method string
---@return boolean
local function buf_has_client(bufnr, method)
  return #(vim.tbl_filter(function(client)
    return client.supports_method(method)
  end, lsp.get_active_clients({ bufnr = bufnr }))) > 0
end

---@type async fun(bufnr: integer, method: string, params: table): any
local buf_request_all = wrap(function(bufnr, method, params, callback)
  lsp.buf_request_all(bufnr, method, params, function(response)
    callback(response)
  end)
end, 4, false)

---@async
---@param bufnr integer
---@param refresh? boolean
---@return Yat.Symbols.Document[]? results
function M.get_symbols(bufnr, refresh)
  if not refresh and M.symbols_cache[bufnr] then
    return M.symbols_cache[bufnr]
  end
  if refresh then
    log.debug("refreshing document symbols for bufnr %s", bufnr)
  end

  local params = lsp.util.make_text_document_params(bufnr)
  if not params then
    log.error("failed to create params for buffer %s", bufnr)
    return
  end

  if buf_has_client(bufnr, DOCUMENT_SYMBOL_METHOD) then
    ---@type { result?: Yat.Symbols.Document[] }[]
    local response = buf_request_all(bufnr, DOCUMENT_SYMBOL_METHOD, { textDocument = params })
    for id, results in pairs(response) do
      if results.result and not vim.tbl_isempty(results.result) then
        M.symbols_cache[bufnr] = results.result
        return results.result
      else
        log.warn("lsp id %s attached to buffer %s returned error: %s", id, bufnr, results)
      end
    end
  else
    log.debug("buffer %s has no attached LSP client that can handle %q", bufnr, DOCUMENT_SYMBOL_METHOD)
  end
end

---@param bufnr integer
---@param range Yat.Document.Range
function M.highlight_range(bufnr, range)
  lsp.util.buf_highlight_references(bufnr, { { range = range } }, "utf-8")
end

---@param bufnr integer
function M.clear_highlights(bufnr)
  lsp.util.buf_clear_references(bufnr)
end

function M.setup()
  local events = require("ya-tree.events")
  local ae = require("ya-tree.events.event").autocmd
  events.on_autocmd_event(ae.BUFFER_DELETED, "YA_TREE_LSP", false, function(bufnr, file)
    if M.symbols_cache[bufnr] then
      M.symbols_cache[bufnr] = nil
      log.debug("removed bufnr %s (%q) from cache", bufnr, file)
    end
  end)
end

return M
