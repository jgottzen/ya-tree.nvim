local scheduler = require("plenary.async.util").scheduler
local Path = require("plenary.path")

local events = require("ya-tree.events")
local ui = require("ya-tree.ui")
local log = require("ya-tree.log")

local api = vim.api

---@alias YaTreeType "files" | "buffers" | "git" | "search"

---@class YaTree
---@field TYPE YaTreeType|string
---@field private _singleton boolean
---@field private _tabpage integer
---@field refreshing boolean
---@field root YaTreeNode
---@field current_node? YaTreeNode
local Tree = {}
Tree.__index = Tree

---@param self YaTree
---@param other YaTree
---@return boolean equal
Tree.__eq = function(self, other)
  return self.TYPE == other.TYPE and self._tabpage == other._tabpage
end

---@param self YaTree
---@return string
Tree.__tostring = function(self)
  return string.format("(%s, tabpage=%s, root=%s)", self.TYPE, vim.inspect(self._tabpage), tostring(self.root))
end

---@generic T : YaTree
---@param self T
---@param tabpage integer
---@return T tree
function Tree.new(self, tabpage)
  ---@type YaTree
  local this = {
    _tabpage = tabpage,
    refreshing = false,
  }
  setmetatable(this, self)

  local ae = require("ya-tree.events.event").autocmd
  events.on_autocmd_event(ae.BUFFER_MODIFIED, this:create_event_id(ae.BUFFER_MODIFIED), function(bufnr, file)
    this:on_buffer_modified(bufnr, file)
  end)
  if require("ya-tree.config").config.auto_reload_on_write then
    events.on_autocmd_event(ae.BUFFER_SAVED, this:create_event_id(ae.BUFFER_SAVED), true, function(bufnr, _, match)
      this:on_buffer_saved(bufnr, match)
    end)
  end
  if require("ya-tree.config").config.git.enable then
    local ge = require("ya-tree.events.event").git
    events.on_git_event(ge.DOT_GIT_DIR_CHANGED, this:create_event_id(ge.DOT_GIT_DIR_CHANGED), function(event_repo, fs_changes)
      this:on_git_event(event_repo, fs_changes)
    end)
  end

  return this
end

-- selene: allow(unused_variable)

---@param tabpage integer
---@diagnostic disable-next-line:unused-local
function Tree:delete(tabpage)
  local ae = require("ya-tree.events.event").autocmd
  events.remove_autocmd_event(ae.BUFFER_MODIFIED, self:create_event_id(ae.BUFFER_MODIFIED))
  events.remove_autocmd_event(ae.BUFFER_SAVED, self:create_event_id(ae.BUFFER_SAVED))
  local ge = require("ya-tree.events.event").git
  events.remove_git_event(ge.DOT_GIT_DIR_CHANGED, self:create_event_id(ge.DOT_GIT_DIR_CHANGED))
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
          node.repo:refresh_status_for_file(file)
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
---@param repo GitRepo
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