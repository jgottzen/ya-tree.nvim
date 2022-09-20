local scheduler = require("plenary.async.util").scheduler

local FsTree = require("ya-tree.trees.filesystem")
local BuffersTree = require("ya-tree.trees.buffers")
local GitTree = require("ya-tree.trees.git")
local SearchTree = require("ya-tree.trees.search")
local git = require("ya-tree.git")
local ui = require("ya-tree.ui")
local log = require("ya-tree.log")

local api = vim.api

---@alias YaTreeTabpageTreesMap  { [string|YaTreeType|"current"]: YaTree }

local M = {
  ---@private
  ---@type table<YaTreeType|string, YaTree>
  _registered_trees = {},
  ---@private
  ---@type table<integer, YaTreeTabpageTreesMap>
  _tabpage_trees = {},
}

---@param tree YaTree
function M.register_tree(tree)
  M._registered_trees[tree.TYPE] = tree
end

function M.delete_trees_after_tab_closed()
  ---@type table<string, boolean>
  local found_toplevels = {}
  local tabpages = api.nvim_list_tabpages()
  for tabpage, trees in pairs(M._tabpage_trees) do
    if not vim.tbl_contains(tabpages, tabpage) then
      for name, tree in pairs(trees) do
        if name ~= "current" then
          tree:delete(tabpage)
        end
        trees[name] = nil
      end
      log.debug("Deleted trees for tabpage %s", tabpage)
      M._tabpage_trees[tabpage] = nil
    else
      for name, tree in pairs(trees) do
        if name ~= "current" then
          tree.root:walk(function(node)
            if node.repo and not found_toplevels[node.repo.toplevel] then
              found_toplevels[node.repo.toplevel] = true
              if not node.repo:is_yadm() then
                return true
              end
            end
          end)
        end
      end
    end
  end

  for toplevel, repo in pairs(git.repos) do
    if not found_toplevels[toplevel] then
      git.remove_repo(repo)
    end
  end
end

---@param tabpage integer
---@param name YaTreeType|string
---@param set_current? boolean
---@return YaTree? tree
function M.get_tree(tabpage, name, set_current)
  local trees = M._tabpage_trees[tabpage]
  if trees then
    local tree = trees[name]
    if tree and set_current then
      trees.current = tree
    end
    return tree
  end
end

---@async
---@param tabpage integer
---@param name YaTreeType|string
---@param set_current boolean
---@param ... any tree arguments
---@return YaTree tree
function M.new_tree(tabpage, name, set_current, ...)
  local trees = M._tabpage_trees[tabpage]
  if not trees then
    trees = {}
    M._tabpage_trees[tabpage] = trees
  end
  if trees[name] then
    trees[name]:delete(tabpage)
    trees[name] = nil
  end
  local class = M._registered_trees[name]
  local tree = class:new(tabpage, ...)
  trees[name] = tree
  if set_current then
    trees.current = tree
  end
  return tree
end

---@param tabpage integer
---@return YaTree? tree
function M.current_tree(tabpage)
  local tree = M._tabpage_trees[tabpage]
  return tree and tree.current
end

---@param tabpage integer
---@param tree YaTree
function M.set_current_tree(tabpage, tree)
  local trees = M._tabpage_trees[tabpage]
  if not trees then
    trees = {}
    M._tabpage_trees[tabpage] = trees
  end
  trees.current = tree
end

---@param tabpage integer
---@param set_current? boolean
---@return YaFsTree? tree
function M.filesystem(tabpage, set_current)
  return M.get_tree(tabpage, "files", set_current) --[[@as YaFsTree?]]
end

---@async
---@param tabpage integer
---@param set_current boolean
---@param root? string|YaTreeNode
---@return YaFsTree tree
function M.new_filesystem(tabpage, set_current, root)
  return M.new_tree(tabpage, "files", set_current or false, root) --[[@as YaFsTree]]
end

---@async
---@param tabpage integer
---@param set_current boolean
---@param root? string|YaTreeNode
---@return YaFsTree tree
function M.filesystem_or_new(tabpage, set_current, root)
  local tree = M.filesystem(tabpage, set_current)
  if not tree then
    tree = M.new_filesystem(tabpage, set_current, root)
  end
  return tree
end

---@param tabpage integer
---@param set_current? boolean
---@return YaBuffersTree? tree
function M.buffers(tabpage, set_current)
  return M.get_tree(tabpage, "buffers", set_current) --[[@as YaBuffersTree?]]
end

---@async
---@param tabpage integer
---@param set_current boolean
---@param path string
---@return YaBuffersTree tree
function M.new_buffers(tabpage, set_current, path)
  return M.new_tree(tabpage, "buffers", set_current or false, path) --[[@as YaBuffersTree]]
end

---@param tabpage integer
---@param set_current? boolean
---@return YaGitTree? tree
function M.git(tabpage, set_current)
  return M.get_tree(tabpage, "git", set_current) --[[@as YaGitTree?]]
end

---@async
---@param tabpage integer
---@param set_current boolean
---@param repo GitRepo
---@return YaGitTree tree
function M.new_git(tabpage, set_current, repo)
  return M.new_tree(tabpage, "git", set_current or false, repo) --[[@as YaGitTree]]
end

---@param tabpage integer
---@param set_current? boolean
---@return YaSearchTree? tree
function M.search(tabpage, set_current)
  return M.get_tree(tabpage, "search", set_current) --[[@as YaSearchTree?]]
end

---@async
---@param tabpage integer
---@param set_current boolean
---@param path string
---@return YaSearchTree
function M.new_search(tabpage, set_current, path)
  return M.new_tree(tabpage, "search", set_current or false, path) --[[@as YaSearchTree]]
end

---@async
---@param scope "window"|"tabpage"|"global"|"auto"
---@param new_cwd string
local function on_cwd_changed(scope, new_cwd)
  log.debug("scope=%s, cwd=%s", scope, new_cwd)

  local current_tabpage = api.nvim_get_current_tabpage() --[[@as integer]]
  local tree = M.filesystem(current_tabpage)
  if (scope == "tabpage" or scope == "global") and tree then
    if new_cwd == tree.cwd then
      log.debug("the tabpage's new cwd %q is the same as the current tree's %s", new_cwd, tostring(tree))
    else
      local node = ui.is_open() and ui.get_current_node() or tree.current_node
      -- since DirChanged is only subscribed to if config.cwd.follow is enabled, the tree.cwd is always bound to the tab cwd,
      -- and the root path of the tree doesn't have to be checked
      tree.cwd = new_cwd
      tree:change_root_node(new_cwd)
      scheduler()
      if ui.is_open() then
        ui.update(tree, node)
      end
    end
  end
  if scope == "global" then
    for _, tabpage in ipairs(api.nvim_list_tabpages()) do
      if tabpage ~= current_tabpage then
        tree = M.filesystem(tabpage)
        if tree and tree.cwd ~= new_cwd then
          -- since DirChanged is only subscribed to if config.cwd.follow is enabled, the tree.cwd is always bound to the tab cwd,
          -- and the root path of the tree doesn't have to be checked
          tree.cwd = new_cwd
          tree:change_root_node(new_cwd)
        end
      end
    end
  end
end

function M.setup()
  local events = require("ya-tree.events")
  local event = require("ya-tree.events.event").autocmd

  events.on_autocmd_event(event.TAB_CLOSED, "YA_TREE_TREES_TAB_CLOSE_CLEANUP", M.delete_trees_after_tab_closed)
  if require("ya-tree.config").config.cwd.follow then
    events.on_autocmd_event(event.CWD_CHANGED, "YA_TREE_TREES_CWD_CHANGED", true, function(_, new_cwd, scope)
      -- currently not available in the table passed to the callback
      if vim.v.event.changed_window then
        -- if the autocmd was fired because of a switch to a tab or window with a different
        -- cwd than the previous tab/window, it can safely be ignored.
        return
      end
      on_cwd_changed(scope, new_cwd)
    end)
  end
end

do
  M.register_tree(FsTree)
  M.register_tree(BuffersTree)
  M.register_tree(GitTree)
  M.register_tree(SearchTree)
end

return M