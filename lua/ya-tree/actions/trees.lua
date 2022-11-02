local lib = require("ya-tree.lib")
local ui = require("ya-tree.ui")
local utils = require("ya-tree.utils")
local log = require("ya-tree.log")("actions")

local M = {}

---@async
---@param tree Yat.Tree
---@param _ Yat.Node
---@param context Yat.Action.FnContext
function M.close_tree(tree, _, context)
  local new_tree = context.sidebar:close_tree(tree)
  if new_tree then
    ui.update(new_tree, new_tree.current_node)
  end
end

---@async
---@param tree Yat.Tree
---@param _ Yat.Node
---@param context Yat.Action.FnContext
function M.delete_tree(tree, _, context)
  local new_tree = context.sidebar:close_tree(tree, true)
  if new_tree then
    ui.update(new_tree, new_tree.current_node)
  end
end

---@async
---@param tree Yat.Tree
---@param node? Yat.Node
---@param context Yat.Action.FnContext
function M.open_git_tree(tree, node, context)
  node = node or tree.root
  local repo = node.repo
  if not repo or repo:is_yadm() then
    repo = lib.rescan_node_for_git(tree, node)
  end
  if repo then
    local git_tree = context.sidebar:git_tree(repo)
    ui.update(git_tree, git_tree.current_node)
  else
    utils.notify(string.format("No Git repository found in %q.", node.path))
  end
end

---@async
---@param context Yat.Action.FnContext
function M.open_buffers_tree(_, _, context)
  local tree = context.sidebar:buffers_tree()
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
