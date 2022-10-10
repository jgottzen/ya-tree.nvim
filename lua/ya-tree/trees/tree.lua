local scheduler = require("plenary.async.util").scheduler
local Path = require("plenary.path")

local events = require("ya-tree.events")
local git = require("ya-tree.git")
local ui = require("ya-tree.ui")
local utils = require("ya-tree.utils")
local log = require("ya-tree.log")("trees")

local api = vim.api

---@alias Yat.Trees.Type "filesystem" | "buffers" | "git" | "search" | string

---@class Yat.Tree
---@field TYPE Yat.Trees.Type
---@field private _tabpage integer
---@field private _registered_events { autcmd: Yat.Events.AutocmdEvent[], git: Yat.Events.GitEvent[], yatree: Yat.Events.YaTreeEvent[] }
---@field persistent boolean
---@field refreshing boolean
---@field root Yat.Node
---@field current_node Yat.Node
---@field supported_actions Yat.Trees.Tree.SupportedActions[]
---@field complete_func string | fun(self: Yat.Tree, bufnr: integer, node: Yat.Node) | false
local Tree = {}
Tree.__index = Tree

---@alias Yat.Trees.Tree.SupportedActions
---| "close_window"
---| "system_open"
---| "open_help"
---| "show_node_info"
---| "close_tree"
---
---| "open_git_tree"
---| "open_buffers_tree"
---
---| "open"
---| "vsplit"
---| "split"
---| "tabnew"
---| "preview"
---| "preview_and_focus"
---
---| "copy_name_to_clipboard"
---| "copy_root_relative_path_to_clipboard"
---| "copy_absolute_path_to_clipboard"
---
---| "close_node"
---| "close_all_nodes"
---| "close_all_child_nodes"
---| "expand_all_nodes"
---| "expand_all_child_nodes"
---
---| "refresh_tree"
---
---| "focus_parent"
---| "focus_prev_sibling"
---| "focus_next_sibling"
---| "focus_first_sibling"
---| "focus_last_sibling"

do
  local builtin = require("ya-tree.actions.builtin")

  Tree.supported_actions = utils.tbl_unique({
    builtin.general.close_window,
    builtin.general.system_open,
    builtin.general.open_help,
    builtin.general.show_node_info,
    builtin.general.close_tree,

    builtin.general.open_git_tree,
    builtin.general.open_buffers_tree,

    builtin.general.open,
    builtin.general.vsplit,
    builtin.general.split,
    builtin.general.tabnew,
    builtin.general.preview,
    builtin.general.preview_and_focus,

    builtin.general.copy_name_to_clipboard,
    builtin.general.copy_root_relative_path_to_clipboard,
    builtin.general.copy_absolute_path_to_clipboard,

    builtin.general.close_node,
    builtin.general.close_all_nodes,
    builtin.general.close_all_child_nodes,
    builtin.general.expand_all_nodes,
    builtin.general.expand_all_child_nodes,

    builtin.general.refresh_tree,

    builtin.general.focus_parent,
    builtin.general.focus_prev_sibling,
    builtin.general.focus_next_sibling,
    builtin.general.focus_first_sibling,
    builtin.general.focus_last_sibling,
  })
end

---@param self Yat.Tree
---@param other Yat.Tree
---@return boolean equal
Tree.__eq = function(self, other)
  return self.TYPE == other.TYPE and self._tabpage == other._tabpage
end

---@param self Yat.Tree
---@return string
Tree.__tostring = function(self)
  return string.format("(%s, tabpage=%s, root=%s)", self.TYPE, vim.inspect(self._tabpage), tostring(self.root))
end

-- selene: allow(unused_variable)

---@param config Yat.Config
function Tree.setup(config) end

---@generic T : Yat.Tree
---@param self T
---@param tabpage integer
---@param enabled_events boolean | { buf_modified?: boolean, buf_saved?: boolean, dot_git_dir_changed?: boolean, diagnostics?: boolean }
---@return T tree
function Tree.new(self, tabpage, enabled_events)
  if enabled_events == true then
    enabled_events = { buf_modified = true, buf_saved = true, dot_git_dir_changed = true, diagnostics = true }
  end
  if not enabled_events then
    enabled_events = {}
  end
  ---@type Yat.Tree
  local this = {
    _tabpage = tabpage,
    _registered_events = { autcmd = {}, git = {}, yatree = {} },
    persistent = false,
    refreshing = false,
  }
  setmetatable(this, self)

  local config = require("ya-tree.config").config
  local ae = require("ya-tree.events.event").autocmd
  if enabled_events.buf_modified then
    this:register_autocmd_event(ae.BUFFER_MODIFIED, false, function(bufnr, file)
      this:on_buffer_modified(bufnr, file)
    end)
  end
  if enabled_events.buf_saved and config.update_on_buffer_saved then
    this:register_autocmd_event(ae.BUFFER_SAVED, true, function(bufnr, _, match)
      this:on_buffer_saved(bufnr, match)
    end)
  end
  if enabled_events.dot_git_dir_changed and config.git.enable then
    local ge = require("ya-tree.events.event").git
    this:register_git_event(ge.DOT_GIT_DIR_CHANGED, function(repo, fs_changes)
      this:on_git_event(repo, fs_changes)
    end)
  end
  if enabled_events.diagnostics and config.diagnostics.enable then
    local ye = require("ya-tree.events.event").ya_tree
    this:register_yatree_event(ye.DIAGNOSTICS_CHANGED, true, function(severity_changed)
      this:on_diagnostics_event(severity_changed)
    end)
  end

  return this
end

---@param event Yat.Events.AutocmdEvent
---@param async boolean
---@param callback fun(bufnr: integer, file: string, match: string)
function Tree:register_autocmd_event(event, async, callback)
  self._registered_events.autcmd[#self._registered_events.autcmd + 1] = event
  events.on_autocmd_event(event, self:create_event_id(event), async, callback)
end

---@param event Yat.Events.AutocmdEvent
function Tree:remove_autocmd_event(event)
  events.remove_autocmd_event(event, self:create_event_id(event))
end

---@param event Yat.Events.GitEvent
---@param callback fun(repo: Yat.Git.Repo, fs_changes: boolean)
function Tree:register_git_event(event, callback)
  self._registered_events.git[#self._registered_events.git + 1] = event
  events.on_git_event(event, self:create_event_id(event), callback)
end

---@param event Yat.Events.GitEvent
function Tree:remove_git_event(event)
  events.remove_git_event(event, self:create_event_id(event))
end

---@param event Yat.Events.YaTreeEvent
---@param async boolean
---@param callback fun(...)
function Tree:register_yatree_event(event, async, callback)
  self._registered_events.yatree[#self._registered_events.yatree + 1] = event
  events.on_yatree_event(event, self:create_event_id(event), async, callback)
end

---@param event Yat.Events.YaTreeEvent
function Tree:remove_yatree_event(event)
  events.remove_yatree_event(event, self:create_event_id(event))
end

do
  ---@type string[]
  local paths = {}

  -- selene: allow(global_usage)
  ---@param start number
  ---@param base string
  ---@return number|string[]
  _G._ya_tree_trees_tree_loaded_nodes_complete = function(start, base)
    if start == 1 then
      return 0
    end
    ---@param item string
    return vim.tbl_filter(function(item)
      return item:find(base, 1, true) ~= nil
    end, paths)
  end

  ---@param bufnr integer
  function Tree:complete_func_loaded_nodes(bufnr)
    local config = require("ya-tree.config").config
    paths = {}
    self.root:walk(function(node)
      if node:is_file() and not node:is_hidden(config) then
        paths[#paths + 1] = node.path:sub(#self.root.path + 2)
      end
    end)
    api.nvim_buf_set_option(bufnr, "completefunc", "v:lua._ya_tree_trees_tree_loaded_nodes_complete")
    api.nvim_buf_set_option(bufnr, "omnifunc", "")
  end
end

-- selene: allow(global_usage)
---@param start number
---@param base string
---@return number|string[]
_G._ya_tree_trees_tree_file_in_path_complete = function(start, base)
  if start == 1 then
    return 0
  end
  return vim.fn.getcompletion(base, "file_in_path")
end

---@param bufnr integer
---@param node? Yat.Node
function Tree:complete_func_file_in_path(bufnr, node)
  api.nvim_buf_set_option(bufnr, "completefunc", "v:lua._ya_tree_trees_tree_file_in_path_complete")
  api.nvim_buf_set_option(bufnr, "omnifunc", "")
  api.nvim_buf_set_option(bufnr, "path", (node and node.path or self.root.path) .. "/**")
end

function Tree:delete()
  log.info("deleting tree %q for tabpage %s", self.TYPE, self._tabpage)
  for _, event in ipairs(self._registered_events.autcmd) do
    self:remove_autocmd_event(event)
  end
  for _, event in ipairs(self._registered_events.git) do
    self:remove_git_event(event)
  end
  for _, event in ipairs(self._registered_events.yatree) do
    self:remove_yatree_event(event)
  end
end

---@param event integer
---@return string id
function Tree:create_event_id(event)
  return string.format("YA_TREE_%s_TREE%s_%s", self.TYPE:upper(), self._tabpage, events.get_event_name(event))
end

---@param bufnr integer
---@param file string
function Tree:on_buffer_modified(bufnr, file)
  if file ~= "" and api.nvim_buf_get_option(bufnr, "buftype") == "" then
    local modified = api.nvim_buf_get_option(bufnr, "modified") --[[@as boolean]]
    local node = self.root:get_child_if_loaded(file)
    if node and node.modified ~= modified then
      node.modified = modified

      if self:is_shown_in_ui(api.nvim_get_current_tabpage()) and ui.is_node_rendered(node) then
        ui.update(self)
      end
    end
  end
end

-- selene: allow(unused_variable)

---@async
---@param bufnr integer
---@param file string
---@diagnostic disable-next-line:unused-local
function Tree:on_buffer_saved(bufnr, file)
  if self.root:is_ancestor_of(file) then
    log.debug("changed file %q is in tree %s", file, tostring(self))
    local parent = self.root:get_child_if_loaded(Path:new(file):parent().filename)
    if parent then
      parent:refresh()
      local node = parent:get_child_if_loaded(file)
      if node then
        node.modified = false
      end

      if require("ya-tree.config").config.git.enable then
        if node and node.repo then
          node.repo:refresh_status_for_path(file)
        end
      end
    end

    scheduler()
    if self:is_shown_in_ui(api.nvim_get_current_tabpage()) then
      ui.update(self)
    end
  end
end

-- selene: allow(unused_variable)

---@async
---@param repo Yat.Git.Repo
---@param fs_changes boolean
---@diagnostic disable-next-line:unused-local
function Tree:on_git_event(repo, fs_changes)
  if
    vim.v.exiting == vim.NIL
    and (self.root:is_ancestor_of(repo.toplevel) or repo.toplevel:find(self.root.path, 1, true) ~= nil)
    and self:is_shown_in_ui(api.nvim_get_current_tabpage())
  then
    log.debug("git repo %s changed", tostring(repo))
    ui.update(self)
  end
end

---@async
---@param severity_changed boolean
function Tree:on_diagnostics_event(severity_changed)
  if severity_changed and self:is_shown_in_ui(api.nvim_get_current_tabpage()) then
    ui.update(self)
  end
end

-- selene: allow(unused_variable)

---@async
---@param new_cwd string
function Tree:on_cwd_changed(new_cwd) end

---@async
---@param node Yat.Node
---@return boolean
function Tree:check_node_for_repo(node)
  if require("ya-tree.config").config.git.enable then
    local repo = git.create_repo(node.path)
    if repo then
      node:set_git_repo(repo)
      repo:refresh_status({ ignored = true })
      return true
    end
  end
  return false
end

---@async
---@param ... any
function Tree:change_root_node(...) end

---@param tabpage integer
---@return boolean
function Tree:is_shown_in_ui(tabpage)
  return ui.is_open(self.TYPE) and self:is_for_tabpage(tabpage)
end

---@param tabpage integer
---@return boolean
function Tree:is_for_tabpage(tabpage)
  return self._tabpage == tabpage
end

return Tree
