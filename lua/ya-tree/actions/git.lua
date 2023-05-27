local lazy = require("ya-tree.lazy")

local Config = lazy.require("ya-tree.config") ---@module "ya-tree.config"
local git = lazy.require("ya-tree.git") ---@module "ya-tree.git"
local Logger = lazy.require("ya-tree.log") ---@module "ya-tree.log"
local ui = lazy.require("ya-tree.ui") ---@module "ya-tree.ui"
local utils = lazy.require("ya-tree.utils") ---@module "ya-tree.utils"

local M = {}

---@async
---@param panel Yat.Panel
function M.toggle_ignored(panel)
  local config = Config.config
  config.git.show_ignored = not config.git.show_ignored
  Logger.get("actions").debug("toggling git ignored to %s", config.git.show_ignored)
  panel.sidebar:draw()
end

---@async
---@param panel Yat.Panel.Tree
---@param node Yat.Node.FsBasedNode
function M.check_node_for_git(panel, node)
  if not Config.config.git.enable then
    utils.notify("Git is not enabled.")
    return
  end

  if not node:is_directory() then
    node = node.parent --[[@as Yat.Node.FsBasedNode]]
  end
  if not node.repo or node.repo:is_yadm() then
    local repo = git.create_repo(node.path)
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
---@param panel Yat.Panel.GitStatus
function M.open_repository(panel)
  local path = ui.nui_input({ title = "Repo", default = panel.root.path, completion = "dir", width = 30 })
  if path then
    panel:change_root_node(path)
  end
end

---@async
---@param _ Yat.Panel.Tree
---@param node Yat.Node.FsBasedNode
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
---@param node Yat.Node.FsBasedNode
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
---@param node Yat.Node.FsBasedNode
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
