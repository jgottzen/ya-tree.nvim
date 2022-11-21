local lib = require("ya-tree.lib")
local utils = require("ya-tree.utils")

local M = {}

---@async
---@param tree Yat.Tree
---@param node Yat.Node
---@param context Yat.Action.FnContext
function M.check_node_for_git(tree, node, context)
  if not node.repo or node.repo:is_yadm() then
    local repo = lib.rescan_node_for_git(tree, node)
    if repo then
      context.sidebar:update()
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
---@param context Yat.Action.FnContext
function M.stage(_, node, context)
  if node.repo then
    local err = node.repo:add(node.path)
    if err then
      utils.warn("Error staging path '" .. node.path .. "': " .. err)
    else
      context.sidebar:update()
    end
  end
end

---@async
---@param _ Yat.Tree
---@param node Yat.Node
---@param context Yat.Action.FnContext
function M.unstage(_, node, context)
  if node.repo then
    local err = node.repo:restore(node.path, true)
    if err then
      utils.warn("Error unstaging path '" .. node.path .. "': " .. err)
    else
      context.sidebar:update()
    end
  end
end

---@async
---@param _ Yat.Tree
---@param node Yat.Node
---@param context Yat.Action.FnContext
function M.revert(_, node, context)
  if node.repo then
    local err = node.repo:restore(node.path, false)
    if err then
      utils.warn("Error reverting path '" .. node.path .. "': " .. err)
    else
      context.sidebar:update()
    end
  end
end

return M
