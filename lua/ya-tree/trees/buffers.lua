local fs = require("ya-tree.fs")
local git = require("ya-tree.git")
local BufferNode = require("ya-tree.nodes.buffer_node")
local Tree = require("ya-tree.trees.tree")
local tree_utils = require("ya-tree.trees.utils")
local utils = require("ya-tree.utils")
local log = require("ya-tree.log")("trees")

local api = vim.api
local uv = vim.loop

---@class Yat.Trees.Buffers : Yat.Tree
---@field TYPE "buffers"
---@field root Yat.Nodes.Buffer
---@field current_node Yat.Nodes.Buffer
---@field supported_actions Yat.Trees.Buffers.SupportedActions
---@field supported_events { autcmd: Yat.Events.AutocmdEvent[], git: Yat.Events.GitEvent[], yatree: Yat.Events.YaTreeEvent[] }
---@field complete_func "buffer"
local BuffersTree = { TYPE = "buffers" }
BuffersTree.__index = BuffersTree
BuffersTree.__eq = Tree.__eq
BuffersTree.__tostring = Tree.__tostring
setmetatable(BuffersTree, { __index = Tree })

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
---| "focus_prev_git_item"
---
---| "focus_prev_diagnostic_item"
---| "focus_next_diagnostic_item"
---
---| Yat.Trees.Tree.SupportedActions

---@param config Yat.Config
function BuffersTree.setup(config)
  BuffersTree.complete_func = "buffer"
  BuffersTree.renderers = tree_utils.create_renderers(BuffersTree.TYPE, config)

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

    builtin.diagnostics.focus_prev_diagnostic_item,
    builtin.diagnostics.focus_next_diagnostic_item,

    unpack(vim.deepcopy(Tree.supported_actions)),
  })

  local ae = require("ya-tree.events.event").autocmd
  local ge = require("ya-tree.events.event").git
  local ye = require("ya-tree.events.event").ya_tree
  BuffersTree.supported_events = {
    autcmd = { ae.BUFFER_MODIFIED, ae.BUFFER_NEW, ae.BUFFER_HIDDEN, ae.BUFFER_DISPLAYED, ae.BUFFER_DELETED },
    git = {},
    yatree = {},
  }
  if config.update_on_buffer_saved then
    table.insert(BuffersTree.supported_events.autcmd, ae.BUFFER_SAVED)
  end
  if config.git.enable then
    table.insert(BuffersTree.supported_events.git, ge.DOT_GIT_DIR_CHANGED)
  end
  if config.diagnostics.enable then
    table.insert(BuffersTree.supported_events.yatree, ye.DIAGNOSTICS_CHANGED)
  end
end

---@async
---@param tabpage integer
---@param path? string
---@return Yat.Trees.Buffers tree
function BuffersTree:new(tabpage, path)
  path = path or uv.cwd() --[[@as string]]
  local this = Tree.new(self, tabpage, path)
  local fs_node = fs.node_for(path) --[[@as Yat.Fs.Node]]
  this.root = BufferNode:new(fs_node)
  this.root.repo = git.get_repo_for_path(fs_node.path)
  this.current_node = this.root:refresh()

  log.info("created new tree %s", tostring(this))
  return this
end

---@async
---@param bufnr integer
---@param file string
---@return boolean
function BuffersTree:on_buffer_new(bufnr, file)
  local tabpage = api.nvim_get_current_tabpage()
  local buftype = api.nvim_buf_get_option(bufnr, "buftype")
  -- use sync directory check to avoid having to call scheduler() in BufferNode
  if (buftype == "" or buftype == "terminal") and not utils.is_directory_sync(file) then
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

    return self:is_shown_in_ui(tabpage)
  end
  return false
end

---@param bufnr integer
---@param file string
---@return boolean
function BuffersTree:on_buffer_hidden(bufnr, file)
  -- BufHidden might be triggered after TermClose, when the buffer no longer exists,
  -- so calling nvim_buf_get_option results in an error.
  local ok, buftype = pcall(api.nvim_buf_get_option, bufnr, "buftype")
  if ok and buftype == "terminal" then
    self.root:set_terminal_hidden(file, bufnr, true)
    return self:is_shown_in_ui(api.nvim_get_current_tabpage())
  end
  return false
end

---@param bufnr integer
---@param file string
---@return boolean
function BuffersTree:on_buffer_displayed(bufnr, file)
  local buftype = api.nvim_buf_get_option(bufnr, "buftype")
  if buftype == "terminal" then
    self.root:set_terminal_hidden(file, bufnr, false)
    return self:is_shown_in_ui(api.nvim_get_current_tabpage())
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
    local tabpage = api.nvim_get_current_tabpage()
    log.debug("removing buffer %q from buffer tree", file)
    self.root:remove_node(file, bufnr, buftype == "terminal")
    if #self.root:children() <= 1 and self.root.path ~= uv.cwd() then
      self.root:refresh({ root_path = uv.cwd() })
    end
    return self:is_shown_in_ui(tabpage)
  end
  return false
end

return BuffersTree
