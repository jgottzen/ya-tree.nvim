local scheduler = require("plenary.async.util").scheduler

local events = require("ya-tree.events")
local ye = require("ya-tree.events.event").ya_tree
local fs = require("ya-tree.fs")
local lsp = require("ya-tree.lsp")
local meta = require("ya-tree.meta")
local symbol_kind = require("ya-tree.lsp.symbol_kind")
local SymbolNode = require("ya-tree.nodes.symbol_node")
local Tree = require("ya-tree.trees.tree")
local utils = require("ya-tree.utils")
local log = require("ya-tree.log").get("trees")

local api = vim.api

---@class Yat.Trees.Symbols : Yat.Tree
---@field new async fun(self: Yat.Trees.Symbols, tabpage: integer, path?: string): Yat.Trees.Symbols?
---@overload async fun(tabpage: integer, path?: string): Yat.Trees.Symbols?
---@field class fun(self: Yat.Trees.Symbols): Yat.Trees.Symbols
---@field super Yat.Tree
---@field static Yat.Trees.Symbols
---
---@field TYPE "symbols"
---@field root Yat.Nodes.Symbol
---@field current_node Yat.Nodes.Symbol
---@field supported_actions Yat.Trees.Symbols.SupportedActions[]
---@field supported_events { autocmd: Yat.Trees.AutocmdEventsLookupTable, git: Yat.Trees.GitEventsLookupTable, yatree: Yat.Trees.YaTreeEventsLookupTable }
---@field complete_func fun(self: Yat.Trees.Symbols, bufnr: integer)
local SymbolsTree = meta.create_class("Yat.Trees.Symbols", Tree)
SymbolsTree.TYPE = "symbols"

---@alias Yat.Trees.Symbols.SupportedActions
---| "toggle_ignored"
---| "toggle_filter"
---
---| "search_for_node_in_tree"
---
---| "focus_prev_diagnostic_item"
---| "focus_next_diagnostic_item"
---
---| Yat.Trees.Tree.SupportedActions

do
  local builtin = require("ya-tree.actions.builtin")
  SymbolsTree.supported_actions = utils.tbl_unique({
    builtin.files.toggle_ignored,
    builtin.files.toggle_filter,

    builtin.search.search_for_node_in_tree,

    builtin.diagnostics.focus_prev_diagnostic_item,
    builtin.diagnostics.focus_next_diagnostic_item,

    unpack(vim.deepcopy(Tree.static.supported_actions)),
  })
end

---@param config Yat.Config
---@return boolean enabled
function SymbolsTree.setup(config)
  SymbolsTree.complete_func = Tree.static.complete_func_loaded_nodes
  SymbolsTree.renderers = Tree.static.create_renderers(SymbolsTree.static.TYPE, config)

  local ae = require("ya-tree.events.event").autocmd
  local supported_events = {
    autocmd = { [ae.BUFFER_SAVED] = SymbolsTree.static.on_buffer_saved },
    git = {},
    yatree = {},
  }
  if config.diagnostics.enable then
    supported_events.yatree[ye.DIAGNOSTICS_CHANGED] = Tree.static.on_diagnostics_event
  end
  SymbolsTree.supported_events = supported_events

  SymbolsTree.keymap = Tree.static.create_mappings(config, SymbolsTree.static.TYPE, SymbolsTree.static.supported_actions)

  return true
end

---@async
---@param path string
---@param bufnr? integer
---@param tabpage integer
---@return Yat.Nodes.Symbol
local function create_root_node(path, bufnr, tabpage)
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

  if bufnr then
    if do_schedule then
      require("plenary.async").void(function()
        root:refresh({ bufnr = bufnr, use_cache = true })
        events.fire_yatree_event(ye.REQUEST_SIDEBAR_REPAINT, tabpage)
      end)()
    else
      root:refresh({ bufnr = bufnr, use_cache = true })
    end
  end

  return root
end

---@async
---@private
---@param tabpage integer
---@param path? string
function SymbolsTree:init(tabpage, path)
  if not path then
    return false
  end
  local root = create_root_node(path, nil, tabpage)
  self.super:init(self.TYPE, tabpage, root, root)

  log.info("created new tree %s", tostring(self))
end

---@async
---@param bufnr integer
---@return boolean update
function SymbolsTree:on_buffer_saved(bufnr)
  self.root:refresh({ bufnr = bufnr, use_cache = false })
  return true
end

---@async
---@param node Yat.Nodes.Symbol
---@param winid integer
function SymbolsTree:on_cursor_hold(node, winid)
  if self.root == node then
    return
  end

  if require("ya-tree.config").config.trees.symbols.scroll_buffer_to_symbol then
    api.nvim_win_set_cursor(winid, { node.position.start.line + 1, node.position.start.character })
  end
  lsp.highlight_range(node:bufnr(), node.position)
  api.nvim_create_autocmd({ "CursorMoved", "BufLeave" }, {
    callback = function()
      lsp.clear_highlights(node:bufnr())
    end,
    once = true,
  })
end

---@async
---@param bufnr integer
---@param file string
---@param is_terminal_buffer boolean
---@return boolean update
function SymbolsTree:on_buffer_enter(bufnr, file, is_terminal_buffer)
  if is_terminal_buffer or self.root.path == file or fs.is_directory(file) then
    return false
  end

  local expanded = self.root.expanded
  self.root = create_root_node(file, bufnr, self.tabpage)
  if expanded then
    self.root:expand()
  end
  self.current_node = self.root
  return true
end

---@async
---@param bufnr integer
---@param file string
---@return boolean update
function SymbolsTree:on_lsp_attach(bufnr, file)
  if self.root.path == file and #self.root:children() == 0 then
    self.root:refresh({ bufnr = bufnr, use_cache = true })
    return true
  end
  return false
end

---@async
---@param path string
function SymbolsTree:change_root_node(path)
  if not fs.is_directory(path) and self.root.path ~= path then
    local old_root = self.root
    self.root = create_root_node(path, nil, self.tabpage)
    if old_root.expanded then
      self.root:expand()
    end
    self.current_node = self.root
  end
end

return SymbolsTree
