local BufferNode = require("ya-tree.nodes.buffer_node")
local fs = require("ya-tree.fs")
local git = require("ya-tree.git")
local log = require("ya-tree.log").get("panels")
local meta = require("ya-tree.meta")
local Path = require("ya-tree.path")
local TreePanel = require("ya-tree.panels.tree_panel")

local api = vim.api
local uv = vim.loop

---@class Yat.Panel.Buffers : Yat.Panel.Tree
---@field new async fun(self: Yat.Panel.Buffers, sidebar: Yat.Sidebar, config: Yat.Config.Panels.Buffers, keymap: table<string, Yat.Action>, renderers: Yat.Panel.TreeRenderers): Yat.Panel.Buffers
---@overload async fun(sidebar: Yat.Sidebar, config: Yat.Config.Panels.Buffers, keymap: table<string, Yat.Action>, renderers: Yat.Panel.TreeRenderers): Yat.Panel.Buffers
---@field class fun(self: Yat.Panel.Buffers): Yat.Panel.Buffers
---@field static Yat.Panel.Buffers
---@field super Yat.Panel.Tree
---
---@field public TYPE "buffers"
---@field public root Yat.Nodes.Buffer
---@field public current_node Yat.Nodes.Buffer
local BuffersPanel = meta.create_class("Yat.Panel.Buffers", TreePanel)

---@async
---@private
---@param sidebar Yat.Sidebar
---@param config Yat.Config.Panels.Buffers
---@param keymap table<string, Yat.Action>
---@param renderers Yat.Panel.TreeRenderers
function BuffersPanel:init(sidebar, config, keymap, renderers)
  local path = uv.cwd() --[[@as string]]
  local fs_node = fs.node_for(path) --[[@as Yat.Fs.Node]]
  local root = BufferNode:new(fs_node)
  root.repo = git.get_repo_for_path(fs_node.path)
  self.super:init("buffers", sidebar, config.title, config.icon, keymap, renderers, root)
  self.current_node = self.root:refresh() or root
  self:register_buffer_modified_event()
  self:register_buffer_saved_event()
  self:register_buffer_enter_event()
  self:register_buffer_new_event()
  self:register_buffer_hidden_event()
  self:register_buffer_displayed_event()
  self:register_buffer_deleted_event()
  self:register_dot_git_dir_changed_event()
  self:register_diagnostics_changed_event()

  log.info("created panel %s", tostring(self))
end

---@private
function BuffersPanel:register_buffer_new_event()
  local event = require("ya-tree.events.event").autocmd.BUFFER_NEW
  self:register_autocmd_event(event, function(bufnr, file)
    self:on_buffer_new(bufnr, file)
  end)
end

---@async
---@private
---@param bufnr integer
---@param file string
function BuffersPanel:on_buffer_new(bufnr, file)
  local buftype = api.nvim_buf_get_option(bufnr, "buftype")
  if (buftype == "" and not fs.is_directory(file)) or buftype == "terminal" then
    local node
    if buftype == "terminal" then
      node = self.root:add_node(file, bufnr, true)
    else
      node = self.root:get_child_if_loaded(file)
      if not node then
        if self.root:is_ancestor_of(file) then
          log.debug("adding buffer %q with bufnr %s to buffers tree", file, bufnr)
          node = self.root:add_node(file, bufnr, false)
        else
          log.debug("buffer %q is not under current buffer tree root %q, refreshing buffer tree", file, self.root.path)
          self.root:refresh()
        end
      elseif node.bufnr ~= bufnr then
        log.debug("buffer %q changed bufnr from %s to %s", file, node.bufnr, bufnr)
        node.bufnr = bufnr
      else
        return
      end
    end

    self:draw(self:get_current_node())
  end
end

---@private
function BuffersPanel:register_buffer_hidden_event()
  local event = require("ya-tree.events.event").autocmd.BUFFER_HIDDEN
  self:register_autocmd_event(event, function(bufnr, file)
    self:on_buffer_hidden(bufnr, file)
  end)
end

---@async
---@private
---@param bufnr integer
---@param file string
function BuffersPanel:on_buffer_hidden(bufnr, file)
  -- BufHidden might be triggered after TermClose, when the buffer no longer exists,
  -- so calling nvim_buf_get_option results in an error.
  local ok, buftype = pcall(api.nvim_buf_get_option, bufnr, "buftype")
  if ok and buftype == "terminal" then
    self.root:set_terminal_hidden(file, bufnr, true)
    self:draw()
  end
end

---@private
function BuffersPanel:register_buffer_displayed_event()
  local event = require("ya-tree.events.event").autocmd.BUFFER_DISPLAYED
  self:register_autocmd_event(event, function(bufnr, file)
    self:on_buffer_displayed(bufnr, file)
  end)
end

---@async
---@private
---@param bufnr integer
---@param file string
function BuffersPanel:on_buffer_displayed(bufnr, file)
  local buftype = api.nvim_buf_get_option(bufnr, "buftype")
  if buftype == "terminal" then
    self.root:set_terminal_hidden(file, bufnr, false)
    self:draw()
  end
end

---@private
function BuffersPanel:register_buffer_deleted_event()
  local event = require("ya-tree.events.event").autocmd.BUFFER_DELETED
  self:register_autocmd_event(event, function(bufnr, file)
    self:on_buffer_deleted(bufnr, file)
  end)
end

---@async
---@private
---@param bufnr integer
---@param file string
function BuffersPanel:on_buffer_deleted(bufnr, file)
  local buftype = api.nvim_buf_get_option(bufnr, "buftype")
  if buftype == "" or buftype == "terminal" then
    if not Path.is_absolute_path(file) then
      file = Path:new(file):absolute()
    end
    log.debug("removing buffer %q from buffer tree", file)
    local updated = self.root:remove_node(file, bufnr, buftype == "terminal")
    local cwd = uv.cwd() --[[@as string]]
    if #self.root:children() <= 1 and self.root.path ~= cwd then
      self.root:refresh({ root_path = cwd })
      updated = true
    end
    if updated then
      self:draw(self:get_current_node())
    end
  end
end

---@protected
---@return string complete_func
---@return string search_root
function BuffersPanel:get_complete_func_and_search_root()
  return "buffer", self.root.path
end

return BuffersPanel
