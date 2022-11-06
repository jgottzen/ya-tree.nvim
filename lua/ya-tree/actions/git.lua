local lib = require("ya-tree.lib")
local ui = require("ya-tree.ui")
local utils = require("ya-tree.utils")

local M = {}

---@async
---@param tree Yat.Tree
---@param node Yat.Node
---@return Yat.Git.Repo? repo
function M.check_node_for_git(tree, node)
  if not node.repo or node.repo:is_yadm() then
    local repo = lib.rescan_node_for_git(tree, node)
    if repo then
      ui.update(tree, node)
    else
      utils.notify(string.format("No Git repository found in %q.", node.path))
    end
  elseif node.repo and not node.repo:is_yadm() then
    utils.notify(string.format("%q is already detected as a Git repository.", node.path))
  end
end

---@async
---@param _ Yat.Tree
---@param node Yat.Node
function M.stage(_, node)
  if node.repo then
    node.repo:add(node.path)
    ui.update()
  end
end

---@async
---@param _ Yat.Tree
---@param node Yat.Node
function M.unstage(_, node)
  if node.repo then
    node.repo:restore(node.path, true)
    ui.update()
  end
end

---@async
---@param _ Yat.Tree
---@param node Yat.Node
function M.revert(_, node)
  if node.repo then
    node.repo:restore(node.path, false)
    ui.update()
  end
end

return M
