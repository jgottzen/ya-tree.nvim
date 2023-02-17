local log = require("ya-tree.log").get("lsp")
local symbol_tag = require("ya-tree.lsp.symbol_tag")
local wrap = require("ya-tree.async").wrap

local lsp = vim.lsp

---@class Lsp.ResponseError
---@field code integer
---@field message string
---@field data? any

---@class Lsp.Position
---@field line integer
---@field character integer

---@class Lsp.Range
---@field start Lsp.Position
---@field end Lsp.Position

---@class Lsp.Symbol.Document
---@field name string
---@field detail? string
---@field kind Lsp.Symbol.Kind
---@field tags? Lsp.Symbol.Tag[]
---@field range Lsp.Range
---@field selectionRange Lsp.Range
---@field children? Lsp.Symbol.Document[]

local DOCUMENT_SYMBOL_METHOD = "textDocument/documentSymbol"

local M = {
  ---@private
  ---@type table<integer, { client_id: integer, symbols: Lsp.Symbol.Document[] }>
  symbol_cache = {},
}

---@param bufnr integer
---@param method string
---@return boolean
local function buf_has_client(bufnr, method)
  return #(vim.tbl_filter(function(client)
    return client.supports_method(method)
  end, lsp.get_active_clients({ bufnr = bufnr }))) > 0
end

---@type async fun(bufnr: integer, method: string, params: table): table<integer, { result?: any[], error?: Lsp.ResponseError }>
local buf_request_all = wrap(function(bufnr, method, params, callback)
  lsp.buf_request_all(bufnr, method, params, function(response)
    callback(response)
  end)
end, 4, true)

---@return Lsp.Symbol.Document[] results
local function normalize_symbols(symbols)
  return vim.tbl_map(function(symbol)
    if not symbol.range then
      symbol.range = symbol.location and symbol.location.range
        or { start = { line = 0, character = 0 }, ["end"] = { line = 0, character = 0 } }
      symbol.location = nil
    end
    if symbol.deprecated then
      if not symbol.tags then
        symbol.tags = { symbol_tag.DEPRECATED }
      elseif not vim.tbl_contains(symbol.tags, symbol_tag.DEPRECATED) then
        symbol.tags[#symbol.tags + 1] = symbol_tag.DEPRECATED
      end
      symbol.deprecated = nil
    end
    return symbol
  end, symbols)
end

---@async
---@param bufnr integer
---@param refresh? boolean
---@return integer? client_id
---@return Lsp.Symbol.Document[] results
function M.symbols(bufnr, refresh)
  if not refresh and M.symbol_cache[bufnr] then
    local t = M.symbol_cache[bufnr]
    return t.client_id, t.symbols
  end
  if refresh then
    log.debug("refreshing document symbols for bufnr %s", bufnr)
  end

  if buf_has_client(bufnr, DOCUMENT_SYMBOL_METHOD) then
    local params = lsp.util.make_text_document_params(bufnr)
    ---@type table<integer, { result?: Lsp.Symbol.Document[], error?: Lsp.ResponseError }>
    local response = buf_request_all(bufnr, DOCUMENT_SYMBOL_METHOD, { textDocument = params })
    for id, results in pairs(response) do
      if results.result then
        local result = normalize_symbols(results.result)
        M.symbol_cache[bufnr] = { client_id = id, symbols = result }
        return id, result
      elseif results.error then
        log.warn("lsp id %s attached to buffer %s returned error: %s", id, bufnr, tostring(results.error))
      end
    end
  else
    log.debug("buffer %s has no attached LSP client that can handle %q", bufnr, DOCUMENT_SYMBOL_METHOD)
  end
  return nil, {}
end

---@param client_id integer
---@return string offset_encoding
local function get_offset_encoding(client_id)
  local client = lsp.get_client_by_id(client_id)
  return client and client.offset_encoding or "utf-16"
end

---@param bufnr integer
---@param client_id integer
---@param range Lsp.Range
function M.highlight_range(bufnr, client_id, range)
  lsp.util.buf_highlight_references(bufnr, { { range = range } }, get_offset_encoding(client_id))
end

---@param bufnr integer
function M.clear_highlights(bufnr)
  lsp.util.buf_clear_references(bufnr)
end

---@param client_id integer
---@param file string
---@param range Lsp.Range
function M.open_location(client_id, file, range)
  lsp.util.show_document({ uri = vim.uri_from_fname(file), range = range }, get_offset_encoding(client_id), { reuse_win = true })
end

local events = require("ya-tree.events")
local ae = require("ya-tree.events.event").autocmd
events.on_autocmd_event(ae.BUFFER_DELETED, "YA_TREE_LSP", false, function(bufnr, file)
  if M.symbol_cache[bufnr] then
    M.symbol_cache[bufnr] = nil
    log.debug("removed bufnr %s (%q) from cache", bufnr, file)
  end
end)

return M
