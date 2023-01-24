local defer = require("ya-tree.async").defer
local fs = require("ya-tree.fs")
local git = require("ya-tree.git")
local log = require("ya-tree.log").get("panels")
local lsp = require("ya-tree.lsp")
local meta = require("ya-tree.meta")
local scheduler = require("ya-tree.async").scheduler
local symbol_kind = require("ya-tree.lsp.symbol_kind")
local SymbolNode = require("ya-tree.nodes.symbol_node")
local TreePanel = require("ya-tree.panels.tree_panel")
local utils = require("ya-tree.utils")

local api = vim.api
local uv = vim.loop

---@class Yat.Panel.Symbols : Yat.Panel.Tree
---@field new async fun(self: Yat.Panel.Symbols, sidebar: Yat.Sidebar, config: Yat.Config.Panels.Symbols, keymap: table<string, Yat.Action>, renderers: Yat.Panel.TreeRenderers): Yat.Panel.Symbols
---@overload async fun(sidebar: Yat.Sidebar, config: Yat.Config.Panels.Symbols, keymap: table<string, Yat.Action>, renderers: Yat.Panel.TreeRenderers): Yat.Panel.Symbols
---@field class fun(self: Yat.Panel.Symbols): Yat.Panel.Symbols
---@field static Yat.Panel.Symbols
---@field super Yat.Panel.Tree
---
---@field public TYPE "symbols"
---@field public root Yat.Nodes.Symbol
---@field public current_node Yat.Nodes.Symbol
local SymbolsPanel = meta.create_class("Yat.Panel.Symbols", TreePanel)

---@async
---@private
---@param sidebar Yat.Sidebar
---@param config Yat.Config.Panels.Symbols
---@param keymap table<string, Yat.Action>
---@param renderers Yat.Panel.TreeRenderers
function SymbolsPanel:init(sidebar, config, keymap, renderers)
  local path = uv.cwd() --[[@as string]]
  local root = self:create_root_node(path)
  self.super:init("symbols", sidebar, config.title, config.icon, keymap, renderers, root)
  self.current_node = self.root:refresh() or root
  if self:has_renderer("modified") then
    self:register_buffer_modified_event()
  end
  self:register_buffer_saved_event()
  self:register_buffer_enter_event()
  self:register_lsp_attach_event()
  self:register_diagnostics_changed_event()

  log.info("created panel %s", tostring(self))
end

---@async
---@private
---@nodiscard
---@param path string
---@param bufnr? integer
---@return Yat.Nodes.Symbol
function SymbolsPanel:create_root_node(path, bufnr)
  local do_schedule = bufnr == nil
  if not bufnr then
    scheduler()
    bufnr = api.nvim_get_current_buf()
    local buftype = api.nvim_buf_get_option(bufnr, "buftype")
    if buftype == "" then
      path = api.nvim_buf_get_name(bufnr)
    else
      bufnr = nil
      local buffers = utils.get_current_buffers()
      if buffers[path] then
        bufnr = buffers[path].bufnr
      end
    end
  end
  local name = utils.get_file_name(path)
  local root = SymbolNode:new(name, path, symbol_kind.FILE, nil, {
    start = { line = 0, character = 0 },
    ["end"] = { line = -1, character = -1 },
  })
  root.repo = git.get_repo_for_path(path)

  if bufnr then
    if do_schedule then
      defer(function()
        root:refresh({ bufnr = bufnr, use_cache = true })
        root:expand()
        self:draw()
      end)
    else
      root:refresh({ bufnr = bufnr, use_cache = true })
      root:expand()
    end
  end

  return root
end

---@async
---@private
---@param bufnr integer
function SymbolsPanel:on_buffer_saved(bufnr)
  self.root:refresh({ bufnr = bufnr, use_cache = false })
  self:draw()
end

---@async
---@private
---@param bufnr integer
---@param file string
function SymbolsPanel:on_buffer_enter(bufnr, file)
  local ok, buftype = pcall(api.nvim_buf_get_option, bufnr, "buftype")
  if ok and buftype == "" and file ~= "" and self.root.path ~= file and fs.is_file(file) then
    self.root = self:create_root_node(file, bufnr)
    self.current_node = self.root
    self:draw()
  end
end

---@private
function SymbolsPanel:register_lsp_attach_event()
  local event = require("ya-tree.events.event").autocmd.LSP_ATTACH
  self:register_autocmd_event(event, function(bufnr, file)
    self:on_lsp_attach(bufnr, file)
  end)
end

---@async
---@private
---@param bufnr integer
---@param file string
function SymbolsPanel:on_lsp_attach(bufnr, file)
  if self.root.path == file and #self.root:children() == 0 then
    self.root:refresh({ bufnr = bufnr, use_cache = true })
    self:draw()
  end
end

---@protected
function SymbolsPanel:on_win_open()
  self.super.on_win_open(self)
  if require("ya-tree.config").config.panels.symbols.scroll_buffer_to_symbol then
    api.nvim_create_autocmd("CursorHold", {
      group = self.window_augroup,
      buffer = self:bufnr(),
      callback = function()
        self:on_cursor_hold()
      end,
    })
  end
end

---@async
---@private
function SymbolsPanel:on_cursor_hold()
  local node = self:get_current_node() --[[@as Yat.Nodes.Symbol?]]
  if not node or self.root == node then
    return
  end

  api.nvim_win_set_cursor(self.sidebar:edit_win(), { node.position.start.line + 1, node.position.start.character })
  lsp.highlight_range(node:bufnr(), node.position)
  api.nvim_create_autocmd({ "CursorMoved", "BufLeave" }, {
    callback = function()
      lsp.clear_highlights(node:bufnr())
    end,
    once = true,
  })
end

---@async
---@param path string
function SymbolsPanel:change_root_node(path)
  if not fs.is_directory(path) and self.root.path ~= path then
    self.root = self:create_root_node(path)
    self.current_node = self.root
    self:draw()
  end
end

---@protected
---@return fun(bufnr: integer)
---@return string search_root
function SymbolsPanel:get_complete_func_and_search_root()
  return function(bufnr)
    return self:complete_func_loaded_nodes(bufnr)
  end, self.root.path
end

return SymbolsPanel
