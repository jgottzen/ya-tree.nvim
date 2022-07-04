local scheduler = require("plenary.async.util").scheduler
local Path = require("plenary.path")

local Nodes = require("ya-tree.nodes")
local git = require("ya-tree.git")
local log = require("ya-tree.log")

local api = vim.api
local uv = vim.loop

---@class YaTree
---@field public tabpage number the current tabpage.
---@field public cwd string the workding directory of the tabpage.
---@field public refreshing boolean if the tree is currently refreshing.
---@field public git_watchers table<GitRepo, string> the registered git watchers.
---@field public root YaTreeNode|YaTreeSearchRootNode|YaTreeBufferNode|YaTreeGitStatusNode the root of the current tree.
---@field public current_node? YaTreeNode the currently selected node.
---@field public tree YaTreeRoot the current tree.
---@field public search YaSearchTreeRoot the current search tree.
---@field public buffers YaBufferTreeRoot the buffers tree info.
---@field public git_status YaGitStatusTreeRoot the git status info.

---@class YaTreeRoot
---@field public root YaTreeNode the root fo the tree.
---@field public current_node? YaTreeNode the currently selected node.

---@class YaSearchTreeRoot
---@field public root? YaTreeSearchRootNode the root of the search tree.
---@field public current_node? YaTreeSearchNode the currently selected node.

---@class YaBufferTreeRoot
---@field public root? YaTreeBufferNode
---@field public current_node? YaTreeBufferNode

---@class YaGitStatusTreeRoot
---@field public root? YaTreeGitStatusNode
---@field public current_node? YaTreeGitStatusNode

local M = {
  ---@private
  ---@type table<string, YaTree>
  _trees = {},
}

---@param tree YaTree
---@return string
local function tree_tostring(tree)
  return string.format("(tabpage=%s, cwd=%q, root=%q)", tree.tabpage, tree.cwd, tree.root.path)
end

---@async
---@param tabpage? number
---@return YaTree tree
function M.get_tree(tabpage)
  scheduler()
  ---@type number
  tabpage = tabpage or api.nvim_get_current_tabpage()
  return M._trees[tostring(tabpage)]
end

---@param tabindex number
---@return number? tabpage
function M.tabindex_to_tabpage(tabindex)
  ---@type number[]
  local tabs = {}
  for tab, _ in pairs(M._trees) do
    tabs[#tabs + 1] = tonumber(tab)
  end
  table.sort(tabs, function(a, b)
    return a < b
  end)
  log.debug(tabs)
  return tabs[tabindex]
end

---@async
---@param root_path? string
---@return YaTree tree
function M.get_or_create_tree(root_path)
  scheduler()
  ---@type number
  local tabpage = api.nvim_get_current_tabpage()
  local tree = M._trees[tostring(tabpage)] --[[@as YaTree?]]

  if tree and (root_path and root_path ~= tree.root.path) then
    log.debug(
      "tree %s for tabpage %s exists, but with a different cwd than requested %q, deleting tree",
      tostring(tree),
      tabpage,
      root_path
    )
    M.delete_tree(tabpage)
    tree = nil
  end

  if not tree then
    ---@type string
    local cwd = uv.cwd()
    local root = root_path or cwd
    log.debug("creating new tree data for tabpage %s with cwd %q and root %q", tabpage, cwd, root)
    local root_node = Nodes.root(root, nil, require("ya-tree.config").config.git.enable)
    ---@type YaTree
    tree = setmetatable({
      tabpage = tabpage,
      cwd = cwd,
      refreshing = false,
      git_watchers = {},
      root = root_node,
      current_node = nil,
      tree = {
        root = root_node,
        current_node = nil,
      },
      search = {
        root = nil,
        current_node = nil,
      },
      buffers = {
        root = nil,
        current_node = nil,
      },
      git_status = {
        root = nil,
        current_node = nil,
      },
    }, { __tostring = tree_tostring })
    M._trees[tostring(tabpage)] = tree

    local repo = root_node.repo
    if repo then
      M.attach_git_watcher(tree, repo)
    end
  end

  return tree
end

---@param tree YaTree
---@param repo GitRepo
function M.attach_git_watcher(tree, repo)
  local config = require("ya-tree.config").config
  if config.git.watch_git_dir and not tree.git_watchers[repo] then
    local lib = require("ya-tree.lib")
    local watcher_id = repo:add_git_watcher(lib.on_git_change)
    tree.git_watchers[repo] = watcher_id
    log.debug("attached git watcher for tree %s to git repo %s with id %s", tree.tabpage, repo.toplevel, watcher_id)
  end
end

---@async
---@param tree YaTree
---@param new_root string|YaTreeNode
---@return YaTree tree
function M.update_tree_root_node(tree, new_root)
  if type(new_root) == "string" then
    log.debug("new root is string %q", new_root)

    tree.refreshing = true
    if tree.tree.root.path ~= new_root then
      ---@type YaTreeNode?
      local root
      if tree.tree.root:is_ancestor_of(new_root) then
        log.debug("current tree %s is ancestor of new root %q, expanding to it", tostring(tree), new_root)
        -- the new root is located 'below' the current root,
        -- if it's already loaded in the tree, use that node as the root, else expand to it
        local node = tree.tree.root:get_child_if_loaded(new_root)
        if node then
          root = node
          root:expand({ force_scan = true })
        else
          root = tree.tree.root:expand({ force_scan = true, to = new_root })
        end
      elseif tree.tree.root.path:find(Path:new(new_root):absolute(), 1, true) then
        log.debug("current tree %s is a child of new root %q, creating parents up to it", tostring(tree), new_root)
        -- the new root is located 'above' the current root,
        -- walk upwards from the current root's parent and see if it's already loaded, if so, us it
        root = tree.tree.root
        while root.parent do
          root = root.parent --[[@as YaTreeNode]]
          root:refresh()
          if root.path == new_root then
            break
          end
        end

        while root.path ~= new_root do
          root = Nodes.root(Path:new(root.path):parent().filename, root, false)
        end
      else
        log.debug("current tree %s is not a child or ancestor of %q", tostring(tree), new_root)
      end

      if not root then
        log.debug("creating new root for %q", new_root)
        tree = M.get_or_create_tree(new_root)
      else
        tree.root = root
        tree.tree.root = root
        tree.tree.current_node = tree.current_node
      end
    else
      log.debug("the new root %q is the same as the current root %s, skipping", new_root, tostring(tree.root))
    end
  else
    ---@cast new_root YaTreeNode
    if tree.tree.root.path ~= new_root.path then
      log.debug("new root is node %q", tostring(new_root))
      tree.root = new_root
      tree.root:expand({ force_scan = true })
      tree.tree.root = new_root
      tree.tree.current_node = tree.current_node
    else
      log.debug("the new root %q is the same as the current root %s, skipping", tostring(new_root), tostring(tree.root))
    end
  end

  tree.refreshing = false
  return tree
end

---@param cb fun(tree: YaTree)
function M.for_each_tree(cb)
  for _, tree in pairs(M._trees) do
    cb(tree)
  end
end

---@param tabpage number
function M.delete_tree(tabpage)
  local tab = tostring(tabpage)
  local tree = M._trees[tab]
  if tree then
    for repo, watcher_id in pairs(tree.git_watchers) do
      repo:remove_git_watcher(watcher_id)
      tree.git_watchers[repo] = nil
      if not repo:has_git_watcher() then
        git.remove_repo(repo)
      end
    end
    M._trees[tab] = nil
  end
end

return M
