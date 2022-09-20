local scheduler = require("plenary.async.util").scheduler

local events = require("ya-tree.events")
local fs = require("ya-tree.filesystem")
local git = require("ya-tree.git")
local BufferNode = require("ya-tree.nodes.buffer_node")
local Tree = require("ya-tree.trees.tree")
local ui = require("ya-tree.ui")
local log = require("ya-tree.log")
local utils = require("ya-tree.utils")

local api = vim.api
local uv = vim.loop

---@class Yat.Trees.Buffers : Yat.Tree
---@field TYPE "buffers"
---@field private _tabpage integer[]
---@field root Yat.Nodes.Buffer
---@field current_node? Yat.Nodes.Buffer
local BuffersTree = { TYPE = "buffers" }
BuffersTree.__index = BuffersTree

---@param self Yat.Trees.Buffers
---@param other Yat.Tree
---@return boolean
BuffersTree.__eq = function(self, other)
  return self.TYPE == other.TYPE
end

BuffersTree.__tostring = Tree.__tostring
setmetatable(BuffersTree, { __index = Tree })

---@type Yat.Trees.Buffers?
local singleton = nil

---@async
---@param tabpage integer
---@param path string
---@return Yat.Trees.Buffers tree
function BuffersTree:new(tabpage, path)
  if not singleton then
    singleton = Tree.new(self, tabpage)
    local fs_node = fs.node_for(path) --[[@as Yat.Fs.Node]]
    singleton._tabpage = { tabpage }
    singleton.root = BufferNode:new(fs_node)
    singleton.root.repo = git.get_repo_for_path(fs_node.path)
    singleton.current_node = singleton.root:refresh()

    local event = require("ya-tree.events.event").autocmd
    events.on_autocmd_event(event.BUFFER_NEW, singleton:create_event_id(event.BUFFER_NEW), true, function(bufnr, file)
      if file ~= "" then
        -- The autocmds are fired before buftypes are set or in the case of BufFilePost before the file is available on the file system,
        -- causing the node creation to fail, by deferring the call for a short time, we should be able to find the file
        vim.defer_fn(function()
          singleton:on_buffer_new(bufnr, file)
        end, 100)
      end
    end)
    events.on_autocmd_event(event.BUFFER_HIDDEN, singleton:create_event_id(event.BUFFER_HIDDEN), function(bufnr, file)
      if file ~= "" then
        singleton:on_buffer_hidden(bufnr, file)
      end
    end)
    events.on_autocmd_event(event.BUFFER_DISPLAYED, singleton:create_event_id(event.BUFFER_DISPLAYED), function(bufnr, file)
      if file ~= "" then
        singleton:on_buffer_displayed(bufnr, file)
      end
    end)
    events.on_autocmd_event(event.BUFFER_DELETED, singleton:create_event_id(event.BUFFER_DELETED), true, function(bufnr, _, match)
      if match ~= "" then
        singleton:on_buffer_deleted(bufnr, match)
      end
    end)

    log.debug("created new tree %s", tostring(singleton))
  else
    log.debug("a buffers tree already exists, reusing it")
    if not vim.tbl_contains(singleton._tabpage, tabpage) then
      singleton._tabpage[#singleton._tabpage + 1] = tabpage
    end
  end
  return singleton
end

---@param tabpage integer
function BuffersTree:delete(tabpage)
  for index, value in ipairs(self._tabpage) do
    if value == tabpage then
      table.remove(self._tabpage, index)
    end
  end
end

---@param event integer
---@return string id
function BuffersTree:create_event_id(event)
  return string.format("YA_TREE_%s_TREE_%s", self.TYPE:upper(), events.get_event_name(event))
end

---@async
---@param bufnr integer
---@param file string
function BuffersTree:on_buffer_new(bufnr, file)
  local tabpage = api.nvim_get_current_tabpage()
  local buftype = api.nvim_buf_get_option(bufnr, "buftype")
  if (buftype == "" or buftype == "terminal") and not utils.is_directory_sync(file) then
    local node
    if buftype == "terminal" then
      node = self.root:add_buffer(file, bufnr, true)
    else
      node = self.root:get_child_if_loaded(file)
      if not node then
        if self.root:is_ancestor_of(file) then
          log.debug("adding buffer %q with bufnr %s to buffers tree", file, bufnr)
          node = self.root:add_buffer(file, bufnr, false)
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

    scheduler()
    if self:is_shown_in_ui(tabpage) then
      if require("ya-tree.config").config.follow_focused_file and not node then
        node = self.root:expand({ to = file })
      else
        node = ui.get_current_node()
      end
      ui.update(self, node, { focus_node = true })
    end
  end
end

---@param bufnr integer
---@param file string
function BuffersTree:on_buffer_hidden(bufnr, file)
  -- BufHidden might be triggered after TermClose, when the buffer no longer exists,
  -- so calling nvim_buf_get_option results in an error.
  local ok, buftype = pcall(api.nvim_buf_get_option, bufnr, "buftype")
  if ok and buftype == "terminal" then
    self.root:set_terminal_hidden(file, bufnr, true)
    if self:is_shown_in_ui(api.nvim_get_current_tabpage()) then
      ui.update(self)
    end
  end
end

---@param bufnr integer
---@param file string
function BuffersTree:on_buffer_displayed(bufnr, file)
  local buftype = api.nvim_buf_get_option(bufnr, "buftype")
  if buftype == "terminal" then
    self.root:set_terminal_hidden(file, bufnr, false)
    if self:is_shown_in_ui(api.nvim_get_current_tabpage()) then
      ui.update(self)
    end
  end
end

---@async
---@param bufnr integer
---@param file string
function BuffersTree:on_buffer_deleted(bufnr, file)
  local buftype = api.nvim_buf_get_option(bufnr, "buftype")
  if buftype == "" or buftype == "terminal" then
    log.debug("removing buffer %q from buffer tree", file)
    self.root:remove_buffer(file, bufnr, buftype == "terminal")
    if #self.root.children == 0 and self.root.path ~= uv.cwd() then
      self.root:refresh({ root_path = uv.cwd() })
    end
    if self:is_shown_in_ui(api.nvim_get_current_tabpage()) then
      ui.update(self, ui.get_current_node())
    end
  end
end

---@param tabpage integer
---@return true
function BuffersTree:is_for_tabpage(tabpage)
  return vim.tbl_contains(self._tabpage, tabpage)
end

return BuffersTree
