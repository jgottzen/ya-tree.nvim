local scheduler = require("plenary.async.util").scheduler
local void = require("plenary.async.async").void
local Path = require("plenary.path")

local config = require("ya-tree.config").config
local Tree = require("ya-tree.tree")
local Nodes = require("ya-tree.nodes")
local git = require("ya-tree.git")
local job = require("ya-tree.job")
local debounce_trailing = require("ya-tree.debounce").debounce_trailing
local ui = require("ya-tree.ui")
local utils = require("ya-tree.utils")
local log = require("ya-tree.log")

local api = vim.api
local fn = vim.fn
local uv = vim.loop

-- Flag for signaling when the library is setting up, which might take time if in a large directory and/or
-- repository. A call to M.open(), while setting up, will create another, duplicate, tree and doing the
-- filesystem and repository scanning again.
local setting_up = false

local M = {}

---@async
---@param node YaTreeNode
---@return boolean is_node_root
function M.is_node_root(node)
  return Tree.get_tree().root.path == node.path
end

---@async
---@return string root_path
function M.get_root_path()
  return Tree.get_tree().root.path
end

--- Resolves the `path` in the speicfied `tree`.
---@param tree YaTree
---@param path string
---@return string? path #the fully resolved path, or `nil`
local function resolve_path_in_tree(tree, path)
  if not vim.startswith(path, utils.os_root()) then
    -- a relative path is relative to the current cwd, not the tree's root node
    path = Path:new({ uv.cwd(), path }):absolute()
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
  tree.buffers.root, tree.buffers.current_node = Nodes.create_buffers_tree(tree.tree.root.path)
  tree.root = tree.buffers.root
  tree.current_node = tree.buffers.current_node
end

---@async
---@param tree YaTree
---@param repo GitRepo
---@param root_path string
local function create_git_status_tree(tree, repo, root_path)
  tree.git_status.root, tree.git_status.current_node = Nodes.create_git_status_tree(root_path, repo)
  tree.root = tree.git_status.root
  tree.current_node = tree.git_status.current_node
end

---@async
---@param repo GitRepo
---@param watcher_id number
---@param fs_changes boolean
function M.on_git_change(repo, watcher_id, fs_changes)
  if vim.v.exiting ~= vim.NIL then
    return
  end
  log.debug("git repo %s changed", tostring(repo))

  scheduler()
  ---@type number
  local tabpage = api.nvim_get_current_tabpage()
  Tree.for_each_tree(function(tree)
    if tree.git_watchers[repo] == watcher_id then
      if fs_changes then
        log.debug("git watcher called with fs_changes=true, refreshing tree")
        if tree.git_status.root then
          tree.git_status.root:refresh({ refresh_git = false })
        end
        local node = tree.tree.root:get_child_if_loaded(repo.toplevel)
        if node then
          log.debug("repo %s is loaded in node %q", tostring(repo), node.path)
          node:refresh({ recurse = true })
        elseif tree.tree.root.path:find(repo.toplevel, 1, true) ~= nil then
          log.debug("tree root %q is a subdirectory of repo %s", tree.tree.root.path, tostring(repo))
          tree.tree.root:refresh({ recurse = true })
        end
      end
      scheduler()
      if tabpage == tree.tabpage and ui.is_open() then
        tree.current_node = ui.get_current_node()
        ui.update(tree.root, tree.current_node)
      end
    end
  end)
end

---@async
---@param opts? {file?: string, switch_root?: boolean, focus?: boolean}
---  - {opts.file?} `string`
---  - {opts.switch_root?} `boolean`
---  - {opts.focus?} `boolean`
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

  ---@type YaTree
  local tree
  if opts.switch_root and opts.file then
    issue_tcd = config.cwd.update_from_tree
    ---@type string
    local cwd = Path:new(opts.file):absolute()
    if not utils.is_directory(cwd) then
      cwd = Path:new(cwd):parent().filename
    end
    log.debug("switching tree cwd to %q", cwd)
    tree = Tree.get_tree()
    if tree then
      tree = Tree.update_tree_root_node(tree, cwd)
      tree.cwd = cwd
    else
      tree = Tree.get_or_create_tree(cwd)
    end
    scheduler()
    -- when switching root and creating a new tree, force the view mode to 'tree',
    -- otherwise visual inconsistencies can arise
    ui.set_view_mode("tree")
  else
    tree = Tree.get_or_create_tree()
  end

  ---@type YaTreeNode
  local node
  if opts.file then
    local file = resolve_path_in_tree(tree, opts.file)
    if file then
      node = tree.root:expand({ to = file })
      if node then
        local displayable, reason = node:is_displayable(config)
        if not displayable and reason then
          if reason == "filter" then
            config.filters.enable = false
          elseif reason == "git" then
            config.git.show_ignored = true
          end
        end
        log.debug("navigating to %q", file)
      else
        log.error("cannot expand to file %q in tree %s", file, tostring(tree))
      end
    else
      log.debug("%q cannot be resolved in the current tree (cwd=%q, root=%q)", opts.file, uv.cwd(), tree.root.path)
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
  if ui.is_open() then
    if opts.focus then
      ui.focus()
    end
    ui.update(tree.root, tree.current_node)
  else
    ui.open(tree.root, tree.current_node, { focus = opts.focus, focus_edit_window = not opts.focus })
  end

  if issue_tcd then
    log.debug("issueing tcd autocmd to %q", tree.tree.root.path)
    vim.cmd("tcd " .. fn.fnameescape(tree.tree.root.path))
  end
end

---@async
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

---@async
function M.redraw()
  local tree = Tree.get_tree()
  if tree and ui.is_open() then
    log.debug("redrawing tree")
    scheduler()
    ui.update(tree.root)
  end
end

---@async
---@param node YaTreeNode
function M.toggle_directory(node)
  local tree = Tree.get_tree()
  if not node:is_directory() or tree.root == node then
    return
  end

  if node.expanded then
    node:collapse()
  else
    node:expand()
  end

  ui.update(tree.root)
end

---@async
---@param node YaTreeNode
function M.close_node(node)
  local tree = Tree.get_tree()
  -- bail if the node is the root node
  if tree.root == node then
    return
  end

  if node:is_directory() and node.expanded then
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

---@async
function M.close_all_nodes()
  local tree = Tree.get_tree()
  tree.root:collapse({ recursive = true, children_only = true })
  tree.current_node = tree.root
  ui.update(tree.root, tree.current_node)
end

---@async
---@param node YaTreeNode
function M.expand_all_nodes(node)
  local tree = Tree.get_tree()
  tree.root:expand({ all = true })
  ui.update(tree.root, node)
end

---@async
---@param tree YaTree
---@param new_root string|YaTreeNode
local function change_root_node_for_tree(tree, new_root)
  log.debug("changing root node to %q", tostring(new_root))

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

  -- save current position
  tree.current_node = node
  if not node:is_directory() then
    if not node.parent or node.parent == tree.root then
      return
    end
    node = node.parent
  end
  log.debug("cd to %q", node.path)

  -- only issue a :tcd if the config is set, _and_ the path is different from the tree's cwd
  if config.cwd.update_from_tree and node.path ~= tree.cwd then
    vim.cmd("tcd " .. fn.fnameescape(node.path))
  elseif node.path ~= tree.root.path then
    change_root_node_for_tree(tree, node)
  end
end

---@async
---@param node YaTreeNode
function M.cd_up(node)
  local tree = Tree.get_tree()
  if tree.root.path == utils.os_root() then
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
    change_root_node_for_tree(tree, tree.root.parent or new_cwd)
  end
end

---@async
---@param node YaTreeNode
function M.toggle_ignored(node)
  config.git.show_ignored = not config.git.show_ignored
  log.debug("toggling git ignored to %s", config.git.show_ignored)
  local tree = Tree.get_tree()
  tree.current_node = node
  ui.update(tree.root, tree.current_node)
end

---@async
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
    node = node.parent
  end
  if node:check_for_git_repo() then
    Tree.attach_git_watcher(tree, node.repo)
    ui.update(tree.root, node)
  else
    utils.notify(string.format("No Git repository found in %q.", node.path))
  end
  tree.refreshing = false
end

---@async
---@param node YaTreeNode
---@param term string
---@param focus_node boolean should only be `true` *iff* the search is final and _not_ incremental.
function M.search(node, term, focus_node)
  local tree = Tree.get_tree()

  -- store the current tree only once, before the search is done
  scheduler()
  if not ui.is_search_open() then
    tree.tree.root = tree.root
    tree.tree.current_node = ui.get_current_node()
  end

  local search_term = term
  if term ~= "*" and not term:find("*") then
    search_term = "*" .. term .. "*"
  end
  local cmd, args = utils.build_search_arguments(search_term, node.path, true)
  if not cmd then
    utils.warn("No suitable search command found!")
    return
  end

  ---@type YaTreeSearchNode?
  local result_node
  ---@type integer|string
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
    ui.open_search(tree.root, focus_node and tree.current_node or nil)
  else
    utils.warn(string.format("%q failed with message:\n\n%s", cmd, matches_or_error))
  end
end

---@async
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
  ---@type YaTreeNode
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
    tree.tree.root:refresh({ recurse = true, refresh_git = config.git.enable })
    if type(node_or_path) == "table" then
      node = node_or_path
    elseif type(node_or_path) == "string" then
      node = tree.tree.root:expand({ to = node_or_path })
    else
      log.error("the node_or_path parameter is of an unsupported type %q", type(node_or_path))
    end
  end

  ui.update(tree.root, node, { focus_node = true })
  tree.refreshing = false
end

---@param tree YaTree
---@param current_node? YaTreeNode
local function close_search(tree, current_node)
  -- save the current node in the search tree
  if current_node then
    tree.search.current_node = current_node
  end
  tree.root = tree.tree.root
  tree.current_node = tree.tree.current_node
  ui.close_search(tree.root, tree.current_node)
end

---@async
---@param node YaTreeNode
function M.goto_node_in_tree(node)
  local tree = Tree.get_tree()
  if ui.is_search_open() then
    tree.tree.current_node = tree.tree.root:expand({ to = node.path })
    close_search(tree, node)
  elseif ui.is_buffers_open() then
    ---@cast node YaTreeBufferNode
    tree.buffers.current_node = node
    tree.root = tree.tree.root
    tree.current_node = tree.root:expand({ to = node.path })
    ui.close_buffers(tree.root, tree.current_node)
  elseif ui.is_git_status_open() then
    ---@cast node YaTreeGitStatusNode
    tree.git_status.current_node = node
    tree.root = tree.tree.root
    tree.current_node = tree.root:expand({ to = node.path })
    ui.close_git_status(tree.root, tree.current_node)
  end
end

---@async
---@param node? YaTreeNode
function M.close_search(node)
  close_search(Tree.get_tree(), node)
end

---@async
---@param node YaTreeNode
function M.show_last_search(node)
  local tree = Tree.get_tree()
  if tree.search.root then
    tree.tree.current_node = node
    tree.root = tree.search.root
    tree.current_node = tree.search.current_node
    ui.open_search(tree.search.root, tree.search.current_node)
  end
end

---@async
---@param path string
function M.search_for_node_in_tree(path)
  local tree = Tree.get_tree()
  local cmd, args = utils.build_search_arguments(path, tree.root.path, false)
  if not cmd then
    return
  end

  job.run({ cmd = cmd, args = args, cwd = tree.root.path, async_callback = true }, function(code, stdout)
    if code == 0 then
      ---@type string[]
      local lines = vim.split(stdout or "", "\n", { plain = true, trimempty = true })
      log.debug("%q found %s matches for %q in %q", cmd, #lines, path, tree.root.path)

      if #lines > 0 then
        tree.current_node = tree.root:expand({ to = lines[1] })
        ui.update(tree.root, tree.current_node)
      else
        utils.notify(string.format("%q cannot be found in the tree", path))
      end
    end
  end)
end

---@async
---@param node YaTreeNode
function M.toggle_git_status(node)
  local tree = Tree.get_tree()
  if ui.is_git_status_open() then
    tree.git_status.current_node = node
    tree.root = tree.tree.root
    tree.current_node = tree.tree.current_node
    ui.close_git_status(tree.root, tree.current_node)
  else
    if not node.repo then
      M.rescan_dir_for_git(node)
    end
    if node.repo then
      tree.tree.current_node = node
      if not tree.git_status.root or tree.git_status.root.repo ~= node.repo then
        local path = node.repo:is_yadm() and tree.root.path or node.repo.toplevel
        create_git_status_tree(tree, node.repo, path)
      else
        tree.root = tree.git_status.root
        tree.current_node = tree.git_status.current_node
      end
      ui.open_git_status(tree.root, tree.current_node)
    end
  end
end

---@async
---@param node YaTreeNode
function M.toggle_buffers(node)
  local tree = Tree.get_tree()
  if ui.is_buffers_open() then
    tree.buffers.current_node = node
    tree.root = tree.tree.root
    tree.current_node = tree.tree.current_node
    ui.close_buffers(tree.root, tree.current_node)
  else
    tree.tree.current_node = node
    if not tree.buffers.root then
      create_buffers_tree(tree)
    else
      tree.root = tree.buffers.root
      tree.current_node = tree.buffers.current_node
    end
    ui.open_buffers(tree.root, tree.current_node)
  end
end

---@async
---@param closed_winid number
local function on_win_closed(closed_winid)
  -- if the closed window was a floating window, do nothing.
  -- otherwise we will quit from a hijacked netrw buffer when using
  -- any form of popup, including command mode
  if ui.is_window_floating(closed_winid) or not ui.is_open() then
    return
  end

  -- defer until the window in question has closed, so that we can check only the remaining windows
  vim.defer_fn(function()
    if #api.nvim_tabpage_list_wins(0) == 1 and vim.bo.filetype == "YaTree" then
      -- check that there are no buffers with unsaved modifications,
      -- if so, just return
      for _, bufnr in ipairs(api.nvim_list_bufs()) do
        if api.nvim_buf_is_loaded(bufnr) and api.nvim_buf_get_option(bufnr, "modified") then
          return
        end
      end
      log.debug("is last window, closing it")
      api.nvim_command(":silent q!")
    end
  end, 100)
end

---@async
local function on_color_scheme()
  scheduler()
  ui.setup_highlights()
  M.redraw()
end

---@async
local function on_tab_new_entered()
  M.open_window({ focus = config.auto_open.focus_tree })
end

---@async
local function on_tab_enter()
  M.redraw()
end

---@async
---@param tabpage number
local function on_tab_closed(tabpage)
  Tree.delete_tree(tabpage)
  scheduler()
  ui.delete_ui(tabpage)
end

---@async
---@param file string
---@param bufnr number
local function on_buf_add_and_file_post(file, bufnr)
  local tree = Tree.get_tree()
  if tree and tree.buffers.root and file ~= "" and api.nvim_buf_get_option(bufnr, "buftype") == "" then
    -- BufFilePost is fired before the file is available on the file system, causing the node creation
    -- to fail, by deferring the call for a short time, we should be able to find the file
    vim.defer_fn(
      void(function()
        ---@type YaTreeBufferNode?
        local node = tree.buffers.root:get_child_if_loaded(file)
        if not node then
          if tree.buffers.root:is_ancestor_of(file) then
            log.debug("adding buffer %q with bufnr %s to buffers tree", file, bufnr)
            tree.buffers.root:add_buffer(file, bufnr)
          else
            log.debug("buffer %q is not under current buffer tree root %q, refreshing buffer tree", file, tree.buffers.root.path)
            tree.buffers.root:refresh()
          end
        elseif node.bufnr ~= bufnr then
          log.debug("buffer %q changed bufnr from %s to %s", file, node.bufnr, bufnr)
          node.bufnr = bufnr
        else
          return
        end

        scheduler()
        if ui.is_open() and ui.is_buffers_open() then
          ui.update(tree.root, ui.get_current_node(), { focus_node = true })
        end
      end),
      100
    )
  end
end

---@async
---@param file string
---@param bufnr number
local function on_buf_enter(file, bufnr)
  if file == "" or api.nvim_buf_get_option(bufnr, "buftype") ~= "" then
    return
  end
  local tree = Tree.get_tree()

  if config.replace_netrw and utils.is_directory(file) then
    -- strip the ending path separator from the path, the node expansion requires that directories doesn't end with it
    if file:sub(-1) == utils.os_sep then
      file = file:sub(1, -2)
    end
    log.debug("the opened buffer is a directory with path %q", file)

    if ui.is_current_window_ui() then
      ui.restore()
    else
      -- switch back to the previous buffer so the window isn't closed
      vim.cmd("bprevious")
    end
    log.debug("deleting buffer %s with file %q", bufnr, file)
    api.nvim_buf_delete(bufnr, { force = true })
    -- force barbar update, otherwise a ghost tab for the buffer can remain
    if type(fn["bufferline#update"]) == "function" then
      pcall(vim.cmd, "call bufferline#update()")
    end

    local opts = { file = file, focus = true }
    if not tree then
      log.debug("no tree for current tab")
      ---@type string
      local cwd = uv.cwd()
      if file:find(cwd, 1, true) then
        log.debug("requested directory is a subpath of the current cwd %q, opening tree with root at cwd", cwd)
      else
        log.debug("requested directory is not a subpath of the current cwd %q, opening tree with root of the requested path", cwd)
        opts.switch_root = true
      end
    elseif not tree.tree.root:is_ancestor_of(file) and tree.tree.root.path ~= file then
      log.debug("the current tree is not a parent for directory %s", file)
      opts.switch_root = true
    else
      log.debug("current tree is parent of directory %s", file)
    end

    M.open_window(opts)
  elseif tree and ui.is_open() then
    -- only update the ui iff highlighting of open files is enabled and
    -- the necessary config options are set
    local update_ui = ui.is_highlight_open_file_enabled()
    if ui.is_current_window_ui() and config.move_buffers_from_tree_window then
      log.debug("moving buffer %s to edit window", bufnr)
      ui.move_buffer_to_edit_window(bufnr)
    end
    if config.follow_focused_file then
      log.debug("focusing on node %q", file)
      tree.current_node = tree.root:expand({ to = file })
      ui.update(tree.root, tree.current_node, { focus_node = true })
      -- avoid updating twice
      update_ui = false
    end

    if update_ui then
      ui.update(tree.root)
    end
  end
end

---@async
---@param file string
---@param bufnr number
local function on_buf_delete(file, bufnr)
  local tree = Tree.get_tree()
  if tree and tree.buffers.root and file ~= "" and api.nvim_buf_get_option(bufnr, "buftype") == "" then
    log.debug("removing buffer %q from buffer tree", file)
    tree.buffers.root:remove_buffer(file)
    if #tree.buffers.root.children == 0 and tree.buffers.root.path ~= tree.tree.root.path then
      tree.buffers.root:refresh({ root_path = tree.tree.root.path })
    end
    if ui.is_open() and ui.is_buffers_open() then
      ui.update(tree.root, ui.get_current_node())
    end
  end
end

---@async
---@param file string
---@param bufnr number
local function on_buf_write_post(file, bufnr)
  if file ~= "" and api.nvim_buf_get_option(bufnr, "buftype") == "" then
    ---@type number
    local tabpage = api.nvim_get_current_tabpage()
    Tree.for_each_tree(function(tree)
      ---@type YaTreeNode?
      local node
      -- always refresh the 'actual' tree, and not the current 'view', i.e. search, buffers or git status
      if tree.tree.root:is_ancestor_of(file) then
        log.debug("changed file %q is in tree %q and tab %s", file, tree.tree.root.path, tree.tabpage)
        node = tree.tree.root:get_child_if_loaded(file)
        if node then
          node:refresh()
        end
      end

      local git_status_changed = false
      ---@type GitRepo?
      local repo
      if config.git.enable then
        if node then
          repo = node.repo
        else
          repo = git.get_repo_for_path(file)
        end
        if repo then
          git_status_changed = repo:refresh_status_for_file(file)
        end
      end

      if tree.git_status.root and tree.git_status.root:is_ancestor_of(file) then
        local git_node = tree.git_status.root:get_child_if_loaded(file)
        if not repo then
          repo = tree.git_status.root.repo
          ---@cast repo GitRepo
          git_status_changed = repo:refresh_status_for_file(file)
        end
        ---@cast git_node YaTreeGitStatusNode?
        if not git_node and git_status_changed then
          tree.git_status.root:add_file(file)
        elseif git_node and git_status_changed then
          if not git_node:get_git_status() then
            tree.git_status.root:remove_file(file)
          end
        end
        if ui.is_git_status_open() then
          node = git_node
        end
      end

      -- only update the ui if something has changed, and the tree is for the current tabpage
      if tree.tabpage == tabpage and ui.is_open() and ((node and ui.is_node_visible(node)) or git_status_changed) then
        ui.update(tree.root)
      end
    end)
  end
end

---@async
---@param scope "window"|"tabpage"|"global"|"auto"
---@param new_cwd string
---@param window_change boolean
local function on_dir_changed(scope, new_cwd, window_change)
  -- if the autocmd was fire was because of a switch to a tab or window with a different
  -- cwd than the previous tab/window, it can safely be ignored.
  if window_change then
    return
  end
  log.debug("scope=%s, window_change=%s, cwd=%s", scope, window_change, new_cwd)

  if scope == "tabpage" then
    local tree = Tree.get_tree()
    -- since DirChanged is only subscribed to if config.cwd.follow is enabled,
    -- the tree.cwd is always bound to the tab cwd, and the root path of the
    -- tree doens't have to be checked
    if not tree or new_cwd == tree.cwd then
      return
    end

    tree.current_node = ui.is_open() and ui.get_current_node() or tree.current_node
    tree.cwd = new_cwd
    change_root_node_for_tree(tree, new_cwd)
  elseif scope == "global" then
    Tree.for_each_tree(function(tree)
      -- since DirChanged is only subscribed to if config.cwd.follow is enabled,
      -- the tree.cwd is always bound to the tab cwd, and the root path of the
      -- tree doens't have to be checked
      if new_cwd ~= tree.cwd then
        tree.cwd = new_cwd
        change_root_node_for_tree(tree, new_cwd)
      end
    end)
  end
end

---@async
local function on_diagnostics_changed()
  scheduler()
  ---@type table<string, number>
  local diagnostics = {}
  for _, diagnostic in ipairs(vim.diagnostic.get()) do
    local bufnr = diagnostic.bufnr
    if api.nvim_buf_is_valid(bufnr) then
      ---@type string
      local bufname = api.nvim_buf_get_name(bufnr)
      local severity = diagnostics[bufname]
      -- lower severity value is a higher severity...
      if not severity or diagnostic.severity < severity then
        diagnostics[bufname] = diagnostic.severity
      end
    end
  end

  if config.diagnostics.propagate_to_parents then
    for path, severity in pairs(diagnostics) do
      for _, parent in next, Path:new(path):parents() do
        ---@cast parent string
        local parent_severity = diagnostics[parent]
        if not parent_severity or parent_severity > severity then
          diagnostics[parent] = severity
        else
          break
        end
      end
    end
  end

  local previous_diagnostics = Nodes.set_diagnostics(diagnostics)
  local tree = Tree.get_tree()
  if tree and ui.is_open() then
    ---@type number
    local diagnostics_count = vim.tbl_count(diagnostics)
    ---@type number
    local previous_diagnostics_count = vim.tbl_count(previous_diagnostics)

    local changed = false
    if diagnostics_count > 0 and previous_diagnostics_count > 0 then
      if diagnostics_count ~= previous_diagnostics_count then
        changed = true
      else
        for path, severity in pairs(diagnostics) do
          if previous_diagnostics[path] ~= severity then
            changed = true
            break
          end
        end
      end
    else
      changed = diagnostics_count ~= previous_diagnostics_count
    end

    -- only update the ui if the diagnostics have changed
    if changed then
      ui.update(tree.root)
    end
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

local function setup_autocommands()
  ---@type integer
  local group = api.nvim_create_augroup("YaTree", { clear = true })

  if config.auto_close then
    api.nvim_create_autocmd("WinClosed", {
      group = group,
      callback = void(function(input)
        on_win_closed(tonumber(input.match))
      end),
      desc = "Close Neovim when the tree is the last window",
    })
  end
  api.nvim_create_autocmd("ColorScheme", {
    group = group,
    callback = void(function()
      on_color_scheme()
    end),
    desc = "Updating highlights",
  })

  if config.auto_open.on_new_tab then
    api.nvim_create_autocmd("TabNewEntered", {
      group = group,
      callback = void(function()
        on_tab_new_entered()
      end),
      desc = "Opening the tree on new tabs",
    })
  end
  api.nvim_create_autocmd("TabEnter", {
    group = group,
    callback = void(function()
      on_tab_enter()
    end),
    desc = "Redraw the tree when switching tabs",
  })
  api.nvim_create_autocmd("TabClosed", {
    group = group,
    callback = void(function(input)
      on_tab_closed(tonumber(input.match))
    end),
    desc = "Remove tab-specific tree",
  })

  api.nvim_create_autocmd({ "BufAdd", "BufFilePost" }, {
    group = group,
    pattern = "*",
    callback = void(function(input)
      on_buf_add_and_file_post(input.file, input.buf)
    end),
    desc = "Updating buffers view",
  })
  api.nvim_create_autocmd("BufEnter", {
    group = group,
    pattern = "*",
    callback = void(function(input)
      on_buf_enter(input.file, input.buf)
    end),
    desc = "Current file highlighting in tree, move buffers from tree window, directory buffers handling",
  })
  api.nvim_create_autocmd("BufDelete", {
    group = group,
    pattern = "*",
    callback = void(function(input)
      on_buf_delete(input.match, input.buf)
    end),
    desc = "Updating buffers view",
  })
  if config.auto_reload_on_write then
    api.nvim_create_autocmd("BufWritePost", {
      group = group,
      pattern = "*",
      callback = void(function(input)
        on_buf_write_post(input.match, input.buf)
      end),
      desc = "Reload tree on buffer writes, git status",
    })
  end

  if config.cwd.follow then
    api.nvim_create_autocmd("DirChanged", {
      group = group,
      callback = void(function(input)
        -- currently not available in the table passed to the callback
        ---@type boolean
        local window_change = vim.v.event.changed_window
        on_dir_changed(input.match, input.file, window_change)
      end),
      desc = "Update tree root when the current cwd changes",
    })
  end
  if config.diagnostics.enable then
    api.nvim_create_autocmd("DiagnosticChanged", {
      group = group,
      pattern = "*",
      callback = debounce_trailing(void(on_diagnostics_changed), config.diagnostics.debounce_time),
      desc = "Diagnostic icons in the tree",
    })
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
    setup_autocommands()

    setting_up = false
  end)()
end

return M
