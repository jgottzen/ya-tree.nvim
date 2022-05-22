local Path = require("plenary.path")

local Nodes = require("ya-tree.nodes")
local log = require("ya-tree.log")

local api = vim.api
local uv = vim.loop

---@class YaTree
---@field public cwd string the workding directory of the tabpage.
---@field public refreshing boolean if the tree is currently refreshing.
---@field public root YaTreeNode|YaTreeSearchNode the root of the current tree.
---@field public current_node? YaTreeNode the currently selected node.
---@field public tree YaTreeRoot the current tree.
---@field public search SearchTree the current search tree.
---@field public tabpage number the current tabpage.
---@field public git_watchers table<GitRepo, string> the registered git watchers.

---@class YaTreeRoot
---@field public root YaTreeNode the root fo the tree.
---@field public current_node? YaTreeNode the currently selected node.

---@class SearchTree
---@field public result? YaTreeSearchNode the root of the search tree.
---@field public current_node? YaTreeNode the currently selected node.

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

---@param tabpage? number
---@return YaTree tree
function M.get_tree(tabpage)
  ---@type number
  tabpage = tabpage or api.nvim_get_current_tabpage()
  return M._trees[tostring(tabpage)]
end

---@param opts? {tabpage?: number, root_path?: string}
---  - {opts.tabpage?} `number`
---  - {opts.root_path?} `string`
---@return YaTree tree
function M.get_or_create_tree(opts)
  opts = opts or {}
  ---@type number
  local tabpage = opts.tabpage or api.nvim_get_current_tabpage()
  local tree = M._trees[tostring(tabpage)]

  if tree and (opts.root_path and opts.root_path ~= tree.root.path) then
    log.debug(
      "tree %s for tabpage %s exists, but with a different cwd than requested %q, deleting tree",
      tostring(tree),
      tabpage,
      opts.root_path
    )
    M.delete_tree(tabpage)
    tree = nil
  end

  if not tree then
    ---@type string
    local cwd = uv.cwd()
    local root = opts.root_path or cwd
    log.debug("creating new tree data for tabpage %s with cwd %q and root %q", tabpage, cwd, root)
    local root_node = Nodes.root(root, nil, require("ya-tree.config").config.git.enable)
    tree = setmetatable({
      cwd = cwd,
      refreshing = false,
      root = root_node,
      current_node = nil,
      tree = {
        root = root_node,
        current_node = nil,
      },
      search = {
        result = nil,
        current_node = nil,
      },
      tabpage = tabpage,
      git_watchers = {},
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

---@param tree YaTree
---@param new_root string|YaTreeNode
---@return YaTree tree
function M.update_tree_root_node(tree, new_root)
  if type(new_root) == "string" then
    log.debug("new root is string %q", new_root)

    if tree.root.path ~= new_root then
      ---@type YaTreeNode
      local root
      if tree.root:is_ancestor_of(new_root) then
        log.debug("current tree %s is ancestor of new root %q, expanding to it", tostring(tree), new_root)
        -- the new root is located 'below' the current root,
        -- if it's already loaded in the tree, use that node as the root, else expand to it
        local node = tree.root:get_child_if_loaded(new_root)
        if node then
          root = node
          root:expand({ force_scan = true })
        else
          root = tree.root:expand({ force_scan = true, to = new_root })
        end
      elseif tree.root.path:find(Path:new(new_root):absolute(), 1, true) then
        log.debug("current tree %s is a child of new root %q, creating parents up to it", tostring(tree), new_root)
        -- the new root is located 'above' the current root,
        -- walk upwards from the current root's parent and see if it's already loaded, if so, us it
        root = tree.root
        while root.parent do
          root = root.parent
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
        tree = M.get_or_create_tree({ root_path = new_root })
      else
        tree.root = root
        tree.tree.root = root
        tree.tree.current_node = tree.current_node
      end
    else
      log.debug("the new root %q is the same as the current root %s, skipping", new_root, tostring(tree.root))
    end
  else
    if tree.root.path ~= new_root.path then
      log.debug("new root is node %q", tostring(new_root))
      ---@type YaTreeNode
      tree.root = new_root
      tree.root:expand({ force_scan = true })
      tree.tree.root = tree.root
      tree.tree.current_node = tree.current_node
    else
      log.debug("the new root %q is the same as the current root %s, skipping", tostring(new_root), tostring(tree.root))
    end
  end

  return tree
end

---@param cb fun(tree: YaTree): nil
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
    end
    M._trees[tab] = nil
  end
end

return M
