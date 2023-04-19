local scheduler = require("ya-tree.async").scheduler
local utils = require("ya-tree.utils")

local M = {}

---@async
---@param panel Yat.Panel
function M.close_panel(panel)
  panel.sidebar:close_panel(panel)
end

---@async
---@param panel Yat.Panel
---@param node? Yat.Node
function M.open_symbols_panel(panel, node)
  if panel.TYPE ~= "symbols" then
    panel.sidebar:symbols_panel(true, node and node.path)
  end
end

---@async
---@param panel Yat.Panel
function M.open_call_hierarchy_panel(panel)
  if panel.TYPE ~= "call_hierarchy" then
    panel.sidebar:call_hierarchy(true)
  end
end

---@async
---@param panel Yat.Panel
---@param node? Yat.Node
function M.open_git_status_panel(panel, node)
  if not require("ya-tree.config").config.git.enable then
    utils.notify("Git is not enabled.")
    return
  end

  if panel.TYPE ~= "git_status" then
    local TreePanel = require("ya-tree.panels.tree_panel")
    if panel:instance_of(TreePanel) then
      ---@cast panel Yat.Panel.Tree
      if not node then
        node = panel.root
      end
      local repo ---@type Yat.Git.Repo?
      local FsBasedNode = require("ya-tree.nodes.fs_based_node")
      if node:instance_of(FsBasedNode) then
        repo = node--[[@as Yat.Node.FsBasedNode]].repo
      end
      if not repo or repo:is_yadm() then
        repo = require("ya-tree.git").create_repo(node.path)
      end
      if repo then
        panel.sidebar:set_git_repo_for_path(node.path, repo)
        panel.sidebar:git_status_panel(true, repo)
      else
        utils.notify(string.format("No Git repository found in %q.", node.path))
      end
    else
      panel.sidebar:git_status_panel(true)
    end
  end
end

---@async
---@param panel Yat.Panel
function M.open_buffers_panel(panel)
  if panel.TYPE ~= "buffers" then
    panel.sidebar:buffers_panel(true)
  end
end

---@async
---@param panel Yat.Panel
---@param node Yat.Node.FsBasedNode
function M.goto_node_in_files_panel(panel, node)
  local files_panel = panel.sidebar:files_panel(true)
  if files_panel then
    files_panel:close_search(false)
    local target_node = files_panel.root:expand({ to = node.path })
    scheduler()
    files_panel:draw(target_node)
  end
end

---@async
---@param panel Yat.Panel
function M.refresh_panel(panel)
  panel:refresh()
end

return M
