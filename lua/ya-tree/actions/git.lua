local utils = require("ya-tree.utils")

local M = {}

---@async
---@param panel Yat.Panel.Tree
---@param node Yat.Node
function M.check_node_for_git(panel, node)
  if not require("ya-tree.config").config.git.enable then
    utils.notify("Git is not enabled.")
    return
  end

  if not node.repo or node.repo:is_yadm() then
    local repo = panel:check_node_for_git_repo(node)
    if repo then
      panel.sidebar:set_git_repo_for_path(node.path, repo)
    else
      utils.notify(string.format("No Git repository found in %q.", node.path))
    end
  elseif node.repo and not node.repo:is_yadm() then
    utils.notify(string.format("%q is already detected as a Git repository.", node.path))
  end
end

---@async
---@param _ Yat.Panel.Tree
---@param node Yat.Node
function M.stage(_, node)
  if node.repo then
    local err = node.repo:index():add(node.path)
    -- the git watcher will trigger updating the panel
    if err then
      utils.warn("Error staging path '" .. node.path .. "': " .. err)
    end
  end
end

---@async
---@param _ Yat.Panel.Tree
---@param node Yat.Node
function M.unstage(_, node)
  if node.repo then
    local err = node.repo:index():restore(node.path, true)
    -- the git watcher will trigger updating the panel
    if err then
      utils.warn("Error unstaging path '" .. node.path .. "': " .. err)
    end
  end
end

---@async
---@param _ Yat.Panel.Tree
---@param node Yat.Node
function M.revert(_, node)
  if node.repo then
    local err = node.repo:index():restore(node.path, false)
    -- the git watcher will trigger updating the panel
    if err then
      utils.warn("Error reverting path '" .. node.path .. "': " .. err)
    end
  end
end

return M
