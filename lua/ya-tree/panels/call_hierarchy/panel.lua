local lazy = require("ya-tree.lazy")

local async = lazy.require("ya-tree.async") ---@module "ya-tree.async"
local CallHierarchyNode = lazy.require("ya-tree.nodes.call_node") ---@module "ya-tree.nodes.call_node"
local Config = lazy.require("ya-tree.config") ---@module "ya-tree.config"
local Logger = lazy.require("ya-tree.log") ---@module "ya-tree.log"
local lsp = lazy.require("ya-tree.lsp") ---@module "ya-tree.lsp"
local TextNode = lazy.require("ya-tree.nodes.text_node") ---@module "ya-tree.nodes.text_node"
local TreePanel = require("ya-tree.panels.tree_panel")
local ui = lazy.require("ya-tree.ui") ---@module "ya-tree.ui"

local api = vim.api

---@class Yat.Panel.CallHierarchy : Yat.Panel.Tree
---@field new async fun(self: Yat.Panel.CallHierarchy, sidebar: Yat.Sidebar, config: Yat.Config.Panels.CallHierarchy, keymap: table<string, Yat.Action>, renderers: { container: Yat.Panel.Tree.Ui.Renderer[], leaf: Yat.Panel.Tree.Ui.Renderer[] }): Yat.Panel.CallHierarchy
---
---@field public TYPE "call_hierarchy"
---@field public root Yat.Node.CallHierarchy|Yat.Node.Text
---@field public current_node Yat.Node.CallHierarchy|Yat.Node.Text
---@field private _direction Yat.CallHierarchy.Direction
---@field private call_site? Lsp.CallHierarchy.Item
local CallHierarchyPanel = TreePanel:subclass("Yat.Panel.CallHierarchy")

---@async
---@private
---@param sidebar Yat.Sidebar
---@param config Yat.Config.Panels.CallHierarchy
---@param keymap table<string, Yat.Action>
---@param renderers { container: Yat.Panel.Tree.Ui.Renderer[], leaf: Yat.Panel.Tree.Ui.Renderer[] }
function CallHierarchyPanel:init(sidebar, config, keymap, renderers)
  local root = TextNode:new("Waiting for LSP...", "/")
  TreePanel.init(self, "call_hierarchy", sidebar, config.title, config.icon, keymap, renderers, root)
  self._direction = "incoming"
  async.run_on_next_tick(function()
    local edit_winid = self.sidebar:edit_win()
    local bufnr = api.nvim_win_get_buf(edit_winid)
    local file = api.nvim_buf_get_name(bufnr)
    self:create_call_hierarchy(edit_winid, bufnr, file)
  end)

  Logger.get("panels").info("created panel %s", tostring(self))
end

---@protected
function CallHierarchyPanel:on_win_opened()
  if Config.config.move_cursor_to_name then
    self:create_move_to_name_autocmd()
  end
end

---@async
---@private
---@param winid integer
---@param bufnr integer
---@param file string
function CallHierarchyPanel:create_call_hierarchy(winid, bufnr, file)
  Logger.get("panels").info("creating call %q hierarchy for file %q (%s)", self._direction, file, bufnr)
  local call_site, err = lsp.call_site(winid, bufnr)
  if call_site then
    self.call_site = call_site
    self.root = CallHierarchyNode:new(call_site.detail, "", call_site.kind, call_site.detail, call_site.selectionRange, file)
    self.root:refresh({ bufnr = bufnr, call_site = self.call_site, direction = self._direction })
    self.root:expand()
  else
    self.root = TextNode:new(err or "No call site at cursor position", "/")
  end
  self:draw()
end

---@async
---@param direction Yat.CallHierarchy.Direction
function CallHierarchyPanel:set_direction(direction)
  if not self.call_site or direction ~= self._direction or self.root.TYPE == "text" then
    self._direction = direction
    ---@type integer, integer?
    local bufnr, winid
    if self.root.TYPE == "call_hierarchy" then
      local root = self.root --[[@as Yat.Node.CallHierarchy]]
      bufnr = root:bufnr()
      winid = ui.get_window_for_buffer(bufnr)
    else
      winid = self.sidebar:edit_win()
      bufnr = api.nvim_win_get_buf(winid)
    end
    if winid then
      self:create_call_hierarchy(winid, bufnr, api.nvim_buf_get_name(bufnr))
    end
  end
end

---@async
function CallHierarchyPanel:toggle_direction()
  self:set_direction(self._direction == "incoming" and "outgoing" or "incoming")
end

---@async
function CallHierarchyPanel:create_from_current_buffer()
  local winid = self.sidebar:edit_win()
  if winid then
    local bufnr = api.nvim_win_get_buf(winid)
    self:create_call_hierarchy(winid, bufnr, api.nvim_buf_get_name(bufnr))
  end
end

---@async
---@param args table<string, string>
function CallHierarchyPanel:command_arguments(args)
  if args.direction then
    self.call_site = nil
    self:set_direction(args.direction)
  end
end

---@async
function CallHierarchyPanel:refresh()
  local log = Logger.get("panels")
  if self.refreshing or vim.v.exiting ~= vim.NIL then
    log.debug("refresh already in progress or vim is exiting, aborting refresh")
    return
  end

  self.refreshing = true
  log.debug("refreshing %q panel", self.TYPE)
  if self.root.TYPE == "call_hierarchy" then
    self.root:refresh({ call_site = self.call_site, direction = self._direction })
    self.root:expand()
    self:draw(self.current_node)
  else
    local winid = self.sidebar:edit_win()
    local bufnr = api.nvim_win_get_buf(winid)
    self:create_call_hierarchy(winid, bufnr, api.nvim_buf_get_name(bufnr))
  end
  self.refreshing = false
end

---@async
---@param node? Yat.Node.CallHierarchy|Yat.Node.Text
function CallHierarchyPanel:search_for_node(node)
  if self.root.TYPE == "call_hierarchy" then
    self:search_for_loaded_node(function(bufnr)
      local root = Config.config.panels.symbols.completion.on == "node" and node or self.root --[[@as Yat.Node.CallHierarchy]]
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
end

---@return string line
---@return Yat.Ui.HighlightGroup[][] highlights
function CallHierarchyPanel:render_header()
  local direction = self._direction:gsub("^%l", string.upper)
  local line, highligts = TreePanel.render_header(self)
  return line .. " | " .. direction, highligts
end

return CallHierarchyPanel
