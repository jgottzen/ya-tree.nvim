local async = require("plenary.async")
local Path = require("plenary.path")

local config = require("ya-tree.config").config
local Tree = require("ya-tree.tree")
local Nodes = require("ya-tree.nodes")
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

---@param node YaTreeNode
---@return boolean is_node_root
function M.is_node_root(node)
  local tree = Tree.get_tree()
  return tree and tree.root.path == node.path or false
end

---@return string|nil root_path
function M.get_root_node_path()
  local tree = Tree.get_tree()
  return tree and tree.root.path
end

--- Resolves the `path` in the speicfied `tree`. If `path` is `nil` or empty, instead resolves the path of the current buffer.
---@param tree YaTree
---@param path? string
---@return string|nil path #the fully resolved path, or `nil`
local function resolve_path_in_tree(tree, path)
  if not path or path == "" then
    local bufname = fn.bufname()
    local file = fn.fnamemodify(bufname, ":p")
    log.debug("current buffer file is %s, bufname is %s", file, bufname)

    path = utils.is_readable_file(file) and file
  end
  if path and not vim.startswith(path, utils.os_root()) then
    -- a relative path is relative to the current cwd, not the tree's root node
    path = Path:new({ tree.cwd, path }):absolute()
    log.debug("expanded cwd relative path to %s", path)
  end

    -- strip the ending path separator from the path, the node expansion requires that directories doesn't end with it
    if path and path:sub(-1) == utils.os_sep then
      path = path:sub(1, -2)
    end

  if path and path:find(tree.root.path, 1, true) then
    log.debug("found path %q in tree root %q", path, tree.root.path)
    -- the path is located in the tree
    return path
  end
end

---@async
---@param repo GitRepo
---@param watcher_id number
---@param fs_changes boolean
local function on_git_change(repo, watcher_id, fs_changes)
  log.debug("git repo %s changed", tostring(repo))

  if vim.v.exiting ~= vim.NIL then
    log.debug("vim is exiting, aborting refresh")
    return
  end

  vim.schedule(function()
    local tree = Tree.get_tree()
    if tree and tree.git_watchers[repo] == watcher_id then
      if fs_changes then
        tree.root:refresh({ recurse = true })
      end
      if ui.is_open() then
        tree.current_node = ui.get_current_node()
        ui.update(tree.root, tree.current_node)
      end
    end
  end)
end

---@param tree YaTree
---@param repo GitRepo
local function attach_git_change_listener(tree, repo)
  if not tree.git_watchers[repo] then
    local watcher_id = repo:add_git_change_listener(on_git_change)
    tree.git_watchers[repo] = watcher_id
    log.debug("attached git change listener for tree %s to git repo %s with id %s", tree.root.path, repo.toplevel, watcher_id)
  end
end

---@param opts? {tree?: YaTree, file?: string, hijack_buffer?: boolean, focus?: boolean}
---  - {opts.tree?} `YaTree`
---  - {opts.file?} `string`
---  - {opts.hijack_buffer?} `boolean`
---  - {opts.focus?} `boolean`
function M.open(opts)
  if setting_up then
    vim.defer_fn(function()
      log.debug("setup is in progress, deferring opening window...")
      M.open(opts)
    end, 100)
  else
    async.run(function()
      opts = opts or {}
      ---@type YaTree
      local tree = opts.tree or Tree.get_or_create_tree()
      -- if a tree was passed as a parameter, then the caller should set up any watchers
      if not opts.tree and tree.root.repo and config.git.watch_git_dir then
        attach_git_change_listener(tree, tree.root.repo)
      end

      ---@type YaTreeNode
      local node
      if opts.file then
        local file = resolve_path_in_tree(tree, opts.file)
        if file then
          node = file and tree.root:expand({ to = file })
          log.debug("navigating to %q", file)
        else
          log.debug("%q cannot be resolved in the current tree (cwd=%q, root=%q)", opts.file, tree.cwd, tree.root.path)
        end
      end

      vim.schedule(function()
        tree.current_node = node or (ui.is_open() and ui.get_current_node()) or tree.current_node
        ui.open(tree.root, tree.current_node, { hijack_buffer = opts.hijack_buffer, focus = opts.focus })
      end)
    end, nil)
  end
end

function M.close()
  ui.close()
end

function M.toggle()
  if ui.is_open() then
    M.close()
  else
    M.open()
  end
end

function M.redraw()
  local tree = Tree.get_tree()
  if tree then
    log.debug("redrawing tree")
    ui.update(tree.root)
  end
end

---@return YaTreeNode? current_node
function M.get_current_node()
  return ui.get_current_node()
end

---@param node YaTreeNode
function M.toggle_directory(node)
  local tree = Tree.get_tree()
  if not tree or not node or not node:is_directory() or tree.root == node then
    return
  end

  async.run(function()
    if node.expanded then
      node:collapse()
    else
      node:expand()
    end

    vim.schedule(function()
      ui.update(tree.root)
    end)
  end, nil)
end

---@param node YaTreeNode
function M.close_node(node)
  local tree = Tree.get_tree()
  -- bail if the node is the root node
  if not tree or not node or tree.root == node then
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

function M.close_all_nodes()
  local tree = Tree.get_tree()
  if tree then
    tree.root:collapse({ recursive = true, children_only = true })
    tree.current_node = tree.root
    ui.update(tree.root, tree.current_node)
  end
end

---@param tree YaTree
---@param new_root string|YaTreeNode
local function update_tree_root_node(tree, new_root)
  if type(new_root) == "string" then
    if tree.root.path ~= new_root then
      ---@type YaTreeNode
      local root
      if tree.root:is_ancestor_of(new_root) then
        local node = tree.root:get_child_if_loaded(new_root)
        if node then
          root = node
          root:expand({ force_scan = true })
        end
      elseif tree.root.path:find(Path:new(new_root):absolute(), 1, true) then
        local parent = tree.root.parent
        while parent and parent.path ~= new_root do
          parent = parent.parent
        end
        if parent and parent.path == new_root then
          root = parent
          root:expand({ force_scan = true })
        end
      end

      if not root then
        root = Nodes.root(new_root, tree.root)
      end
      tree.root = root
      tree.tree.root = root
      tree.tree.current_node = tree.current_node
    end
  else
    if tree.root.path ~= new_root.path then
      ---@type YaTreeNode
      tree.root = new_root
      tree.root:expand({ force_scan = true })
      tree.tree.root = tree.root
      tree.tree.current_node = tree.current_node
    end
  end
end

---@param tree YaTree
---@param new_root string|YaTreeNode
local function change_root_node_for_tree(tree, new_root)
  log.debug("changing root node to %q", tostring(new_root))

  ---@type number
  local tabpage = api.nvim_get_current_tabpage()

  async.run(function()
    update_tree_root_node(tree, new_root)

    if tree.tabpage == tabpage then
      vim.schedule(function()
        ui.update(tree.root, tree.current_node)
      end)
    end
  end, nil)
end

---@param node YaTreeNode
function M.cd_to(node)
  local tree = Tree.get_tree()
  if not tree or not node or not node:is_directory() then
    return
  end
  log.debug("cd to %q", node.path)

  -- save current position
  tree.current_node = node

  -- only issue a :tcd if the config is set, _and_ the path is different from the tree's cwd
  if config.cwd.update_from_tree and node.path ~= tree.cwd then
    vim.cmd("tcd " .. fn.fnameescape(node.path))
  elseif node.path ~= tree.root.path then
    change_root_node_for_tree(tree, node)
  end
end

---@param node YaTreeNode
function M.cd_up(node)
  local tree = Tree.get_tree()
  if not tree then
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

---@param node YaTreeNode
function M.parent_node(node)
  -- check that the node isn't the current root node
  local tree = Tree.get_tree()
  if tree and node and tree.root ~= node then
    node = node.parent
    ui.focus_node(node)
  end
end

---@param node YaTreeNode
function M.prev_sibling(node)
  if node then
    ui.focus_prev_sibling()
  end
end

---@param node YaTreeNode
function M.next_sibling(node)
  if node then
    ui.focus_next_sibling()
  end
end

---@param node YaTreeNode
function M.first_sibling(node)
  if node then
    ui.focus_first_sibling()
  end
end

---@param node YaTreeNode
function M.last_sibling(node)
  if node then
    ui.focus_last_sibling()
  end
end

---@param node YaTreeNode
function M.prev_git_item(node)
  if node then
    ui.focus_prev_git_item()
  end
end

---@param node YaTreeNode
function M.next_git_item(node)
  if node then
    ui.focus_next_git_item()
  end
end

---@param node YaTreeNode
function M.toggle_ignored(node)
  local tree = Tree.get_tree()
  if tree and node then
    log.debug("toggling ignored")

    tree.current_node = node
    config.git.show_ignored = not config.git.show_ignored
    ui.update(tree.root, tree.current_node)
  end
end

---@param node YaTreeNode
function M.toggle_filter(node)
  local tree = Tree.get_tree()
  if tree and node then
    log.debug("toggling filter")

    tree.current_node = node
    config.filters.enable = not config.filters.enable
    ui.update(tree.root, tree.current_node)
  end
end

---@param node_or_path YaTreeNode|string
local function refresh_current_tree(node_or_path)
  local tree = Tree.get_tree()
  if not tree then
    return
  end
  if tree.refreshing or vim.v.exiting ~= vim.NIL then
    log.debug("refresh already in progress or vim is exiting, aborting refresh")
    return
  end

  log.debug("refreshing current tree")
  tree.refreshing = true

  async.run(function()
    -- only refresh git if git watcher is _not_ enabled
    tree.root:refresh({ recurse = true, refresh_git = not config.git.watch_git_dir })

    if type(node_or_path) == "table" then
      ---@type YaTreeNode
      tree.current_node = node_or_path
    elseif type(node_or_path) == "string" then
      local node = tree.root:expand({ to = node_or_path })
      if node then
        node:expand()
        tree.current_node = node
      end
    else
      log.error("the node_or_path parameter is of an unsupported type %q", type(node_or_path))
    end

    vim.schedule(function()
      ui.update(tree.root, tree.current_node)
      tree.refreshing = false
    end)
  end, nil)
end

---@param node YaTreeNode
function M.refresh(node)
  refresh_current_tree(node)
end

---@param path string
function M.refresh_and_navigate(path)
  refresh_current_tree(path)
end

---@param node YaTreeNode
function M.rescan_dir_for_git(node)
  local tree = Tree.get_tree()
  if not config.git.enable or not tree or not node then
    return
  end
  log.debug("checking if %s is in a git repository", node.path)

  tree.current_node = node
  if not node:is_directory() then
    node = node.parent
  end
  async.run(function()
    if node:check_for_git_repo() then
      if config.git.watch_git_dir then
        attach_git_change_listener(tree, node.repo)
      end

      vim.schedule(function()
        ui.update(tree.root, tree.current_node)
      end)
    end
  end, nil)
end

---@param node YaTreeNode
---@param term string
---@param search_result string[]
---@param focus_node boolean
function M.display_search_result(node, term, search_result, focus_node)
  local tree = Tree.get_tree()
  if not tree or not node then
    return
  end

  -- store the current tree only once, before the search is done
  if not ui.is_search_open() then
    tree.tree.root = tree.root
    tree.tree.current_node = ui.get_current_node()
  end

  async.run(function()
    tree.search.result, tree.search.current_node = node:create_search_tree(search_result)
    tree.search.result.search_term = term
    tree.root = tree.search.result
    tree.current_node = tree.search.current_node

    vim.schedule(function()
      ui.open_search(tree.search.result, focus_node and tree.search.current_node)
    end)
  end, nil)
end

function M.focus_first_search_result()
  local tree = Tree.get_tree()
  if tree and tree.search.current_node then
    ui.focus_node(tree.search.current_node)
  end
end

function M.clear_search()
  local tree = Tree.get_tree()
  if not tree then
    return
  end

  tree.search.result = nil
  tree.search.current_node = nil
  tree.root = tree.tree.root
  tree.current_node = tree.tree.current_node
  ui.close_search(tree.root, tree.current_node)
end

function M.open_help()
  ui.open_help()
end

---@param node YaTreeNode
function M.system_open(node)
  if not node then
    return
  end

  if not config.system_open.cmd then
    utils.warn("No sytem open command set, or OS cannot be recognized!")
    return
  end

  local args = vim.deepcopy(config.system_open.args)
  table.insert(args, node.link_to or node.path)
  job.run({ cmd = config.system_open.cmd, args = args, detached = true }, function(code, _, stderr)
    if code ~= 0 then
      vim.schedule(function()
        stderr = vim.split(stderr or "", "\n", { plain = true, trimempty = true })
        stderr = table.concat(stderr, " ")
        utils.warn(string.format("%q returned error code %q and message %q", config.system_open.cmd, code, stderr))
      end)
    end
  end)
end

---@param bufnr number
local function on_win_leave(bufnr)
  ui.on_win_leave(bufnr)
end

local function on_color_scheme()
  ui.setup_highlights()
  M.redraw()
end

local function on_tab_new_entered()
  M.open({ focus = config.auto_open.focus_tree })
end

local function on_tab_enter()
  M.redraw()
end

---@param tabpage number
local function on_tab_closed(tabpage)
  local tree = Tree.get_tree(tabpage)
  if tree then
    for repo, watcher_id in pairs(tree.git_watchers) do
      repo:remove_git_change_listener(watcher_id)
    end
    Tree.delete_tree(tabpage)
  end
  ui.delete_ui(tabpage)
end

---@param file string
---@param bufnr number
local function on_buf_enter(file, bufnr)
  if ui.is_buffer_yatree(bufnr) then
    return
  end

  -- this event might be called multiple times, in succession, for the same buffer,
  -- use a buffer variable to keep track of it
  local ok, value = pcall(api.nvim_buf_get_var, bufnr, "YaTree_on_buf_new_file")
  if ok and value == 1 then
    return
  end

  local tree = Tree.get_tree()
  api.nvim_buf_set_var(bufnr, "YaTree_on_buf_new_file", 1)

  async.run(function()
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

      file = Path:new(file):absolute()
      if not tree then
        log.debug("no tree for current tab")
        ---@type string
        local cwd = uv.cwd()
        if file:find(cwd, 1, true) then
          log.debug("requested directory is a subpath of the current cwd %q, opening tree with root at cwd", cwd)
          ---@type YaTree
          tree = Tree.get_or_create_tree()
        else
          log.debug("requested directory is not a subpath of the current cwd %q, opening tree with root of the requested path", cwd)
          ---@type YaTree
          tree = Tree.get_or_create_tree({ root_path = file })
        end

        if tree.root.repo and config.git.watch_git_dir then
          tree.root.repo:add_git_change_listener(on_git_change)
        end
      elseif not tree.root:is_ancestor_of(file) and tree.root.path ~= file then
        log.debug("the current tree is not a parent for directory %s", file)
        update_tree_root_node(tree, file)
      else
        log.debug("current tree is parent of directory %s", file)
      end

      M.open({ tree = tree, focus = true, file = file })
    else
      -- only update the ui iff highlighting of open files is enabled and
      -- the necessary config options are set
      local update_ui = false
      if tree and ui.is_current_window_ui() and config.move_buffers_from_tree_window then
        log.debug("moving buffer %s to edit window", bufnr)
        ui.move_buffer_to_edit_window(bufnr)
        update_ui = ui.is_highlight_open_file_enabled()
      end
      if tree and ui.is_open() and not ui.is_search_open() then
        if config.follow_focused_file then
          tree.current_node = tree.root:expand({ to = file })
          ui.update(tree.root, tree.current_node, { focus_node = true })
          -- avoid updating twice
          update_ui = false
        else
          update_ui = ui.is_highlight_open_file_enabled()
        end
      end

      if tree and update_ui then
        ui.update(tree.root)
      end

      ok, value = pcall(api.nvim_buf_del_var, bufnr, "YaTree_on_buf_new_file")
      if not ok then
        log.error("couldn't delete YaTree_on_buf_new_file var on buffer %s, file %s, message=%q", bufnr, file, value)
      end
    end
  end, nil)
end

---@param file string
---@param bufnr number
local function on_buf_delete(file, bufnr)
  if not ui.is_open() or not file or file == "" or ui.is_buffer_yatree(bufnr) then
    return
  end

  local tree = Tree.get_tree()
  if not tree or not tree.root:is_ancestor_of(file) then
    return
  end

  -- defer the ui update since the BufDelete event is called _before_ the buffer is deleted
  vim.defer_fn(function()
    ui.update(tree.root)
  end, 50)
end

---@param closed_winid number
local function on_win_closed(closed_winid)
  -- if the closed window was a floating window, do nothing.
  -- otherwise we will quit from a hijacked netrw buffer when using
  -- any form of popup, including command mode
  if ui.is_window_floating(closed_winid) or not ui.is_open() then
    return
  end

  -- defer until the window in question has closed, so that
  -- we can check only the remaining windows
  vim.defer_fn(function()
    if #api.nvim_list_wins() == 1 and vim.bo.filetype == "YaTree" then
      -- check that there are no buffers with unsaved modifications,
      -- if so, just return
      for _, bufnr in ipairs(api.nvim_list_bufs()) do
        if api.nvim_buf_is_valid(bufnr) and api.nvim_buf_is_loaded(bufnr) and api.nvim_buf_get_option(bufnr, "modified") then
          return
        end
      end
      api.nvim_command(":silent q!")
    end
  end, 50)
end

---@param file string
local function on_buf_write_post(file)
  if file then
    ---@type number
    local tabpage = api.nvim_get_current_tabpage()

    async.run(function()
      Tree.for_each_tree(function(tree)
        if tree.root:is_ancestor_of(file) then
          log.debug("changed file %q is in tree %q and tab %s", file, tree.root.path, tree.tabpage)

          local node = tree.root:get_child_if_loaded(file)
          if node then
            node:refresh({ refresh_git = config.git.enable })

            -- only update the ui if the tree is for the current tabpage
            if tree.tabpage == tabpage then
              vim.schedule(function()
                ui.update(tree.root)
              end)
            end
          end
        end
      end)
    end, nil)
  end
end

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

local function on_diagnostics_changed()
  ---@type table<string, number>
  local diagnostics = {}
  for _, diagnostic in ipairs(vim.diagnostic.get()) do
    local bufnr = diagnostic.bufnr
    if api.nvim_buf_is_valid(bufnr) then
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
      ---@type string
      for _, parent in next, Path:new(path):parents() do
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
    local diagnostics_count = vim.tbl_count(diagnostics)
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
  local group = api.nvim_create_augroup("YaTree", { clear = true })

  api.nvim_create_autocmd("WinLeave", {
    group = group,
    pattern = "*",
    callback = function(input)
      on_win_leave(input.buf)
    end,
    desc = "Keeping track of which window to open buffers in",
  })
  api.nvim_create_autocmd("ColorScheme", {
    group = group,
    pattern = "*",
    callback = function()
      on_color_scheme()
    end,
    desc = "Updating highlights",
  })

  if config.auto_open.on_new_tab then
    api.nvim_create_autocmd("TabNewEntered", {
      group = group,
      pattern = "*",
      callback = function()
        on_tab_new_entered()
      end,
      desc = "Opening the tree on new tabs",
    })
  end
  api.nvim_create_autocmd("TabEnter", {
    group = group,
    pattern = "*",
    callback = function()
      on_tab_enter()
    end,
    desc = "Redraw the tree when switching tabs",
  })
  api.nvim_create_autocmd("TabClosed", {
    group = group,
    pattern = "*",
    callback = function(input)
      on_tab_closed(tonumber(input.match))
    end,
    desc = "Remove tab-specific tree",
  })

  local highlight_open_file = ui.is_highlight_open_file_enabled()
  if config.follow_focused_file or config.replace_netrw or config.move_buffers_from_tree_window or highlight_open_file then
    api.nvim_create_autocmd({ "BufEnter", "BufNewFile" }, {
      group = group,
      pattern = "*",
      callback = function(input)
        on_buf_enter(input.file, input.buf)
      end,
      desc = "Current file highlighting in tree, and directory buffers handling",
    })
  end
  if ui.is_highlight_open_file_enabled() then
    api.nvim_create_autocmd("BufDelete", {
      group = group,
      pattern = "*",
      callback = function(input)
        on_buf_delete(input.file, input.buf)
      end,
      desc = "Current file highlighting in the tree",
    })
  end

  if config.auto_close then
    api.nvim_create_autocmd("WinClosed", {
      group = group,
      pattern = "*",
      callback = function(input)
        on_win_closed(tonumber(input.match))
      end,
      desc = "Close Neovim when the tree is the last window",
    })
  end
  if config.auto_reload_on_write then
    api.nvim_create_autocmd("BufWritePost", {
      group = group,
      pattern = "*",
      callback = function(input)
        on_buf_write_post(input.file)
      end,
      desc = "Reload tree on buffer writes",
    })
  end
  if config.cwd.follow then
    api.nvim_create_autocmd("DirChanged", {
      group = group,
      pattern = "*",
      callback = function(input)
        -- currently not available in the table passed to the callback
        ---@type boolean
        local window_change = vim.v.event.changed_window
        on_dir_changed(input.match, input.file, window_change)
      end,
      desc = "Update tree root when the current cwd changes",
    })
  end
  if config.diagnostics.enable then
    api.nvim_create_autocmd("DiagnosticChanged", {
      group = group,
      pattern = "*",
      callback = debounce_trailing(on_diagnostics_changed, config.diagnostics.debounce_time),
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

  ---@type number
  local tabpage = api.nvim_get_current_tabpage()
  async.run(function()
    local tree = Tree.get_or_create_tree({ tabpage = tabpage, root_path = root_path })
    if tree.root.repo and config.git.watch_git_dir then
      attach_git_change_listener(tree, tree.root.repo)
    end

    vim.schedule(function()
      if is_directory or config.auto_open.on_setup then
        local focus = config.auto_open.on_setup and config.auto_open.focus_tree
        M.open({ tree = tree, hijack_buffer = is_directory, focus = focus })
      end

      -- the autocmds must be set up last, this avoids triggering the BufNewFile event,
      -- if the initial buffer is a directory
      setup_autocommands()

      setting_up = false
    end)
  end, nil)
end

return M
