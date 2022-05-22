local async = require("plenary.async")
local scheduler = require("plenary.async.util").scheduler
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
  return Tree.get_tree().root.path == node.path
end

---@return string root_path
function M.get_root_node_path()
  return Tree.get_tree().root.path
end

--- Resolves the `path` in the speicfied `tree`.
---@param tree YaTree
---@param path string
---@return string|nil path #the fully resolved path, or `nil`
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
---@param repo GitRepo
---@param watcher_id number
---@param fs_changes boolean
function M.on_git_change(repo, watcher_id, fs_changes)
  if vim.v.exiting ~= vim.NIL then
    return
  end
  log.debug("git repo %s changed", tostring(repo))

  ---@type number
  local tabpage = api.nvim_get_current_tabpage()
  async.void(function()
    Tree.for_each_tree(function(tree)
      if tree.git_watchers[repo] == watcher_id then
        if fs_changes then
          tree.root:refresh({ recurse = true })
        end
        scheduler()
        if tabpage == tree.tabpage and ui.is_open() then
          tree.current_node = ui.get_current_node()
          ui.update(tree.root, tree.current_node)
        end
      end
    end)
  end)()
end

---@param opts? {file?: string, switch_root?: boolean, focus?: boolean}
---  - {opts.file?} `string`
---  - {opts.switch_root?} `boolean`
---  - {opts.focus?} `boolean`
function M.open_tree(opts)
  if setting_up then
    log.debug("setup is in progress, deferring opening window...")
    vim.defer_fn(function()
      M.open_tree(opts)
    end, 100)
    return
  end

  async.void(function()
    opts = opts or {}
    log.debug("opening tree with %s", opts)
    scheduler()
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
        tree = Tree.get_or_create_tree({ root_path = cwd })
      end
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
          local should_display, reason = utils.should_display_node(node, config)
          if not should_display and reason then
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
    end

    scheduler()
    tree.current_node = node or (ui.is_open() and ui.get_current_node())
    ui.open(tree.root, tree.current_node, { focus = opts.focus })

    if issue_tcd then
      log.debug("issueing tcd autocmd to %q", tree.cwd)
      vim.cmd("tcd " .. fn.fnameescape(tree.cwd))
    end
  end)()
end

function M.close_tree()
  ui.close()
end

function M.toggle_tree()
  if ui.is_open() then
    M.close_tree()
  else
    M.open_tree()
  end
end

function M.redraw()
  local tree = Tree.get_tree()
  if tree then
    log.debug("redrawing tree")
    ui.update(tree.root)
  end
end

---@param node YaTreeNode
function M.toggle_directory(node)
  local tree = Tree.get_tree()
  if not node:is_directory() or tree.root == node then
    return
  end

  async.void(function()
    if node.expanded then
      node:collapse()
    else
      node:expand()
    end

    scheduler()
    ui.update(tree.root)
  end)()
end

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

function M.close_all_nodes()
  local tree = Tree.get_tree()
  tree.root:collapse({ recursive = true, children_only = true })
  tree.current_node = tree.root
  ui.update(tree.root, tree.current_node)
end

---@param tree YaTree
---@param current_node YaTreeNode
local function close_search(tree, current_node)
  -- save the current node in the search tree
  tree.search.current_node = current_node
  tree.root = tree.tree.root
  tree.current_node = tree.tree.current_node
  ui.close_search(tree.root, tree.current_node)
end

---@param tree YaTree
---@param new_root string|YaTreeNode
local function change_root_node_for_tree(tree, new_root)
  log.debug("changing root node to %q", tostring(new_root))

  ---@type number
  local tabpage = api.nvim_get_current_tabpage()
  async.void(function()
    tree.root = tree.tree.root
    tree = Tree.update_tree_root_node(tree, new_root)

    if tree.tabpage == tabpage then
      scheduler()
      if ui.is_search_open() then
        close_search(tree, ui.get_current_node())
      elseif ui.is_buffers_open() then
        ui.close_buffers(tree.root, tree.current_node)
      else
        ui.update(tree.root, tree.current_node)
      end
    end
  end)()
end

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

---@param tree YaTree
local function open_buffers(tree)
  ---@type string[]
  local paths = {}
  for _, bufnr in ipairs(api.nvim_list_bufs()) do
    if api.nvim_buf_is_valid(bufnr) and api.nvim_buf_is_loaded(bufnr) and fn.buflisted(bufnr) == 1 then
      ---@type string
      local path = api.nvim_buf_get_name(bufnr)
      if path ~= "" then
        paths[#paths + 1] = path
      end
    end
  end

  async.void(function()
    ---@type string
    local root_path
    if #paths == 0 then
      root_path = tree.tree.root.path
    elseif #paths == 1 then
      root_path = Path:new(paths[1]):parent().filename
    else
      root_path = utils.find_common_ancestor(paths) or tree.tree.root.path
    end
    if tree.tree.root:is_ancestor_of(root_path) then
      root_path = tree.tree.root.path
    end
    tree.root, tree.current_node = Nodes.create_tree_from_paths(root_path, paths)

    scheduler()
    ui.open_buffers(tree.root, tree.current_node)
  end)()
end

---@param tree YaTree
---@param node_or_path YaTreeNode|string
local function refresh_tree(tree, node_or_path)
  if tree.refreshing or vim.v.exiting ~= vim.NIL then
    log.debug("refresh already in progress or vim is exiting, aborting refresh")
    return
  end
  log.debug("refreshing current tree")
  tree.refreshing = true

  async.void(function()
    tree.root:refresh({ recurse = true, refresh_git = config.git.enable })

    if type(node_or_path) == "table" then
      ---@cast node_or_path YaTreeNode
      tree.current_node = node_or_path
    elseif type(node_or_path) == "string" then
      local node = tree.root:expand({ to = node_or_path })
      if node then
        tree.current_node = node
      end
    else
      log.error("the node_or_path parameter is of an unsupported type %q", type(node_or_path))
    end

    scheduler()
    ui.update(tree.root, tree.current_node)
    tree.refreshing = false
  end)()
end

---@param node_or_path YaTreeNode|string
function M.refresh_tree(node_or_path)
  local tree = Tree.get_tree()
  if ui.is_buffers_open() then
    open_buffers(tree)
  elseif ui.is_search_open() then
    M.search(tree.root, tree.root.search_term, false)
  else
    refresh_tree(tree, node_or_path)
  end
end

---@param node YaTreeNode
function M.rescan_dir_for_git(node)
  if not config.git.enable then
    return
  end
  local tree = Tree.get_tree()
  log.debug("checking if %s is in a git repository", node.path)

  tree.current_node = node
  if not node:is_directory() then
    node = node.parent
  end
  async.void(function()
    if node:check_for_git_repo() then
      Tree.attach_git_watcher(tree, node.repo)
      scheduler()
      ui.update(tree.root, tree.current_node)
    end
  end)()
end

do
  ---@type boolean
  local fd_has_max_results
  ---@type boolean
  local fdfind_has_max_results
  do
    ---@param cmd string
    ---@return boolean
    local function has_max_results(cmd)
      local test = fn.system(cmd .. " this_is_only_a_test_search --max-depth=1 --max-results=1")
      return not test:match("^error:")
    end

    fd_has_max_results = fn.executable("fd") == 1 and has_max_results("fd")
    fdfind_has_max_results = fn.executable("fdfind") == 1 and has_max_results("fdfind")
  end

  ---@param term string
  ---@param path string
  ---@return string? cmd, string[] arguments
  local function build_search(term, path)
    local cmd = config.search.cmd

    ---@type string[]
    local args
    if type(config.search.args) == "function" then
      args = config.search.args(cmd, term, path, config)
    else
      if cmd == "fd" or cmd == "fdfind" then
        args = { "--color=never", "-tf", "-td", "-tl" }
        if not config.filters.enable or not config.filters.dotfiles then
          table.insert(args, "--hidden")
        end
        if config.filters.enable then
          for name, _ in pairs(config.filters.custom) do
            table.insert(args, "--exclude")
            table.insert(args, name)
          end
        end
        if config.git.show_ignored then
          table.insert(args, "--no-ignore")
        end
        if (fd_has_max_results or fdfind_has_max_results) and config.search.max_results > 0 then
          table.insert(args, "--max-results=" .. config.search.max_results)
        end
        table.insert(args, "--glob")
        table.insert(args, term)
        table.insert(args, path)
      elseif cmd == "find" then
        args = { path, "-type", "f,d,l" }
        if config.filters.enable and config.filters.dotfiles then
          table.insert(args, "-not")
          table.insert(args, "-path")
          table.insert(args, "*/.*")
        end
        table.insert(args, "-iname")
        table.insert(args, term)
      elseif cmd == "where" then
        args = { "/r", path, term }
      else
        -- no search command available
        return
      end

      if type(config.search.args) == "table" then
        for _, arg in ipairs(config.search.args) do
          table.insert(args, arg)
        end
      end
    end

    return cmd, args
  end

  ---@param node YaTreeNode
  ---@param term string
  ---@param search_result string[]
  ---@param focus_node boolean
  local function display_search_result(node, term, search_result, focus_node)
    local tree = Tree.get_tree()

    -- store the current tree only once, before the search is done
    if not ui.is_search_open() then
      tree.tree.root = tree.root
      tree.tree.current_node = ui.get_current_node()
    end

    async.void(function()
      local result, first_node = node:create_tree_from_paths(search_result)
      ---@cast result YaTreeSearchNode
      tree.search.result = result
      tree.search.result.search_term = term
      tree.search.current_node = first_node
      tree.root = tree.search.result
      tree.current_node = tree.search.current_node

      scheduler()
      ui.open_search(tree.root, focus_node and tree.current_node or nil)
    end)()
  end

  ---@param node YaTreeNode
  ---@param term string
  ---@param focus_node boolean
  function M.search(node, term, focus_node)
    local search_term = term
    if term ~= "*" and not term:find("*") then
      search_term = "*" .. term .. "*"
    end
    local cmd, args = build_search(search_term, node.path)
    if not cmd then
      utils.warn("No suitable search command found!")
      return
    end

    log.debug("searching for %q in %q", term, node.path)

    job.run({ cmd = cmd, args = args, cwd = node.path, wrap_callback = true }, function(code, stdout, stderr)
      if code == 0 then
        ---@type string[]
        local lines = vim.split(stdout or "", "\n", { plain = true, trimempty = true })
        utils.notify(string.format("%q found %s matches for %q", cmd, #lines, term))
        display_search_result(node, term, lines, focus_node)
      else
        log.error("%q with args %s failed with code %s and message %s", cmd, args, code, stderr)
        utils.warn(string.format("%q failed with code %s and message:\n\n%s", cmd, code, stderr))
      end
    end)
  end
end

function M.focus_first_search_result()
  local tree = Tree.get_tree()
  if tree.search.current_node then
    ui.focus_node(tree.search.current_node)
  end
end

---@param node YaTreeNode
function M.goto_node_in_tree(node)
  local tree = Tree.get_tree()
  tree.root = tree.tree.root
  async.void(function()
    tree.tree.current_node = tree.root:expand({ to = node.path })
    scheduler()
    if ui.is_search_open() then
      close_search(tree, node)
    elseif ui.is_buffers_open() then
      tree.current_node = tree.tree.current_node
      ui.close_buffers(tree.root, tree.current_node)
    end
  end)()
end

function M.close_search(node)
  close_search(Tree.get_tree(), node)
end

function M.show_last_search(node)
  local tree = Tree.get_tree()
  if tree.search.result then
    tree.tree.root = tree.root
    tree.tree.current_node = node
    tree.root = tree.search.result
    tree.current_node = tree.search.current_node

    ui.open_search(tree.search.result, tree.search.current_node)
  end
end

---@param path string
function M.goto_path_in_tree(path)
  local tree = Tree.get_tree()
  local file = resolve_path_in_tree(tree, path)
  if file then
    async.void(function()
      tree.current_node = tree.root:expand({ force_scan = true, to = file })
      scheduler()
      ui.update(tree.root, tree.current_node, { focus_node = true })
    end)()
  end
end

---@param node YaTreeNode
function M.toggle_buffers(node)
  local tree = Tree.get_tree()
  if ui.is_buffers_open() then
    tree.root = tree.tree.root
    tree.current_node = tree.tree.current_node
    ui.close_buffers(tree.root, tree.current_node)
  else
    tree.tree.root = tree.root
    tree.tree.current_node = node
    open_buffers(tree)
  end
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
  M.open_tree({ focus = config.auto_open.focus_tree })
end

local function on_tab_enter()
  M.redraw()
end

---@param tabpage number
local function on_tab_closed(tabpage)
  Tree.delete_tree(tabpage)
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

  async.void(function()
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
      elseif not tree.root:is_ancestor_of(file) and tree.root.path ~= file then
        log.debug("the current tree is not a parent for directory %s", file)
        tree = Tree.update_tree_root_node(tree, file)
      else
        log.debug("current tree is parent of directory %s", file)
      end

      M.open_tree({ focus = true, file = file })
    else
      if tree then
        -- only update the ui iff highlighting of open files is enabled and
        -- the necessary config options are set
        local update_ui = false
        if ui.is_current_window_ui() and config.move_buffers_from_tree_window then
          log.debug("moving buffer %s to edit window", bufnr)
          ui.move_buffer_to_edit_window(bufnr)
          update_ui = ui.is_highlight_open_file_enabled()
        end
        if ui.is_open() then
          if config.follow_focused_file then
            tree.current_node = tree.root:expand({ to = file })
            scheduler()
            ui.update(tree.root, tree.current_node, { focus_node = true })
            -- avoid updating twice
            update_ui = false
          else
            update_ui = ui.is_highlight_open_file_enabled()
          end
        end

        if update_ui then
          scheduler()
          ui.update(tree.root)
        end
      end

      ok, value = pcall(api.nvim_buf_del_var, bufnr, "YaTree_on_buf_new_file")
      if not ok then
        log.error("couldn't delete YaTree_on_buf_new_file var on buffer %s, file %s, message=%q", bufnr, file, value)
      end
    end
  end)()
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

  -- defer until the window in question has closed, so that we can check only the remaining windows
  vim.defer_fn(function()
    if #api.nvim_tabpage_list_wins(0) == 1 and vim.bo.filetype == "YaTree" then
      -- check that there are no buffers with unsaved modifications,
      -- if so, just return
      for _, bufnr in ipairs(api.nvim_list_bufs()) do
        if api.nvim_buf_is_valid(bufnr) and api.nvim_buf_is_loaded(bufnr) and api.nvim_buf_get_option(bufnr, "modified") then
          return
        end
      end
      log.debug("is last window, closing it")
      api.nvim_command(":silent q!")
    end
  end, 50)
end

---@param file string
local function on_buf_write_post(file)
  ---@type number
  local tabpage = api.nvim_get_current_tabpage()
  async.void(function()
    Tree.for_each_tree(function(tree)
      if tree.root:is_ancestor_of(file) then
        log.debug("changed file %q is in tree %q and tab %s", file, tree.root.path, tree.tabpage)

        local node = tree.root:get_child_if_loaded(file)
        if node then
          node:refresh({ refresh_git = config.git.enable })
          scheduler()
          -- only update the ui if the tree is for the current tabpage
          if tree.tabpage == tabpage and ui.is_open() then
            ui.update(tree.root)
          end
        end
      end
    end)
  end)()
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
  local group = api.nvim_create_augroup("YaTree", { clear = true })

  api.nvim_create_autocmd("WinLeave", {
    group = group,
    callback = function(input)
      on_win_leave(input.buf)
    end,
    desc = "Keeping track of which window to open buffers in",
  })
  api.nvim_create_autocmd("ColorScheme", {
    group = group,
    callback = function()
      on_color_scheme()
    end,
    desc = "Updating highlights",
  })

  if config.auto_open.on_new_tab then
    api.nvim_create_autocmd("TabNewEntered", {
      group = group,
      callback = function()
        on_tab_new_entered()
      end,
      desc = "Opening the tree on new tabs",
    })
  end
  api.nvim_create_autocmd("TabEnter", {
    group = group,
    callback = function()
      on_tab_enter()
    end,
    desc = "Redraw the tree when switching tabs",
  })
  api.nvim_create_autocmd("TabClosed", {
    group = group,
    callback = function(input)
      on_tab_closed(tonumber(input.match))
    end,
    desc = "Remove tab-specific tree",
  })

  if config.follow_focused_file or config.replace_netrw or config.move_buffers_from_tree_window or ui.is_highlight_open_file_enabled() then
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
        on_buf_delete(input.match, input.buf)
      end,
      desc = "Current file highlighting in the tree",
    })
  end

  if config.auto_close then
    api.nvim_create_autocmd("WinClosed", {
      group = group,
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
        on_buf_write_post(input.match)
      end,
      desc = "Reload tree on buffer writes",
    })
  end
  if config.cwd.follow then
    api.nvim_create_autocmd("DirChanged", {
      group = group,
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
  async.void(function()
    local tree = Tree.get_or_create_tree({ tabpage = tabpage, root_path = root_path })

    scheduler()
    if is_directory or config.auto_open.on_setup then
      local focus = config.auto_open.on_setup and config.auto_open.focus_tree
      ui.open(tree.root, tree.current_node, { hijack_buffer = is_directory, focus = focus })
    end

    -- the autocmds must be set up last, this avoids triggering the BufNewFile event,
    -- if the initial buffer is a directory
    setup_autocommands()

    setting_up = false
  end)()
end

return M
