local CallHierarchyNode = require("ya-tree.nodes.call_node")
local defer = require("ya-tree.async").defer
local log = require("ya-tree.log").get("panels")
local lsp = require("ya-tree.lsp")
local meta = require("ya-tree.meta")
local TextNode = require("ya-tree.nodes.text_node")
local TreePanel = require("ya-tree.panels.tree_panel")
local ui = require("ya-tree.ui")

local api = vim.api
local uv = vim.loop

---@class Yat.Panel.CallHierarchy : Yat.Panel.Tree
---@field new async fun(self: Yat.Panel.CallHierarchy, sidebar: Yat.Sidebar, config: Yat.Config.Panels.CallHierarchy, keymap: table<string, Yat.Action>, renderers: Yat.Panel.TreeRenderers): Yat.Panel.CallHierarchy
---@overload async fun(sidebar: Yat.Sidebar, config: Yat.Config.Panels.CallHierarchy, keymap: table<string, Yat.Action>, renderers: Yat.Panel.TreeRenderers): Yat.Panel.CallHierarchy
---
---@field public TYPE "call_hierarchy"
---@field public root Yat.Node.CallHierarchy|Yat.Node.Text
---@field public current_node Yat.Node.CallHierarchy|Yat.Node.Text
---@field private _direction Yat.CallHierarchy.Direction
---@field private call_site? Lsp.CallHierarchy.Item
local CallHierarchyPanel = meta.create_class("Yat.Panel.CallHierarchy", TreePanel)

---@async
---@private
---@param sidebar Yat.Sidebar
---@param config Yat.Config.Panels.CallHierarchy
---@param keymap table<string, Yat.Action>
---@param renderers Yat.Panel.TreeRenderers
function CallHierarchyPanel:init(sidebar, config, keymap, renderers)
  local path = uv.cwd() --[[@as string]]
  local text = "Waiting for LSP..."
  local root = TextNode:new(text, path, false)
  TreePanel.init(self, "call_hierarchy", sidebar, config.title, config.icon, keymap, renderers, root)
  self._direction = "incoming"
  defer(function()
    local edit_winid = self.sidebar:edit_win()
    local bufnr = api.nvim_win_get_buf(edit_winid)
    local file = api.nvim_buf_get_name(bufnr)
    self:create_call_hierarchy(edit_winid, bufnr, file)
  end)

  log.info("created panel %s", tostring(self))
end

---@async
---@private
---@param winid integer
---@param bufnr integer
---@param file string
function CallHierarchyPanel:create_call_hierarchy(winid, bufnr, file)
  log.info("creating call %q hierarchy for file %q (%s)", self._direction, file, bufnr)
  local call_site, err = lsp.call_site(winid, bufnr)
  if call_site then
    self.call_site = call_site
    self.root = CallHierarchyNode:new(call_site.detail, "", call_site.kind, call_site.detail, call_site.selectionRange, bufnr, file)
    self.root:refresh({ call_site = self.call_site, direction = self._direction })
    self.root:expand()
  else
    if err then
      self.root = TextNode:new(err, file, false)
    else
      self.root = TextNode:new("No call site at cursor position", file, false)
    end
  end
  self:draw()
end

---@async
---@param direction Yat.CallHierarchy.Direction
function CallHierarchyPanel:set_direction(direction)
  if not self.call_site or direction ~= self._direction or self.root:instance_of(TextNode) then
    self._direction = direction
    ---@type integer, integer?
    local bufnr, winid
    if self.root:instance_of(CallHierarchyNode) then
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
  if self.refreshing or vim.v.exiting ~= vim.NIL then
    log.debug("refresh already in progress or vim is exiting, aborting refresh")
    return
  end

  self.refreshing = true
  log.debug("refreshing %q panel", self.TYPE)
  if self.root:instance_of(CallHierarchyNode) then
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

---@return string line
---@return Yat.Ui.HighlightGroup[][] highlights
function CallHierarchyPanel:render_header()
  local direction = self._direction:gsub("^%l", string.upper)
  local line, highligts = TreePanel.render_header(self)
  return line .. " | " .. direction, highligts
end

---@protected
---@return fun(bufnr: integer)
---@return string search_root
function CallHierarchyPanel:get_complete_func_and_search_root()
  return function(bufnr)
    return self:complete_func_loaded_nodes(bufnr)
  end, self.root.path
end

return CallHierarchyPanel
