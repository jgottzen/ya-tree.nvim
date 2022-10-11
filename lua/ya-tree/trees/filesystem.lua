local scheduler = require("plenary.async.util").scheduler
local Path = require("plenary.path")

local fs = require("ya-tree.filesystem")
local Node = require("ya-tree.nodes.node")
local Tree = require("ya-tree.trees.tree")
local ui = require("ya-tree.ui")
local utils = require("ya-tree.utils")
local log = require("ya-tree.log")("trees")

local api = vim.api
local uv = vim.loop

---@class Yat.Trees.Filesystem : Yat.Tree
---@field TYPE "filesystem"
---@field persistent true
---@field supported_actions Yat.Trees.Filesystem.SupportedActions[]
---@field complete_func fun(self: Yat.Trees.Filesystem, bufnr: integer, node?: Yat.Node)
local FilesystemTree = { TYPE = "filesystem" }
FilesystemTree.__index = FilesystemTree
FilesystemTree.__eq = Tree.__eq
FilesystemTree.__tostring = Tree.__tostring
setmetatable(FilesystemTree, { __index = Tree })

---@alias Yat.Trees.Filesystem.SupportedActions
---| "add"
---| "rename"
---| "delete"
---| "trash"
---
---| "copy_node"
---| "cut_node"
---| "paste_nodes"
---| "clear_clipboard"
---
---| "cd_to"
---| "cd_up"
---
---| "toggle_ignored"
---| "toggle_filter"
---
---| "search_for_node_in_tree"
---| "search_interactively"
---| "search_once"
---
---| "check_node_for_git"
---| "focus_prev_git_item"
---| "focus_prev_git_item"
---
---| "focus_prev_diagnostic_item"
---| "focus_next_diagnostic_item"
---
---| Yat.Trees.Tree.SupportedActions

do
  local builtin = require("ya-tree.actions.builtin")

  FilesystemTree.supported_actions = utils.tbl_unique({
    builtin.files.add,
    builtin.files.rename,
    builtin.files.delete,
    builtin.files.trash,

    builtin.files.copy_node,
    builtin.files.cut_node,
    builtin.files.paste_nodes,
    builtin.files.clear_clipboard,

    builtin.files.cd_to,
    builtin.files.cd_up,

    builtin.files.toggle_ignored,
    builtin.files.toggle_filter,

    builtin.search.search_for_node_in_tree,
    builtin.search.search_interactively,
    builtin.search.search_once,

    builtin.git.check_node_for_git,
    builtin.git.focus_prev_git_item,
    builtin.git.focus_next_git_item,

    builtin.diagnostics.focus_prev_diagnostic_item,
    builtin.diagnostics.focus_next_diagnostic_item,

    unpack(Tree.supported_actions),
  })
end

---@param config Yat.Config
function FilesystemTree.setup(config)
  local completion = config.trees.filesystem.completion
  if type(completion.setup) == "function" then
    function FilesystemTree:complete_func(bufnr, node)
      local completefunc = completion.setup(self, node)
      if completefunc then
        api.nvim_buf_set_option(bufnr, "completefunc", completefunc)
        api.nvim_buf_set_option(bufnr, "omnifunc", "")
      end
    end
  else
    if completion.on == "node" then
      FilesystemTree.complete_func = Tree.complete_func_file_in_path
    else
      if completion.on ~= "root" then
        utils.warn(string.format("'trees.filesystem.completion.on' is not a recognized value (%q), using 'root'", completion.on))
      end
      function FilesystemTree:complete_func(bufnr)
        return self:complete_func_file_in_path(bufnr)
      end
    end
  end
end

---Creates a new filesystem node tree root.
---@async
---@param path string the path
---@param old_root? Yat.Node the previous root
---@return Yat.Node root
local function create_root_node(path, old_root)
  local fs_node = fs.node_for(path) --[[@as Yat.Fs.Node]]
  local root = Node:new(fs_node)

  -- if the tree root was moved on level up, i.e the new root is the parent of the old root, add it to the tree
  if old_root and Path:new(old_root.path):parent().filename == root.path then
    root._children = { old_root }
    old_root.parent = root
    local repo = old_root.repo
    if repo and root.path:find(repo.toplevel, 1, true) then
      root.repo = repo
    end
  end

  -- force scan of the directory
  root:expand({ force_scan = true })

  return root
end

---@async
---@param tabpage integer
---@param root? string|Yat.Node
---@return Yat.Trees.Filesystem tree
function FilesystemTree:new(tabpage, root)
  local root_node
  if type(root) == "string" then
    if not fs.is_directory(root) then
      root = Path:new(root):parent():absolute() --[[@as string]]
    end
    root_node = create_root_node(root)
  elseif type(root) == "table" then
    root_node = root --[[@as Yat.Node]]
  else
    root_node = create_root_node(uv.cwd())
  end

  local this = Tree.new(self, tabpage, root_node.path)
  this:enable_events(true)
  this.persistent = true

  this.root = root_node
  this.current_node = this.root
  this:check_node_for_repo(this.root)

  log.debug("created new tree %s", tostring(this))
  return this
end

---@async
---@param repo Yat.Git.Repo
---@param fs_changes boolean
function FilesystemTree:on_git_event(repo, fs_changes)
  if vim.v.exiting ~= vim.NIL or not (self.root:is_ancestor_of(repo.toplevel) or repo.toplevel:find(self.root.path, 1, true) ~= nil) then
    return
  end
  log.debug("git repo %s changed", tostring(repo))

  if fs_changes then
    log.debug("git listener called with fs_changes=true, refreshing tree")
    local node = self.root:get_child_if_loaded(repo.toplevel)
    if node then
      log.debug("repo %s is loaded in node %q", tostring(repo), node.path)
      node:refresh({ recurse = true })
    elseif self.root.path:find(repo.toplevel, 1, true) ~= nil then
      log.debug("tree root %q is a subdirectory of repo %s", self.root.path, tostring(repo))
      self.root:refresh({ recurse = true })
    end
  end
  scheduler()
  if self:is_shown_in_ui(api.nvim_get_current_tabpage()) then
    -- get the current node to keep the cursor on it
    ui.update(self, ui.get_current_node())
  end
end

---@async
---@param new_cwd string
function FilesystemTree:on_cwd_changed(new_cwd)
  if new_cwd ~= self.root.path then
    local tabpage = api.nvim_get_current_tabpage()
    self:change_root_node(new_cwd)

    scheduler()
    if self:is_shown_in_ui(tabpage) then
      ui.update(self, ui.get_current_node())
    end
  end
end

---@async
---@param tree Yat.Trees.Filesystem
---@param new_root string
---@return boolean `false` if the current tree cannot walk up or down to reach the specified directory.
local function update_tree_root_node(tree, new_root)
  if tree.root.path ~= new_root then
    local root
    if tree.root:is_ancestor_of(new_root) then
      log.debug("current tree %s is ancestor of new root %q, expanding to it", tostring(tree), new_root)
      -- the new root is located 'below' the current root,
      -- if it's already loaded in the tree, use that node as the root, else expand to it
      root = tree.root:get_child_if_loaded(new_root)
      if root then
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
        root = root.parent --[[@as Yat.Node]]
        root:refresh()
        if root.path == new_root then
          break
        end
      end

      while root.path ~= new_root do
        root = create_root_node(Path:new(root.path):parent().filename, root)
      end
    else
      log.debug("current tree %s is not a child or ancestor of %q", tostring(tree), new_root)
    end

    if not root then
      log.debug("cannot walk the tree to find a node for %q, returning nil", new_root)
      return false
    else
      tree.root = root
    end
  else
    log.debug("the new root %q is the same as the current root %s, skipping", new_root, tostring(tree.root))
  end
  return true
end

---@async
---@param new_root string|Yat.Node
function FilesystemTree:change_root_node(new_root)
  local old_root = self.root
  if type(new_root) == "string" then
    if not fs.is_directory(new_root) then
      new_root = Path:new(new_root):parent():absolute() --[[@as string]]
    end
    if new_root == self.root.path then
      return
    end
    log.debug("setting new tree root to %q", new_root)
    if not update_tree_root_node(self, new_root) then
      self.root = create_root_node(new_root, self.root)
    end
  else
    ---@cast new_root Yat.Node
    if new_root == self.root then
      return
    end
    log.debug("setting new tree root to %s", tostring(new_root))
    self.root = new_root
    self.root:expand({ force_scan = true })

    local tree_root = new_root
    while tree_root.parent do
      tree_root = tree_root.parent --[[@as Yat.Node]]
    end
    ---@type table<string, boolean>
    local found_toplevels = {}
    tree_root:walk(function(node)
      if node.repo and not found_toplevels[node.repo.toplevel] then
        found_toplevels[node.repo.toplevel] = true
        if not node.repo:is_yadm() then
          return true
        end
      end
    end)
  end

  if not self.root.repo then
    self:check_node_for_repo(self.root)
  end
  log.debug("updated tree to %s, old root was %s", tostring(self), tostring(old_root))
end

return FilesystemTree
