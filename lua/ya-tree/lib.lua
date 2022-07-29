local scheduler = require("plenary.async.util").scheduler
local void = require("plenary.async").void
local Path = require("plenary.path")

local config = require("ya-tree.config").config
local fs = require("ya-tree.filesystem")
local git = require("ya-tree.git")
local Nodes = require("ya-tree.nodes")
local job = require("ya-tree.job")
local ui = require("ya-tree.ui")
local utils = require("ya-tree.utils")
local log = require("ya-tree.log")

local api = vim.api
local fn = vim.fn
local uv = vim.loop

-- Flag for signaling when the library is setting up, which might take time if in a large directory and/or
-- repository. A call to M.open_window(), while setting up, will create another, duplicate, tree and doing the
-- filesystem and repository scanning again.
local setting_up = false

local M = {
  ---@private
  ---@type table<string, YaTree>
  _trees = {},
  ---@private
  ---@type table<GitRepo, number[]>
  _repo_tabpages = {},
  ---@private
  ---@type table<GitRepo, string>
  _repo_listeners = {},
}

---@class YaTree
---@field public tabpage number the current tabpage.
---@field public cwd string the workding directory of the tabpage.
---@field public refreshing boolean if the tree is currently refreshing.
---@field public root YaTreeNode|YaTreeSearchRootNode|YaTreeBufferNode|YaTreeGitStatusNode the root of the current tree.
---@field public current_node? YaTreeNode the currently selected node.
---@field public files YaFilesTreeRoot the current files tree.
---@field public search YaSearchTreeRoot the current search tree.
---@field public buffers YaBufferTreeRoot the buffers tree info.
---@field public git_status YaGitStatusTreeRoot the git status info.

---@class YaFilesTreeRoot
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

local Tree = {}

local add_git_change_listener
do
  ---@async
  ---@param repo GitRepo
  ---@param listener_id string
  ---@param fs_changes boolean
  local function on_git_change(repo, listener_id, fs_changes)
    if vim.v.exiting ~= vim.NIL or M._repo_listeners[repo] ~= listener_id then
      return
    end
    log.debug("git repo %s changed", tostring(repo))

    scheduler()
    ---@type number
    local tabpage = api.nvim_get_current_tabpage()
    local tabpages = M._repo_tabpages[repo]
    if tabpages then
      for _, tab in ipairs(tabpages) do
        local tree = Tree.get_tree(tab)
        if tree then
          if fs_changes then
            log.debug("git listener called with fs_changes=true, refreshing tree")
            if tree.git_status.root then
              tree.git_status.root:refresh({ refresh_git = false })
            end
            local node = tree.files.root:get_child_if_loaded(repo.toplevel)
            if node then
              log.debug("repo %s is loaded in node %q", tostring(repo), node.path)
              node:refresh({ recurse = true })
            elseif tree.files.root.path:find(repo.toplevel, 1, true) ~= nil then
              log.debug("tree root %q is a subdirectory of repo %s", tree.files.root.path, tostring(repo))
              tree.files.root:refresh({ recurse = true })
            end
          end
          scheduler()
          if tabpage == tree.tabpage and ui.is_open() then
            tree.current_node = ui.get_current_node()
            ui.update(tree.root, tree.current_node)
          end
        end
      end
    end
  end

  ---@param tabpage number
  ---@param repo GitRepo
  add_git_change_listener = function(tabpage, repo)
    if config.git.enable and config.git.watch_git_dir then
      local tabpages = M._repo_tabpages[repo]
      if not tabpages then
        if M._repo_listeners[repo] ~= nil then
          log.error("repo %s already has a listener_id %q registered", tostring(repo), M._repo_listeners[repo])
        end
        local listener_id = repo:add_git_change_listener(on_git_change)
        if listener_id then
          M._repo_tabpages[repo] = { tabpage }
          M._repo_listeners[repo] = listener_id
          log.debug("attached git listener for tree %s to git repo %s with id %s", tabpage, tostring(repo), listener_id)
        else
          log.error("failed to add git change listener for tree %s to git repo %s", tabpage, tostring(repo))
        end
      else
        tabpages[#tabpages + 1] = tabpage
        log.debug("added repo %s to tree %s", tostring(repo), tabpage)
      end
    end
  end
end

do
  ---@param tree YaTree
  ---@return string
  local function tree_tostring(tree)
    return string.format("(tabpage=%s, cwd=%q, root=%q)", tree.tabpage, tree.cwd, tree.root.path)
  end

  ---@private
  ---@param tabpage? number
  ---@return YaTree tree
  function Tree.get_tree(tabpage)
    ---@type number
    tabpage = tabpage or api.nvim_get_current_tabpage()
    return M._trees[tostring(tabpage)]
  end

  ---@async
  ---@param root_path string
  ---@param tabpage? number
  ---@return YaTree tree
  local function create_tree(root_path, tabpage)
    if not tabpage then
      scheduler()
      ---@type number
      tabpage = api.nvim_get_current_tabpage()
    end
    ---@type string
    local cwd = uv.cwd()
    local root = root_path
    log.debug("creating new tree data for tabpage %s with cwd %q and root %q", tabpage, cwd, root)
    local root_node = Nodes.root(root)
    ---@type YaTree
    local tree = setmetatable({
      tabpage = tabpage,
      cwd = cwd,
      refreshing = false,
      root = root_node,
      current_node = nil,
      files = {
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

    return tree
  end

  ---@async
  ---@param root_path? string
  ---@param tabpage? number
  ---@return YaTree tree
  function Tree.get_or_create_tree(root_path, tabpage)
    root_path = root_path or uv.cwd()
    if not fs.is_directory(root_path) then
      root_path = Path:new(root_path):parent():absolute() --[[@as string]]
    end
    log.debug("getting or creating tree for %q", root_path)
    scheduler()
    local tree = Tree.get_tree(tabpage)
    if tree then
      if tree.files.root.path == root_path then
        log.debug("current tree %s root is the same as the requested root %s", tostring(tree), root_path)
        return tree
      else
        log.debug("current tree %s doesn't have the requested root %q", tostring(tree), root_path)
        M._delete_tree(tree.tabpage)
      end
    end

    tree = create_tree(root_path, tabpage)
    if config.git.enable then
      local repo = git.create_repo(root_path)
      if repo then
        tree.files.root:set_git_repo(repo)
        repo:refresh_status({ ignored = true })
        add_git_change_listener(tree.tabpage, repo)
      end
    end
    return tree
  end

  ---@async
  ---@param tree YaTree
  ---@param new_root string
  ---@return YaTree|nil tree returns `nil` if the current tree cannot walk up or down to reach the specified directory.
  local function update_tree_root_node(tree, new_root)
    tree.refreshing = true
    if tree.files.root.path ~= new_root then
      local root
      if tree.files.root:is_ancestor_of(new_root) then
        log.debug("current tree %s is ancestor of new root %q, expanding to it", tostring(tree), new_root)
        -- the new root is located 'below' the current root,
        -- if it's already loaded in the tree, use that node as the root, else expand to it
        local node = tree.files.root:get_child_if_loaded(new_root)
        if node then
          root = node
          root:expand({ force_scan = true })
        else
          root = tree.files.root:expand({ force_scan = true, to = new_root })
        end
      elseif tree.files.root.path:find(Path:new(new_root):absolute(), 1, true) then
        log.debug("current tree %s is a child of new root %q, creating parents up to it", tostring(tree), new_root)
        -- the new root is located 'above' the current root,
        -- walk upwards from the current root's parent and see if it's already loaded, if so, us it
        root = tree.files.root
        while root.parent do
          root = root.parent --[[@as YaTreeNode]]
          root:refresh()
          if root.path == new_root then
            break
          end
        end

        while root.path ~= new_root do
          root = Nodes.root(Path:new(root.path):parent().filename, root)
        end
      else
        log.debug("current tree %s is not a child or ancestor of %q", tostring(tree), new_root)
      end

      if not root then
        log.debug("cannot walk the tree to find a node for %q, returning nil", new_root)
        return nil
      else
        tree.root = root
        tree.files.root = root
        tree.files.current_node = tree.current_node
      end
    else
      log.debug("the new root %q is the same as the current root %s, skipping", new_root, tostring(tree.root))
    end

    tree.refreshing = false
    return tree
  end

  ---@async
  ---@param tree YaTree
  ---@param new_root string|YaTreeNode
  ---@return YaTree tree
  function Tree.update_tree_root_node(tree, new_root)
    if type(new_root) == "string" then
      log.debug("new root is string %q", new_root)
      if not fs.is_directory(new_root) then
        new_root = Path:new(new_root):parent():absolute() --[[@as string]]
      end
      local new_tree = update_tree_root_node(tree, new_root)
      if not new_tree then
        log.debug("root %q could not be found walking the old tree %q, creating a new tree", new_root, tree.files.root.path)
        new_tree = Tree.get_or_create_tree(new_root, tree.tabpage)
      end
      return new_tree
    elseif type(new_root) == "table" then
      ---@cast new_root YaTreeNode
      if tree.files.root.path ~= new_root.path then
        log.debug("new root is node %q", tostring(new_root))
        tree.refreshing = true
        tree.root = new_root
        tree.root:expand({ force_scan = true })
        tree.files.root = new_root
        tree.files.current_node = tree.current_node
        tree.refreshing = false
      else
        log.debug("the new root %q is the same as the current root %s, skipping", tostring(new_root), tostring(tree.root))
      end
      return tree
    else
      log.error("new_root is of a type %q, which is not supported, returning old tree", type(new_root))
      return tree
    end
  end
end

M._get_tree = Tree.get_tree

---@private
---@param cb fun(tree: YaTree)
function M._for_each_tree(cb)
  for _, tree in pairs(M._trees) do
    cb(tree)
  end
end

---@private
---@param tabpage number
function M._delete_tree(tabpage)
  local tree = M._trees[tostring(tabpage)]
  if tree then
    log.debug("deleting tree for tabpage %s", tabpage)
    M._trees[tostring(tabpage)] = nil
  end

  for repo, tabpages in pairs(M._repo_tabpages) do
    for index, tab in ipairs(tabpages) do
      if tab == tabpage then
        log.debug("removing tab %s from repo %s list of tabpages", tab, tostring(repo))
        table.remove(tabpages, index)
        break
      end
    end
    if #tabpages == 0 then
      log.debug("no tree contains repo %s, removing it", tostring(repo))
      local listener_id = M._repo_listeners[repo]
      if not listener_id then
        log.error("no listener_id registered for repo %s", tostring(repo))
      else
        repo:remove_git_change_listener(listener_id)
      end
      if not repo:has_git_listeners() then
        git.remove_repo(repo)
      end
      M._repo_tabpages[repo] = nil
      M._repo_listeners[repo] = nil
    end
  end
end

---@private
---@param tabindex number
---@return number? tabpage
function M._tabindex_to_tabpage(tabindex)
  ---@type number[]
  local tabpages = {}
  for tab, _ in pairs(M._trees) do
    tabpages[#tabpages + 1] = tonumber(tab)
  end
  table.sort(tabpages)
  return tabpages[tabindex]
end

---@param node YaTreeNode
---@return boolean is_node_root
function M.is_node_root(node)
  return Tree.get_tree().root.path == node.path
end

---@return string root_path
function M.get_root_path()
  return Tree.get_tree().root.path
end

--- Resolves the `path` in the `tree`.
---@param tree YaTree
---@param path string
---@return string|nil path the fully resolved path, or `nil`
local function resolve_path_in_tree(tree, path)
  if not utils.is_absolute_path(path) then
    -- a relative path is relative to the current cwd, not the tree's root node
    path = Path:new({ uv.cwd(), path }):absolute() --[[@as string]]
    log.debug("expanded cwd relative path to %s", path)
  end

  if path:find(tree.root.path, 1, true) then
    log.debug("found path %q in tree root %q", path, tree.root.path)
    -- strip the ending path separator from the path, the node expansion requires that directories doesn't end with it
    if path:sub(-1) == utils.os_sep then
      path = path:sub(1, -2)
    end

    return path
  end
end

---@async
---@param tree YaTree
local function create_buffers_tree(tree)
  tree.buffers.root, tree.buffers.current_node = Nodes.create_buffers_tree(tree.files.root.path)
  tree.root = tree.buffers.root
  tree.current_node = tree.buffers.current_node
end

---@async
---@param tree YaTree
---@param repo GitRepo
local function create_git_status_tree(tree, repo)
  tree.git_status.root, tree.git_status.current_node = Nodes.create_git_status_tree(repo)
  tree.root = tree.git_status.root
  tree.current_node = tree.git_status.current_node
end

---@async
---@param opts? {path?: string, switch_root?: boolean, focus?: boolean, view_mode?: YaTreeCanvasViewMode}
---  - {opts.path?} `string`
---  - {opts.switch_root?} `boolean`
---  - {opts.focus?} `boolean`
---  - {opts.view_mode?} `YaTreeCanvasViewMode`
function M.open_window(opts)
  if setting_up then
    log.debug("setup is in progress, deferring opening window...")
    local deferred = void(function()
      M.open_window(opts)
    end)
    vim.defer_fn(deferred, 100)
    return
  end

  opts = opts or {}
  log.debug("opening tree with %s", opts)
  -- If the switch_root flag is true and a file is given _and_ the appropriate config flag is set,
  -- we need to update the tree with the new cwd and root _before_ issuing the `tcd` command, since
  -- control passes to the handler. Issuing it after will be a no-op since since the tree cwd is already set.
  local issue_tcd = false

  scheduler()
  local tree
  if opts.switch_root and opts.path then
    issue_tcd = config.cwd.update_from_tree
    local path = Path:new(opts.path)
    local cwd = path:absolute() --[[@as string]]
    if not path:is_dir() then
      path = path:parent()
      cwd = path:absolute() --[[@as string]]
    end
    if path:exists() then
      log.debug("switching tree cwd to %q", cwd)
      tree = Tree.get_tree()
      if tree then
        tree = Tree.update_tree_root_node(tree, cwd)
      else
        tree = Tree.get_or_create_tree(cwd)
      end
      if config.cwd.update_from_tree then
        -- updating the root node doesn't change the cwd, so set it
        tree.cwd = cwd
      end
      scheduler()
      -- when switching root and creating a new tree, force the view mode to 'files',
      -- otherwise visual inconsistencies can arise
      ui.set_view_mode("files")
    else
      utils.warn(string.format("Path %q doesn't exist.\nUsing %q as tree root", opts.path, uv.cwd()))
      tree = Tree.get_or_create_tree()
    end
  else
    tree = Tree.get_or_create_tree()
  end

  ---@type string|nil
  local path
  if opts.path then
    path = resolve_path_in_tree(tree, opts.path)
    if not path then
      log.info("%q cannot be resolved in the current tree (cwd=%q, root=%q)", opts.path, uv.cwd(), tree.root.path)
    end
  end

  if opts.view_mode == "files" then
    tree.root = tree.files.root
  elseif opts.view_mode == "buffers" then
    if not tree.buffers.root then
      create_buffers_tree(tree)
    else
      tree.root = tree.buffers.root
    end
  elseif opts.view_mode == "git_status" then
    if not tree.git_status.root then
      local repo = path and git.create_repo(path) or tree.files.root.repo
      if repo then
        create_git_status_tree(tree, repo)
      else
        utils.warn(string.format("Could not find a Git repository in path %q", tree.files.root.path))
      end
    else
      tree.root = tree.git_status.root
    end
  elseif opts.view_mode ~= nil then
    log.error("view mode %q is not supported when opening the window", opts.view_mode)
    opts.view_mode = nil
  end

  local node
  if path then
    node = tree.root:expand({ to = path })
    if node then
      local displayable, reason = utils.is_node_displayable(node, config)
      if not displayable and reason then
        if reason == "filter" then
          config.filters.enable = false
        elseif reason == "git" then
          config.git.show_ignored = true
        end
      end
      log.debug("navigating to %q", path)
    else
      if opts.view_mode and opts.view_mode == "files" then
        log.error("cannot expand to file %q in tree %s", path, tostring(tree))
        utils.warn(string.format("Path %q is not a file or directory", opts.path))
      else
        log.debug("cannot expand to node %q in view %q", path, opts.view_mode)
        utils.notify(string.format("Path %q is not available in the current view", path))
      end
    end
  else
    if config.follow_focused_file then
      ---@type number
      local bufnr = api.nvim_get_current_buf()
      if api.nvim_buf_get_option(bufnr, "buftype") == "" then
        ---@type string
        local filename = api.nvim_buf_get_name(bufnr)
        if tree.root:is_ancestor_of(filename) then
          node = tree.root:expand({ to = filename })
        end
      end
    end
  end

  scheduler()
  tree.current_node = node or (ui.is_open() and ui.get_current_node() or nil)
  if ui.is_open() and not opts.view_mode then
    if opts.focus then
      ui.focus()
    end
    ui.update(tree.root, tree.current_node)
  else
    ui.open(tree.root, tree.current_node, { focus = opts.focus, focus_edit_window = not opts.focus, view_mode = opts.view_mode })
  end

  if issue_tcd then
    log.debug("issueing tcd autocmd to %q", tree.files.root.path)
    vim.cmd("tcd " .. fn.fnameescape(tree.files.root.path))
  end
end

function M.close_window()
  ui.close()
end

---@async
function M.toggle_window()
  if ui.is_open() then
    M.close_window()
  else
    M.open_window()
  end
end

function M.redraw()
  local tree = Tree.get_tree()
  if tree and ui.is_open() then
    log.debug("redrawing tree")
    ui.update(tree.root)
  end
end

---@async
---@param node YaTreeNode
function M.toggle_node(node)
  local tree = Tree.get_tree()
  if not node:is_container() or tree.root == node then
    return
  end

  if node.expanded then
    node:collapse()
  else
    node:expand()
  end

  ui.update(tree.root)
end

---@param node YaTreeNode
function M.close_node(node)
  local tree = Tree.get_tree()
  -- bail if the node is the root node
  if tree.root == node then
    return
  end

  if node:is_container() and node.expanded then
    node:collapse()
  else
    local parent = node.parent
    if parent and parent ~= tree.root then
      parent:collapse()
      node = parent
    end
  end
  tree.current_node = node

  ui.update(tree.root, tree.current_node)
end

function M.close_all_nodes()
  local tree = Tree.get_tree()
  tree.root:collapse({ recursive = true, children_only = true })
  tree.current_node = tree.root
  ui.update(tree.root, tree.current_node)
end

do
  ---@async
  ---@param node YaTreeNode
  ---@param depth number
  local function expand(node, depth)
    node:expand()
    if depth < config.expand_all_nodes_max_depth then
      for _, child in ipairs(node.children) do
        if child:is_container() and utils.is_node_displayable(child, config) then
          expand(child, depth + 1)
        end
      end
    end
  end

  ---@async
  ---@param node YaTreeNode
  function M.expand_all_nodes(node)
    local tree = Tree.get_tree()
    expand(tree.root, 1)
    ui.update(tree.root, node)
  end
end

---@private
---@async
---@param tree YaTree
---@param new_root string|YaTreeNode
function M._change_root_node_for_tree(tree, new_root)
  log.debug("changing root node to %q for tree %s", tostring(new_root), tostring(tree))

  scheduler()
  ---@type number
  local tabpage = api.nvim_get_current_tabpage()
  tree = Tree.update_tree_root_node(tree, new_root)

  if tree.tabpage == tabpage and ui.is_open() then
    if ui.is_search_open() then
      ui.close_search(tree.root, tree.current_node)
    elseif ui.is_buffers_open() then
      ui.close_buffers(tree.root, tree.current_node)
    elseif ui.is_git_status_open() then
      ui.close_git_status(tree.root, tree.current_node)
    else
      ui.update(tree.root, tree.current_node)
    end
  end
end

---@async
---@param node YaTreeNode
function M.cd_to(node)
  local tree = Tree.get_tree()
  if node == tree.root then
    return
  end

  if not node:is_directory() then
    if not node.parent or node.parent == tree.root then
      return
    end
    node = node.parent --[[@as YaTreeNode]]
  end

  if node:node_type() == "GitStatus" and node.repo:is_yadm() then
    log.debug("changing root node of yadm git status tree to %q", node.path)
    tree.git_status.root = node --[[@as YaTreeGitStatusNode]]
    tree.root = tree.git_status.root
    ui.update(tree.root, node)
  else
    log.debug("cd to %q", node.path)

    -- only issue a :tcd if the config is set, _and_ the path is different from the tree's cwd
    if config.cwd.update_from_tree and node.path ~= tree.cwd then
      vim.cmd("tcd " .. fn.fnameescape(node.path))
    elseif node.path ~= tree.root.path then
      M._change_root_node_for_tree(tree, node)
    end
  end
end

---@async
---@param node YaTreeNode
function M.cd_up(node)
  local tree = Tree.get_tree()
  if utils.is_root(tree.root.path) then
    return
  end

  local new_cwd = tree.root.parent and tree.root.parent.path or Path:new(tree.root.path):parent().filename
  log.debug("changing root directory one level up from %q to %q", tree.root.path, new_cwd)

  -- save current position
  tree.current_node = node
  -- only issue a :tcd if the config is set, _and_ the path is different from the tree's cwd
  if config.cwd.update_from_tree and new_cwd ~= tree.cwd then
    vim.cmd("tcd " .. fn.fnameescape(new_cwd))
  else
    M._change_root_node_for_tree(tree, tree.root.parent or new_cwd)
  end
end

---@param node YaTreeNode
function M.toggle_ignored(node)
  config.git.show_ignored = not config.git.show_ignored
  log.debug("toggling git ignored to %s", config.git.show_ignored)
  local tree = Tree.get_tree()
  tree.current_node = node
  ui.update(tree.root, tree.current_node)
end

---@param node YaTreeNode
function M.toggle_filter(node)
  config.filters.enable = not config.filters.enable
  log.debug("toggling filter to %s", config.filters.enable)
  local tree = Tree.get_tree()
  tree.current_node = node
  ui.update(tree.root, tree.current_node)
end

---@async
---@param node YaTreeNode
function M.rescan_dir_for_git(node)
  if not config.git.enable then
    utils.notify("Git is not enabled.")
    return
  end
  local tree = Tree.get_tree()
  if tree.refreshing or vim.v.exiting ~= vim.NIL then
    log.debug("refresh already in progress or vim is exiting, aborting refresh")
    return
  end
  tree.refreshing = true
  log.debug("checking if %s is in a git repository", node.path)

  if not node:is_directory() then
    node = node.parent --[[@as YaTreeNode]]
  end
  if not node.repo or node.repo:is_yadm() then
    local repo = git.create_repo(node.path)
    if repo then
      node:set_git_repo(repo)
      repo:refresh_status({ ignored = true })
      add_git_change_listener(tree.tabpage, repo)
      ui.update(tree.root, node)
    else
      utils.notify(string.format("No Git repository found in %q.", node.path))
    end
  end
  tree.refreshing = false
end

---@async
---@param node YaTreeNode
---@param term string
function M.search(node, term)
  scheduler()
  local tree = Tree.get_tree()

  -- store the current tree only once, before the search is done
  if not ui.is_search_open() then
    tree.files.root = tree.root
    tree.files.current_node = ui.get_current_node()
  end

  local cmd, args = utils.build_search_arguments(term, node.path, true)
  if not cmd then
    utils.warn("No suitable search command found!")
    return
  end

  local result_node
  local matches_or_error
  if not tree.search.root or tree.search.root.path ~= node.path then
    tree.search.root, result_node, matches_or_error = Nodes.create_search_tree(node.path, term, cmd, args)
  else
    result_node, matches_or_error = tree.search.root:search(term, cmd, args)
  end
  if result_node then
    tree.search.current_node = result_node
    tree.root = tree.search.root
    tree.current_node = tree.search.current_node

    utils.notify(string.format("%q found %s matches for %q in %q", cmd, matches_or_error, term, node.path))
    ui.open_search(tree.search.root, tree.search.current_node)
  else
    utils.warn(string.format("%q failed with message:\n\n%s", cmd, matches_or_error))
  end
end

function M.focus_first_search_result()
  local tree = Tree.get_tree()
  if tree.search.current_node then
    ui.focus_node(tree.search.current_node)
  end
end

---@async
---@param node_or_path YaTreeNode|string
function M.refresh_tree(node_or_path)
  local tree = Tree.get_tree()
  if tree.refreshing or vim.v.exiting ~= vim.NIL then
    log.debug("refresh already in progress or vim is exiting, aborting refresh")
    return
  end
  tree.refreshing = true
  log.debug("refreshing current tree")

  scheduler()
  local node
  if ui.is_buffers_open() then
    tree.buffers.root:refresh()
    node = ui.get_current_node()
  elseif ui.is_git_status_open() then
    tree.git_status.root:refresh()
    node = ui.get_current_node()
  elseif ui.is_search_open() then
    tree.search.root:refresh()
    node = ui.get_current_node()
  else
    tree.files.root:refresh({ recurse = true, refresh_git = config.git.enable })
    if type(node_or_path) == "table" then
      node = node_or_path
    elseif type(node_or_path) == "string" then
      node = tree.files.root:expand({ to = node_or_path })
    else
      log.error("the node_or_path parameter is of an unsupported type %q", type(node_or_path))
    end
  end

  ui.update(tree.root, node, { focus_node = true })
  tree.refreshing = false
end

---@param tree YaTree
---@param current_node? YaTreeSearchNode
local function close_search(tree, current_node)
  -- save the current node in the search tree
  if current_node then
    tree.search.current_node = current_node
  end
  tree.root = tree.files.root
  tree.current_node = tree.files.current_node
  ui.close_search(tree.root, tree.current_node)
end

---@async
---@param node YaTreeNode
function M.goto_node_in_tree(node)
  local tree = Tree.get_tree()
  if ui.is_search_open() then
    ---@cast node YaTreeSearchNode
    tree.files.current_node = tree.files.root:expand({ to = node.path })
    close_search(tree, node)
  elseif ui.is_buffers_open() then
    ---@cast node YaTreeBufferNode
    if node:is_directory() or node:is_file() then
      tree.buffers.current_node = node
      tree.root = tree.files.root
      tree.current_node = tree.root:expand({ to = node.path })
      ui.close_buffers(tree.root, tree.current_node)
    end
  elseif ui.is_git_status_open() then
    ---@cast node YaTreeGitStatusNode
    tree.git_status.current_node = node
    tree.root = tree.files.root
    tree.current_node = tree.root:expand({ to = node.path })
    ui.close_git_status(tree.root, tree.current_node)
  end
end

---@param node? YaTreeSearchNode
function M.close_search(node)
  close_search(Tree.get_tree(), node)
end

---@param node YaTreeNode
function M.show_last_search(node)
  local tree = Tree.get_tree()
  if tree.search.root then
    tree.files.current_node = node
    tree.root = tree.search.root --[[@as YaTreeSearchNode]]
    tree.current_node = tree.search.current_node
    ui.open_search(tree.search.root, tree.search.current_node)
  end
end

---@param path string
function M.search_for_node_in_tree(path)
  local tree = Tree.get_tree()
  local cmd, args = utils.build_search_arguments(path, tree.root.path, false)
  if not cmd then
    return
  end

  job.run({ cmd = cmd, args = args, cwd = tree.root.path, async_callback = true }, function(code, stdout, stderr)
    if code == 0 then
      ---@type string[]
      local lines = vim.split(stdout or "", "\n", { plain = true, trimempty = true })
      log.debug("%q found %s matches for %q in %q", cmd, #lines, path, tree.root.path)

      if #lines > 0 then
        tree.current_node = tree.root:expand({ to = lines[1] })
        scheduler()
        ui.update(tree.root, tree.current_node)
      else
        utils.notify(string.format("%q cannot be found in the tree", path))
      end
    else
      log.error("%q with args %s failed with code %s and message %s", cmd, args, code, stderr)
    end
  end)
end

---@async
---@param node YaTreeNode
function M.toggle_git_status(node)
  local tree = Tree.get_tree()
  if ui.is_git_status_open() then
    ---@cast node YaTreeGitStatusNode
    tree.git_status.current_node = node
    tree.root = tree.files.root
    tree.current_node = tree.files.current_node
    ui.close_git_status(tree.root, tree.current_node)
  else
    if not node.repo then
      M.rescan_dir_for_git(node)
    end
    if node.repo then
      tree.files.current_node = node
      if not tree.git_status.root or tree.git_status.root.repo ~= node.repo then
        create_git_status_tree(tree, node.repo)
      else
        tree.root = tree.git_status.root
        tree.current_node = tree.git_status.current_node
      end
      ui.open_git_status(tree.git_status.root, tree.git_status.current_node)
    end
  end
end

---@async
---@param node YaTreeNode
function M.toggle_buffers(node)
  local tree = Tree.get_tree()
  if ui.is_buffers_open() then
    ---@cast node YaTreeBufferNode
    tree.buffers.current_node = node
    tree.root = tree.files.root
    tree.current_node = tree.files.current_node
    ui.close_buffers(tree.root, tree.current_node)
  else
    tree.files.current_node = node
    if not tree.buffers.root then
      create_buffers_tree(tree)
    else
      tree.root = tree.buffers.root --[[@as YaTreeBufferNode]]
      tree.current_node = tree.buffers.current_node
    end
    ui.open_buffers(tree.buffers.root, tree.buffers.current_node)
  end
end

local function setup_netrw()
  if config.replace_netrw then
    vim.cmd([[silent! autocmd! FileExplorer *]])
    vim.cmd([[autocmd VimEnter * ++once silent! autocmd! FileExplorer *]])
    vim.g.loaded_netrw = 1
    vim.g.loaded_netrwPlugin = 1
  end
end

function M.setup()
  setting_up = true
  config = require("ya-tree.config").config

  setup_netrw()

  local is_directory = false
  ---@type string
  local root_path
  if config.replace_netrw then
    is_directory, root_path = utils.get_path_from_directory_buffer()
  end
  if not is_directory then
    root_path = uv.cwd()
  end

  void(function()
    local tree = Tree.get_or_create_tree(root_path)

    scheduler()
    if is_directory or config.auto_open.on_setup then
      local focus = config.auto_open.on_setup and config.auto_open.focus_tree
      ui.open(tree.root, tree.current_node, { hijack_buffer = is_directory, focus = focus, focus_edit_window = not focus })
    end

    -- the autocmds must be set up last, this avoids triggering the BufNewFile event,
    -- if the initial buffer is a directory
    require("ya-tree.autocommands").setup()

    setting_up = false
  end)()
end

return M
