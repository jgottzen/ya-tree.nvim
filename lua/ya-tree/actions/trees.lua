local lib = require("ya-tree.lib")
local log = require("ya-tree.log").get("actions")
local utils = require("ya-tree.utils")

local M = {}

---@async
---@param tree Yat.Tree
---@param _ Yat.Node
---@param sidebar Yat.Sidebar
function M.close_tree(tree, _, sidebar)
  local new_tree = sidebar:close_tree(tree)
  if new_tree then
    sidebar:update(new_tree, new_tree.current_node)
  end
end

---@async
---@param tree Yat.Tree
---@param _ Yat.Node
---@param sidebar Yat.Sidebar
function M.delete_tree(tree, _, sidebar)
  local new_tree = sidebar:close_tree(tree, true)
  if new_tree then
    sidebar:update(new_tree, new_tree.current_node)
  end
end

---@async
---@param tree Yat.Tree
---@param _ Yat.Node
---@param sidebar Yat.Sidebar
function M.focus_prev_tree(tree, _, sidebar)
  local prev_tree = sidebar:get_prev_tree(tree)
  if prev_tree then
    sidebar:focus_node(prev_tree, prev_tree.root)
  end
end

---@async
---@param tree Yat.Tree
---@param _ Yat.Node
---@param sidebar Yat.Sidebar
function M.focus_next_tree(tree, _, sidebar)
  local next_tree = sidebar:get_next_tree(tree)
  if next_tree then
    sidebar:focus_node(next_tree, next_tree.root)
  end
end

---@async
---@param tree Yat.Tree
---@param node Yat.Node
---@param sidebar Yat.Sidebar
function M.open_symbols_tree(tree, node, sidebar)
  if tree.TYPE ~= "symbols" then
    tree = sidebar:symbols_tree(node.path)
    sidebar:update(tree, tree.current_node)
  end
end

---@async
---@param tree Yat.Tree
---@param node? Yat.Node
---@param sidebar Yat.Sidebar
function M.open_git_tree(tree, node, sidebar)
  node = node or tree.root
  local repo = node.repo
  if not repo or repo:is_yadm() then
    repo = lib.rescan_node_for_git(tree, node)
  end
  if repo then
    local git_tree = sidebar:git_tree(repo)
    sidebar:update(git_tree, git_tree.current_node)
  else
    utils.notify(string.format("No Git repository found in %q.", node.path))
  end
end

---@async
---@param sidebar Yat.Sidebar
function M.open_buffers_tree(_, _, sidebar)
  local tree = sidebar:buffers_tree()
  sidebar:update(tree, tree.current_node)
end

---@async
---@param tree Yat.Tree
---@param node Yat.Node
---@param sidebar Yat.Sidebar
function M.refresh_tree(tree, node, sidebar)
  if tree.refreshing or vim.v.exiting ~= vim.NIL then
    log.debug("refresh already in progress or vim is exiting, aborting refresh")
    return
  end
  tree.refreshing = true
  log.debug("refreshing current tree")

  tree.root:refresh({ recurse = true, refresh_git = true })
  sidebar:update(tree, node, { focus_node = true })
  tree.refreshing = false
end

return M
