local lazy = require("ya-tree.lazy")

local async = lazy.require("ya-tree.async") ---@module "ya-tree.async"
local Config = lazy.require("ya-tree.config") ---@module "ya-tree.config"
local event = lazy.require("ya-tree.events.event") ---@module "ya-tree.events.event"
local fs = lazy.require("ya-tree.fs") ---@module "ya-tree.fs"
local Logger = lazy.require("ya-tree.log") ---@module "ya-tree.log"
local lsp = lazy.require("ya-tree.lsp") ---@module "ya-tree.lsp"
local symbol_kind = lazy.require("ya-tree.lsp.symbol_kind") ---@module "ya-tree.lsp.symbol_kind"
local LspSymbolNode = lazy.require("ya-tree.nodes.lsp_symbol_node") ---@module "ya-tree.nodes.lsp_symbol_node"
local TreePanel = require("ya-tree.panels.tree_panel")
local utils = lazy.require("ya-tree.utils") ---@module "ya-tree.utils"

local api = vim.api
local uv = vim.loop

---@class Yat.Panel.Symbols : Yat.Panel.Tree
---@field new async fun(self: Yat.Panel.Symbols, sidebar: Yat.Sidebar, config: Yat.Config.Panels.Symbols, keymap: table<string, Yat.Action>, renderers: { container: Yat.Panel.Tree.Ui.Renderer[], leaf: Yat.Panel.Tree.Ui.Renderer[] }): Yat.Panel.Symbols
---
---@field public TYPE "symbols"
---@field public root Yat.Node.LspSymbol
---@field public current_node Yat.Node.LspSymbol
local SymbolsPanel = TreePanel:subclass("Yat.Panel.Symbols")

---@async
---@private
---@param sidebar Yat.Sidebar
---@param config Yat.Config.Panels.Symbols
---@param keymap table<string, Yat.Action>
---@param renderers { container: Yat.Panel.Tree.Ui.Renderer[], leaf: Yat.Panel.Tree.Ui.Renderer[] }
function SymbolsPanel:init(sidebar, config, keymap, renderers)
  local path = uv.cwd() --[[@as string]]
  local root = self:create_root_node(path)
  TreePanel.init(self, "symbols", sidebar, config.title, config.icon, keymap, renderers, root)
  if self:has_renderer("modified") then
    self:register_buffer_modified_event()
  end
  self:register_buffer_saved_event()
  self:register_buffer_enter_event()
  self:register_lsp_attach_event()
  self:register_diagnostics_changed_event()

  Logger.get("panels").info("created panel %s", tostring(self))
end

---@async
---@private
---@nodiscard
---@param path string
---@param bufnr? integer
---@return Yat.Node.LspSymbol
function SymbolsPanel:create_root_node(path, bufnr)
  local do_defer = bufnr == nil
  if not bufnr then
    async.scheduler()
    bufnr = api.nvim_get_current_buf()
    local buftype = vim.bo[bufnr].buftype
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
  local name = fs.name_from_path(path)
  local root = LspSymbolNode:new(name, path, symbol_kind.File, nil, {
    start = { line = 0, character = 0 },
    ["end"] = { line = -1, character = -1 },
  })

  if bufnr then
    if do_defer then
      async.run_on_next_tick(function()
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
  if self.root:bufnr() == bufnr then
    self.root:refresh({ use_cache = false })
    self:draw(self.current_node)
  end
end

---@async
---@private
---@param bufnr integer
---@param file string
function SymbolsPanel:on_buffer_enter(bufnr, file)
  local ok, buftype = pcall(function()
    return vim.bo[bufnr].buftype
  end)
  if ok and buftype == "" and file ~= "" and self.root.path ~= file and fs.is_file(file) then
    self.root = self:create_root_node(file, bufnr)
    self.current_node = self.root
    self:draw(self.current_node)
  end
end

---@private
function SymbolsPanel:register_lsp_attach_event()
  self:register_autocmd_event(event.autocmd.LSP_ATTACH, function(bufnr, file)
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
function SymbolsPanel:on_win_opened()
  if Config.config.move_cursor_to_name then
    self:create_move_to_name_autocmd()
  end
  if Config.config.panels.symbols.scroll_buffer_to_symbol then
    api.nvim_create_autocmd("CursorHold", {
      group = self.window_augroup,
      buffer = self:bufnr(),
      callback = function()
        self:on_cursor_hold()
      end,
      desc = "Highlight current symbol",
    })
  end
end

---@async
---@private
function SymbolsPanel:on_cursor_hold()
  local node = self:get_current_node() --[[@as Yat.Node.LspSymbol?]]
  if not node or self.root == node then
    return
  end
  local client_id = node:lsp_client_id()
  if not client_id then
    return
  end

  api.nvim_win_set_cursor(self.sidebar:edit_win(), { node.position.start.line + 1, node.position.start.character })
  lsp.highlight_range(node:bufnr(), client_id, node.position)
  api.nvim_create_autocmd({ "CursorMoved", "BufLeave" }, {
    callback = function()
      lsp.clear_highlights(node:bufnr())
    end,
    once = true,
    desc = "Clear current symbol highlighting",
  })
end

---@async
function SymbolsPanel:refresh()
  local log = Logger.get("panels")
  if self.refreshing or vim.v.exiting ~= vim.NIL then
    log.debug("refresh already in progress or vim is exiting, aborting refresh")
    return
  end

  self.refreshing = true
  log.debug("refreshing %q panel", self.TYPE)
  self.root:refresh({ use_cache = false })
  self:draw(self.current_node)
  self.refreshing = false
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

---@async
---@param node? Yat.Node.LspSymbol
function SymbolsPanel:search_for_node(node)
  self:search_for_loaded_node(function(bufnr)
    local root = Config.config.panels.symbols.completion.on == "node" and node or self.root
    local sub_pos = #root.path + 2
    ---@type Yat.Panel.Tree.ComplexCompletionItem[]
    local items = {}
    root:walk(function(current)
      items[#items + 1] = { word = current.path:sub(sub_pos), abbr = current:abbreviated_path():sub(sub_pos) }
    end)
    table.remove(items, 1)
    self:complete_func_complex(bufnr, items)
  end)
end

return SymbolsPanel
