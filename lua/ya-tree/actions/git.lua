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

return M
