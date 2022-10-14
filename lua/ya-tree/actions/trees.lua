local lib = require("ya-tree.lib")
local Trees = require("ya-tree.trees")
local ui = require("ya-tree.ui")
local utils = require("ya-tree.utils")
local log = require("ya-tree.log")("actions")

local api = vim.api

local M = {}

---@async
function M.close_tree()
  local tabpage = api.nvim_get_current_tabpage() --[[@as integer]]
  local tree = Trees.filesystem(tabpage, true)
  ui.update(tree, tree.current_node)
end

---@async
---@param tree Yat.Tree
function M.delete_tree(tree)
  local tabpage = api.nvim_get_current_tabpage() --[[@as integer]]
  Trees.delete_tree(tabpage, tree)
  local fs_tree = Trees.filesystem(tabpage, true)
  ui.update(fs_tree, fs_tree.current_node)
end

---@async
---@param tree Yat.Tree
---@param node Yat.Node
function M.open_git_tree(tree, node)
  local tabpage = api.nvim_get_current_tabpage()
  local repo = node.repo
  if not repo or repo:is_yadm() then
    repo = lib.rescan_node_for_git(tree, node)
  end
  if repo then
    tree = Trees.git(tabpage, repo)
    ui.update(tree, tree.current_node)
  else
    utils.notify(string.format("No Git repository found in %q.", node.path))
  end
end

---@async
function M.open_buffers_tree()
  local tabpage = api.nvim_get_current_tabpage()
  local tree = Trees.buffers(tabpage)
  ui.update(tree, tree.current_node)
end

---@async
---@param tree Yat.Tree
---@param node Yat.Node
function M.refresh_tree(tree, node)
  if tree.refreshing or vim.v.exiting ~= vim.NIL then
    log.debug("refresh already in progress or vim is exiting, aborting refresh")
    return
  end
  tree.refreshing = true
  log.debug("refreshing current tree")

  tree.root:refresh({ recurse = true, refresh_git = require("ya-tree.config").config.git.enable })
  ui.update(tree, node, { focus_node = true })
  tree.refreshing = false
end

return M
