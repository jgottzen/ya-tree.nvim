local fs = require("ya-tree.fs")
local git = require("ya-tree.git")
local BufferNode = require("ya-tree.nodes.buffer_node")
local meta = require("ya-tree.meta")
local Tree = require("ya-tree.trees.tree")
local tree_utils = require("ya-tree.trees.utils")
local utils = require("ya-tree.utils")
local log = require("ya-tree.log")("trees")

local api = vim.api
local uv = vim.loop

---@class Yat.Trees.Buffers : Yat.Tree
---@field new async fun(self: Yat.Trees.Buffers, tabpage: integer, path?: string): Yat.Trees.Buffers
---@overload async fun(tabpage: integer, path?: string): Yat.Trees.Buffers
---@field class fun(self: Yat.Trees.Buffers): Yat.Trees.Buffers
---@field super Yat.Tree
---@field static Yat.Trees.Buffers
---
---@field TYPE "buffers"
---@field root Yat.Nodes.Buffer
---@field current_node Yat.Nodes.Buffer
---@field supported_actions Yat.Trees.Buffers.SupportedActions[]
---@field supported_events { autocmd: Yat.Trees.AutocmdEventsLookupTable, git: Yat.Trees.GitEventsLookupTable, yatree: Yat.Trees.YaTreeEventsLookupTable }
---@field complete_func "buffer"
local BuffersTree = meta.create_class("Yat.Trees.Buffers", Tree)
BuffersTree.TYPE = "buffers"

---@alias Yat.Trees.Buffers.SupportedActions
---| "cd_to"
---| "toggle_ignored"
---| "toggle_filter"
---
---| "search_for_node_in_tree"
---
---| "goto_node_in_filesystem_tree"
---
---| "check_node_for_git"
---| "focus_prev_git_item"
---| "focus_next_git_item"
---| "git_stage"
---| "git_unstage"
---| "git_revert"
---
---| "focus_prev_diagnostic_item"
---| "focus_next_diagnostic_item"
---
---| Yat.Trees.Tree.SupportedActions

---@param config Yat.Config
function BuffersTree.setup(config)
  BuffersTree.complete_func = "buffer"
  BuffersTree.renderers = tree_utils.create_renderers(BuffersTree.static.TYPE, config)

  local builtin = require("ya-tree.actions.builtin")
  BuffersTree.supported_actions = utils.tbl_unique({
    builtin.files.cd_to,
    builtin.files.toggle_ignored,
    builtin.files.toggle_filter,

    builtin.search.search_for_node_in_tree,

    builtin.tree_specific.goto_node_in_filesystem_tree,

    builtin.git.check_node_for_git,
    builtin.git.focus_prev_git_item,
    builtin.git.focus_next_git_item,
    builtin.git.git_stage,
    builtin.git.git_unstage,
    builtin.git.git_revert,

    builtin.diagnostics.focus_prev_diagnostic_item,
    builtin.diagnostics.focus_next_diagnostic_item,

    unpack(vim.deepcopy(Tree.static.supported_actions)),
  })

  local ae = require("ya-tree.events.event").autocmd
  local ge = require("ya-tree.events.event").git
  local ye = require("ya-tree.events.event").ya_tree
  local supported_events = {
    autocmd = {
      [ae.BUFFER_SAVED] = Tree.static.on_buffer_saved,
      [ae.BUFFER_MODIFIED] = Tree.static.on_buffer_modified,
      [ae.BUFFER_NEW] = BuffersTree.static.on_buffer_new,
      [ae.BUFFER_HIDDEN] = BuffersTree.static.on_buffer_hidden,
      [ae.BUFFER_DISPLAYED] = BuffersTree.static.on_buffer_displayed,
      [ae.BUFFER_DELETED] = BuffersTree.static.on_buffer_deleted,
    },
    git = {},
    yatree = {},
  }
  if config.git.enable then
    supported_events.git[ge.DOT_GIT_DIR_CHANGED] = Tree.static.on_git_event
  end
  if config.diagnostics.enable then
    supported_events.yatree[ye.DIAGNOSTICS_CHANGED] = Tree.static.on_diagnostics_event
  end
  BuffersTree.supported_events = supported_events
end

---@async
---@private
---@param tabpage integer
---@param path? string
function BuffersTree:init(tabpage, path)
  path = path or uv.cwd() --[[@as string]]
  self.super:init(tabpage, path)
  local fs_node = fs.node_for(path) --[[@as Yat.Fs.Node]]
  self.root = BufferNode:new(fs_node)
  self.root.repo = git.get_repo_for_path(fs_node.path)
  self.current_node = self.root:refresh()

  log.info("created new tree %s", tostring(self))
end

---@async
---@param bufnr integer
---@param file string
---@return boolean
function BuffersTree:on_buffer_new(bufnr, file)
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
        return false
      end
    end

    return true
  end
  return false
end

---@async
---@param bufnr integer
---@param file string
---@return boolean
function BuffersTree:on_buffer_hidden(bufnr, file)
  -- BufHidden might be triggered after TermClose, when the buffer no longer exists,
  -- so calling nvim_buf_get_option results in an error.
  local ok, buftype = pcall(api.nvim_buf_get_option, bufnr, "buftype")
  if ok and buftype == "terminal" then
    return self.root:set_terminal_hidden(file, bufnr, true)
  end
  return false
end

---@async
---@param bufnr integer
---@param file string
---@return boolean
function BuffersTree:on_buffer_displayed(bufnr, file)
  local buftype = api.nvim_buf_get_option(bufnr, "buftype")
  if buftype == "terminal" then
    return self.root:set_terminal_hidden(file, bufnr, false)
  end
  return false
end

---@async
---@param bufnr integer
---@param file string
---@return boolean
function BuffersTree:on_buffer_deleted(bufnr, file)
  local buftype = api.nvim_buf_get_option(bufnr, "buftype")
  if buftype == "" or buftype == "terminal" then
    log.debug("removing buffer %q from buffer tree", file)
    local updated = self.root:remove_node(file, bufnr, buftype == "terminal")
    local cwd = uv.cwd() --[[@as string]]
    if #self.root:children() <= 1 and self.root.path ~= cwd then
      self.root:refresh({ root_path = cwd })
      updated = true
    end
    return updated
  end
  return false
end

return BuffersTree
