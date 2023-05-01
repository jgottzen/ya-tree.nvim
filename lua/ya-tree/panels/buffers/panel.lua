local lazy = require("ya-tree.lazy")

local BufferNode = lazy.require("ya-tree.nodes.buffer_node") ---@module "ya-tree.nodes.buffer_node"
local Config = lazy.require("ya-tree.config") ---@module "ya-tree.config"
local event = lazy.require("ya-tree.events.event") ---@module "ya-tree.events.event"
local fs = lazy.require("ya-tree.fs") ---@module "ya-tree.fs"
local git = lazy.require("ya-tree.git") ---@module "ya-tree.git"
local Logger = lazy.require("ya-tree.log") ---@module "ya-tree.log"
local Path = lazy.require("ya-tree.path") ---@module "ya-tree.path"
local TreePanel = require("ya-tree.panels.tree_panel")

local api = vim.api
local uv = vim.loop

---@class Yat.Panel.Buffers : Yat.Panel.Tree
---@field new async fun(self: Yat.Panel.Buffers, sidebar: Yat.Sidebar, config: Yat.Config.Panels.Buffers, keymap: table<string, Yat.Action>, renderers: { directory: Yat.Panel.Tree.Ui.Renderer[], file: Yat.Panel.Tree.Ui.Renderer[] }): Yat.Panel.Buffers
---
---@field public TYPE "buffers"
---@field public root Yat.Node.Buffer
---@field public current_node Yat.Node.Buffer
local BuffersPanel = TreePanel:subclass("Yat.Panel.Buffers")

---@async
---@private
---@param sidebar Yat.Sidebar
---@param config Yat.Config.Panels.Buffers
---@param keymap table<string, Yat.Action>
---@param renderers { directory: Yat.Panel.Tree.Ui.Renderer[], file: Yat.Panel.Tree.Ui.Renderer[] }
function BuffersPanel:init(sidebar, config, keymap, renderers)
  local path = uv.cwd() --[[@as string]]
  local fs_node = fs.node_for(path) --[[@as Yat.Fs.Node]]
  local root = BufferNode:new(fs_node)
  root.repo = git.get_repo_for_path(fs_node.path)
  local panel_renderers = { container = renderers.directory, leaf = renderers.file }
  TreePanel.init(self, "buffers", sidebar, config.title, config.icon, keymap, panel_renderers, root)
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

  Logger.get("panels").info("created panel %s", tostring(self))
end

---@param repo Yat.Git.Repo
---@param path string
function BuffersPanel:set_git_repo_for_path(repo, path)
  local node = self.root:get_node(path) or self.root:get_node(repo.toplevel)
  if node then
    Logger.get("panels").debug("setting git repo for panel %s on node %s", self.TYPE, node.path)
    node:set_git_repo(repo)
    self:draw()
  end
end

---@return Yat.Git.Repo[]
function BuffersPanel:get_git_repos()
  ---@type table<Yat.Git.Repo, boolean>
  local found_toplevels = {}
  self.root:walk(function(node)
    if node.repo then
      if not found_toplevels[node.repo] then
        found_toplevels[node.repo] = true
      end
      if not node.repo:is_yadm() then
        return true
      end
    end
  end)
  return vim.tbl_keys(found_toplevels)
end

---@private
function BuffersPanel:register_buffer_new_event()
  self:register_autocmd_event(event.autocmd.BUFFER_NEW, function(bufnr, file)
    self:on_buffer_new(bufnr, file)
  end)
end

---@async
---@private
---@param bufnr integer
---@param file string
function BuffersPanel:on_buffer_new(bufnr, file)
  local log = Logger.get("panels")
  local buftype = api.nvim_buf_get_option(bufnr, "buftype")
  local is_terminal = buftype == "terminal"
  if (buftype == "" and fs.is_file(file)) or is_terminal then
    local  node = self.root:get_node(file)
    if not node then
      log.debug("adding buffer %q with bufnr %s to buffers tree", file, bufnr)
      node = self.root:add_node(file, bufnr, is_terminal)
    elseif node.bufnr ~= bufnr then
      log.debug("buffer %q changed bufnr from %s to %s", file, node.bufnr, bufnr)
      node.bufnr = bufnr
    end

    if not Config.config.follow_focused_file then
      node = self:get_current_node() --[[@as Yat.Node.Buffer?]]
    end
    self:draw(node)
  end
end

---@private
function BuffersPanel:register_buffer_hidden_event()
  self:register_autocmd_event(event.autocmd.BUFFER_HIDDEN, function(bufnr, file)
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
  self:register_autocmd_event(event.autocmd.BUFFER_DISPLAYED, function(bufnr, file)
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
  self:register_autocmd_event(event.autocmd.BUFFER_DELETED, function(bufnr, file)
    self:on_buffer_deleted(bufnr, file)
  end)
end

---@async
---@private
---@param bufnr integer
---@param file string
function BuffersPanel:on_buffer_deleted(bufnr, file)
  local buftype = api.nvim_buf_get_option(bufnr, "buftype")
  local is_fs_buffer = buftype == ""
  local is_terminal = buftype == "terminal"
  if is_fs_buffer and fs.is_file(file) or is_terminal then
    if is_fs_buffer and not Path.is_absolute_path(file) then
      file = Path:new(file):absolute()
    end
    Logger.get("panels").debug("removing buffer %q from buffer tree", file)
    if self.root:remove_node(file, bufnr, is_terminal) then
      self:draw(self:get_current_node())
    end
  end
end

---@protected
function BuffersPanel:on_win_opened()
  if Config.config.move_cursor_to_name then
    self:create_move_to_name_autocmd()
  end
  if Config.config.follow_focused_file then
    self:expand_to_current_buffer()
  end
end

---@protected
---@return string complete_func
---@return string search_root
function BuffersPanel:get_complete_func_and_search_root()
  return "buffer", self.root.path
end

return BuffersPanel
