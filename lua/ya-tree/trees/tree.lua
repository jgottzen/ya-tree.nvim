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
---@param tabpage? integer
---@param ...? any
---@return T tree
---@diagnostic disable-next-line:unused-vararg
function Tree.new(self, tabpage, ...)
  ---@class YaTree
  local this = {
    _tabpage = tabpage or 1,
    refreshing = false,
  }
  setmetatable(this, self)

  local event = require("ya-tree.events.event")
  local buffer_modified_id = this:create_event_id(event.BUFFER_MODIFIED)
  events.on_autocmd_event(event.BUFFER_MODIFIED, buffer_modified_id, false, function(bufnr, file)
    this:on_buffer_modified(bufnr, file)
  end)
  if require("ya-tree.config").config.auto_reload_on_write then
    events.on_autocmd_event(event.BUFFER_SAVED, this:create_event_id(event.BUFFER_SAVED), true, function(bufnr, file)
      this:on_buffer_saved(bufnr, file)
    end)
  end

  return this
end

-- selene: allow(unused_variable)

---@param tabpage integer
function Tree:delete(tabpage) end

---@param event_id YaTreeEvent
---@return string id
function Tree:create_event_id(event_id)
  local event = require("ya-tree.events.event")
  return string.format("YA_TREE_%s_TREE%s_%s", self.TYPE, self._tabpage, event[event_id])
end

---@param bufnr integer
---@param file string
function Tree:on_buffer_modified(bufnr, file)
  if self.root then
    if file ~= "" and api.nvim_buf_get_option(bufnr, "buftype") == "" then
      ---@type boolean
      local modified = api.nvim_buf_get_option(bufnr, "modified")
      local node = self.root:get_child_if_loaded(file)
      if node and node.modified ~= modified then
        node.modified = modified

        local tabpage = api.nvim_get_current_tabpage()
        if self:is_for_tabpage(tabpage) and ui.is_open(self.TYPE) and ui.is_node_rendered(node) then
          ui.update(self)
        end
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
  if self.root then
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
      local tabpage = api.nvim_get_current_tabpage()
      if self:is_for_tabpage(tabpage) and ui.is_open(self.TYPE) then
        ui.update(self)
      end
    end
  end
end

---@param ... any
function Tree:change_root_node(...) end

---@param tabpage integer
---@return boolean
function Tree:is_for_tabpage(tabpage)
  return self._tabpage == tabpage
end

return Tree
