local async = require("plenary.async")
local Path = require("plenary.path")

local config = require("ya-tree.config").config
local Tree = require("ya-tree.tree")
local Nodes = require("ya-tree.nodes")
local job = require("ya-tree.job")
local git = require("ya-tree.git")
local debounce_trailing = require("ya-tree.debounce").debounce_trailing
local ui = require("ya-tree.ui")
local utils = require("ya-tree.utils")
local log = require("ya-tree.log")

local api = vim.api
local fn = vim.fn
local uv = vim.loop

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

---@return string|nil buffer_path #the path fo the current buffer
local function get_current_buffer_path()
  local bufname = fn.bufname()
  local file = fn.fnamemodify(bufname, ":p")
  log.debug("current buffer file is %s, bufname is %s", file, bufname)

  return utils.is_readable_file(file) and file
end

--- Resolves the `path` in the speicfied `tree`. If `path` is `nil`, instead resolves the path of the current buffer.
---@param tree YaTree
---@param path? string
---@return string|nil path #the fully resolved path, or `nil`
local function resolve_path(tree, path)
  if not path or path == "" then
    path = get_current_buffer_path()
  end
  if path and not vim.startswith(path, utils.os_root()) then
    -- a relative path is relative to the current cwd, not the tree's root node
    path = Path:new({ tree.cwd, path }):absolute()
    log.debug("expanded cwd relative path to %s", path)
  end

  if path and path:find(tree.root.path, 1, true) then
    -- the path is located in the tree
    return path
  end
end

---@param opts {tree?: YaTree, file?: string, hijack_buffer?: boolean, focus?: boolean}
---  - {opts.tree?} `YaTree`
---  - {opts.file?} `string`
---  - {opts.hijack_buffer?} `boolean`
---  - {opts.focus?} `boolean`
function M.open(opts)
  async.run(function()
    opts = opts or {}
    ---@type YaTree
    local tree = opts.tree or Tree.get_tree({ create_if_missing = true })

    ---@type string
    local file
    if opts.file then
      file = resolve_path(tree, opts.file)
      log.debug("navigating to %q", file)
    elseif config.follow_focused_file then
      file = resolve_path(tree)
    end

    tree.current_node = file and tree.root:expand({ to = file }) or (ui.is_open() and ui.get_current_node())

    vim.schedule(function()
      ui.open(tree.root, { hijack_buffer = opts.hijack_buffer, focus = opts.focus }, tree.current_node)
    end)
  end)
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

function M.focus()
  M.open({ focus = true })
end

function M.redraw()
  log.debug("redrawing tree")

  local tree = Tree.get_tree()
  if tree and ui.is_open() then
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
  end)
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

  ui.update(tree.root)
end

function M.close_all_nodes()
  local tree = Tree.get_tree()
  if tree then
    tree.root:collapse({ recursive = true, children_only = true })
    tree.current_node = tree.root
    ui.update(tree.root, tree.current_node)
  end
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

  if config.cwd.update_from_tree then
    vim.cmd("tcd " .. fn.fnameescape(node.path))
  else
    M.change_root_node(tree, node)
  end
end

---@param node YaTreeNode
function M.cd_up(node)
  local tree = Tree.get_tree()
  if not tree or not node or not node:is_directory() then
    return
  end
  local new_cwd = tree.root.parent and tree.root.parent.path or Path:new(tree.root.path):parent().filename
  log.debug("changing root directory one level up from %q to %q", tree.root.path, new_cwd)

  -- save current position
  tree.current_node = node

  if config.cwd.update_from_tree then
    vim.cmd("tcd " .. fn.fnameescape(new_cwd))
  else
    M.change_root_node(tree, tree.root.parent or new_cwd)
  end
end

---@param tree YaTree
---@param new_root string|YaTreeNode
function M.change_root_node(tree, new_root)
  log.debug("changing root node to %q", tostring(new_root))

  async.run(function()
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
      end
    else
      if tree.root.path ~= new_root.path then
        ---@type YaTreeNode
        tree.root = new_root
        tree.root:expand({ force_scan = true })
      end
    end

    vim.schedule(function()
      ui.update(tree.root, tree.current_node, { tabpage = tree.tabpage })
    end)
  end)
end

---@param node YaTreeNode
function M.parent_node(node)
  -- bail if the node is the current root node
  local tree = Tree.get_tree()
  if not tree or not node or tree.root == node then
    return
  end

  node = node.parent
  ui.focus_node(node)
end

---@param node YaTreeNode
function M.prev_sibling(node)
  if not node then
    return
  end

  ui.focus_prev_sibling()
end

---@param node YaTreeNode
function M.next_sibling(node)
  if not node then
    return
  end

  ui.focus_next_sibling()
end

---@param node YaTreeNode
function M.first_sibling(node)
  if not node then
    return
  end

  ui.focus_first_sibling()
end

---@param node YaTreeNode
function M.last_sibling(node)
  if not node then
    return
  end

  ui.focus_last_sibling()
end

---@param node YaTreeNode
function M.toggle_ignored(node)
  local tree = Tree.get_tree()
  if not tree or not node then
    return
  end
  log.debug("toggling ignored")

  tree.current_node = node
  config.git.show_ignored = not config.git.show_ignored
  ui.update(tree.root, tree.current_node)
end

---@param node YaTreeNode
function M.toggle_filter(node)
  local tree = Tree.get_tree()
  if not tree or not node then
    return
  end
  log.debug("toggling filter")

  tree.current_node = node
  config.filters.enable = not config.filters.enable
  ui.update(tree.root, tree.current_node)
end

do
  local refreshing = false

  ---@param tree YaTree
  ---@param node_or_path YaTreeNode|string
  local function refresh_tree(tree, node_or_path)
    log.debug("refreshing current tree")
    if refreshing or vim.v.exiting ~= vim.NIL then
      log.debug("refresh already in progress or vim is exiting, aborting refresh")
      return
    end
    refreshing = true

    async.run(function()
      tree.root:refresh()

      if type(node_or_path) == "table" then
        ---@type YaTreeNode
        tree.current_node = node_or_path
      elseif type(node_or_path) == "string" then
        local node = tree.root:expand({ to = node_or_path })
        if node then
          node:expand()
          tree.current_node = node
        end
      end

      vim.schedule(function()
        ui.update(tree.root, tree.current_node, { tabpage = tree.tabpage })
        refreshing = false
      end)
    end)
  end

  ---@param node YaTreeNode
  function M.refresh(node)
    local tree = Tree.get_tree()
    if tree then
      refresh_tree(tree, node)
    end
  end

  ---@param path string
  function M.refresh_and_navigate(path)
    local tree = Tree.get_tree()
    if tree then
      tree.current_node = ui.is_open() and ui.get_current_node() or tree.current_node
      refresh_tree(tree, path)
    end
  end

  function M.refresh_git()
    log.debug("refreshing git repositories")
    if refreshing or vim.v.exiting ~= vim.NIL then
      log.debug("refresh already in progress or vim is exiting, aborting refresh")
      return
    end
    refreshing = true

    local tree = Tree.get_tree()
    tree.current_node = ui.get_current_node()

    async.run(function()
      for _, repo in pairs(git.repos) do
        if repo then
          repo:refresh_status({ ignored = true })
        end
      end

      if tree then
        vim.schedule(function()
          ui.update(tree.root, tree.current_node, { tabpage = tree.tabpage })
        end)
      end
      refreshing = false
    end)
  end
end

---@param node YaTreeNode
function M.rescan_dir_for_git(node)
  local tree = Tree.get_tree()
  if not tree or not node then
    return
  end
  log.debug("checking if %s is in a git repository", node.path)

  tree.current_node = node
  if not node:is_directory() then
    node = node.parent
  end
  async.run(function()
    node:check_for_git_repo()

    vim.schedule(function()
      ui.update(tree.root, tree.current_node)
    end)
  end)
end

---@param node YaTreeNode
---@param term string
---@param search_result string[]
function M.display_search_result(node, term, search_result)
  local tree = Tree.get_tree()
  if not tree or not node then
    return
  end

  -- store the current node only once, before the search is done
  if not ui.is_search_open() then
    tree.current_node = ui.get_current_node()
  end

  tree.search.result, tree.search.current_node = node:create_search_tree(search_result)
  tree.search.result.search_term = term

  vim.schedule(function()
    ui.open_search(tree.search.result)
  end)
end

function M.focus_first_search_result()
  local tree = Tree.get_tree()
  if not tree then
    return
  end

  if tree.search.result and tree.search.current_node then
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
  ui.close_search(tree.root, tree.current_node)
end

---@param node YaTreeNode
function M.toggle_help(node)
  local tree = Tree.get_tree()
  if not tree then
    return
  end

  ---@type YaTreeNode|YaTreeSearchNode
  local root, current_node
  if ui.is_search_open() then
    root = tree.search.result
    current_node = ui.is_help_open() and tree.search.current_node or node
    tree.search.current_node = current_node
  else
    root = tree.root
    current_node = ui.is_help_open() and tree.current_node or node
    tree.current_node = current_node
  end
  ui.toggle_help(root, current_node)
end

---@param node YaTreeNode
function M.system_open(node)
  if not node then
    return
  end

  if not config.system_open.cmd then
    utils.print_error("No sytem open command set, or OS cannot be recognized!")
    return
  end

  local args = vim.deepcopy(config.system_open.args)
  table.insert(args, node.link_to or node.path)
  job.run({ cmd = config.system_open.cmd, args = args, detached = true }, function(code, _, error)
    if code ~= 0 then
      vim.schedule(function()
        utils.print_error(string.format("%q returned error code %q and message %q", config.system_open.cmd, code, error))
      end)
    end
  end)
end

---@param bufnr number
function M.on_win_leave(bufnr)
  if not Tree.get_tree() then
    return
  end

  ui.on_win_leave(bufnr)
end

function M.on_color_scheme()
  ui.setup_highlights()
end

function M.on_tab_enter()
  M.redraw()
end

---@param tabpage number
function M.on_tab_closed(tabpage)
  Tree.delete_tree(tabpage)
  ui.delete_tab(tabpage)
end

---@param file string
---@param bufnr number
function M.on_buf_new_file(file, bufnr)
  if not file or file == "" or ui.is_buffer_yatree(bufnr) then
    return
  end

  if not (config.follow_focused_file or config.replace_netrw or config.move_buffers_from_tree_window) then
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
    local is_directory, path = M.get_path_from_directory_buffer()
    if is_directory and config.replace_netrw then
      if ui.is_current_window_ui() then
        ui.restore()
      else
        -- switch back to the previous buffer so the window isn't closed
        vim.cmd("bprevious")
      end
      log.debug("deleting buffer %s with file %s and path %s", bufnr, file, path)
      api.nvim_buf_delete(bufnr, { force = true })
      -- force barbar update, otherwise a ghost tab for the buffer can remain
      if fn.exists("bufferline#update") == 1 then
        vim.cmd("call bufferline#update()")
      end

      if not tree then
        log.debug("no tree for current tab")
        tree = Tree.get_tree({ root_path = path })
        vim.schedule(function()
          M.focus()
        end)
      elseif not tree.root:is_ancestor_of(path) and tree.root.path ~= path then
        log.debug("the current tree is not a parent for directory %s", path)
        M.change_root_node(tree, path)
        vim.schedule(function()
          M.focus()
        end)
      else
        log.debug("current tree is parent of directory %s", path)
        tree.current_node = tree.root:expand({ to = path })
        ui.update(tree.root, tree.current_node, { focus_node = true })
        M.focus()
      end
    else
      if tree and ui.is_current_window_ui() and config.move_buffers_from_tree_window then
        log.debug("moving buffer %s to edit window", bufnr)
        ui.move_buffer_to_edit_window(bufnr, tree.root)
      end
      if config.follow_focused_file and ui.is_open() and not (ui.is_help_open() or ui.is_search_open()) then
        tree.current_node = tree.root:expand({ to = file })
        ui.update(tree.root, tree.current_node, { focus_node = true })
      end

      ok = pcall(api.nvim_buf_del_var, bufnr, "YaTree_on_buf_new_file")
      if not ok then
        log.error("couldn't delete YaTree_on_buf_new_file var on buffer %s, file %s", bufnr, file)
      end
    end
  end)
end

---@param closed_winid number
function M.on_win_closed(closed_winid)
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
      api.nvim_command(":silent q!")
    end
  end, 50)
end

---@param file string
function M.on_buf_write_post(file)
  if file then
    async.run(function()
      Tree.for_each_tree(function(tree)
        if tree.root:is_ancestor_of(file) then
          log.debug("changed file %q is in tree %q and tab %s", file, tree.root.path, tree.tabpage)

          local parent_path = Path:new(file):parent():absolute()
          local node = tree.root:get_child_if_loaded(parent_path)
          if node then
            node:refresh()

            vim.schedule(function()
              ui.update(tree.root, nil, { tabpage = tree.tabpage })
            end)
          end
        end
      end)
    end)
  end
end

function M.on_cursor_moved()
  if not ui.is_open() then
    return
  end

  ui.move_cursor_to_name()
end

function M.on_dir_changed()
  ---@type boolean
  local window_change = vim.v.event.changed_window
  if window_change then
    return
  end

  ---@type string
  local new_cwd = vim.v.event.cwd
  -- the documentation of DirChanged is incorrent it seems, the scope is not 'tab' but 'tabpage'
  ---@type "'global'"|"'tabpage'"|"'window'"
  local scope = vim.v.event.scope
  log.debug("event.scope=%s, event.changed_window=%s, event.cwd=%s", scope, window_change, new_cwd)

  if scope == "tabpage" then
    local tree = Tree.get_tree()
    -- since DirChanged is only subscribed to if conif.cwd.follow is enabled,
    -- the tree.cwd is always bound to the tab cwd, and the root path of the
    -- tree doens't have to be checked
    if not tree or new_cwd == tree.cwd then
      return
    end

    tree.current_node = ui.is_open() and ui.get_current_node() or tree.current_node
    tree.cwd = new_cwd
    M.change_root_node(tree, new_cwd)
  elseif scope == "global" then
    Tree.for_each_tree(function(tree)
      if new_cwd ~= tree.cwd then
        tree.cwd = new_cwd
        M.change_root_node(tree, new_cwd)
      end
    end)
  end
end

function M.on_git_event()
  M.refresh_git()
end

M.on_diagnostics_changed = debounce_trailing(function()
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
      for _, parent in next, Path:new(path):parents() do
        local parent_severity = diagnostics[parent]
        if not parent_severity or parent_severity > severity then
          diagnostics[parent] = severity
        end
      end
    end
  end
  Nodes.set_diagnostics(diagnostics)

  Tree.for_each_tree(function(tree)
    if not ui.is_help_open(tree.tabpage) then
      if ui.is_search_open(tree.tabpage) then
        ui.update(tree.search.result, nil, { tabpage = tree.tabpage })
      elseif ui.is_open(tree.tabpage) then
        ui.update(tree.root, nil, { tabpage = tree.tabpage })
      end
    end
  end)
end, config.diagnostics.debounce_time)

---@return boolean is_directory, string? path
function M.get_path_from_directory_buffer()
  local bufnr = api.nvim_get_current_buf()
  local bufname = api.nvim_buf_get_name(bufnr)
  local stat = uv.fs_stat(bufname)
  if not stat or stat.type ~= "directory" then
    return false
  end
  local buftype = api.nvim_buf_get_option(bufnr, "filetype")
  if buftype ~= "" then
    return false
  end

  log.debug("buffer %s (%s) is buftype %s and stat.type %s", bufnr, bufname, buftype, stat.type)
  local lines = api.nvim_buf_get_lines(bufnr, 0, -1, false)
  if #lines == 0 or (#lines == 1 and lines[1] == "") then
    return true, fn.expand(bufname)
  else
    return false
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
  vim.cmd("augroup YaTree")
  vim.cmd("autocmd!")

  vim.cmd([[autocmd WinLeave * lua require('ya-tree.lib').on_win_leave(vim.fn.expand('<abuf>'))]])
  vim.cmd([[autocmd ColorScheme * lua require('ya-tree.lib').on_color_scheme()]])

  vim.cmd([[autocmd TabEnter * lua require('ya-tree.lib').on_tab_enter()]])
  vim.cmd([[autocmd TabClosed * lua require('ya-tree.lib').on_tab_closed(vim.fn.expand('<afile>'))]])

  vim.cmd([[autocmd BufEnter,BufNewFile * lua require('ya-tree.lib').on_buf_new_file(vim.fn.expand('<afile>:p'), vim.fn.expand('<abuf>'))]])

  if config.auto_close then
    vim.cmd([[autocmd WinClosed * lua require('ya-tree.lib').on_win_closed(vim.fn.expand('<amatch>'))]])
  end
  if config.auto_reload_on_write then
    vim.cmd([[autocmd BufWritePost * lua require('ya-tree.lib').on_buf_write_post(vim.fn.expand('<afile>:p'))]])
  end
  if config.hijack_cursor then
    vim.cmd([[autocmd CursorMoved YaTree* lua require('ya-tree.lib').on_cursor_moved()]])
  end
  if config.cwd.follow then
    vim.cmd([[autocmd DirChanged * lua require('ya-tree.lib').on_dir_changed()]])
  end
  if config.git.enable then
    vim.cmd([[autocmd User FugitiveChanged,NeogitStatusRefreshed lua require('ya-tree.lib').on_git_event()]])
  end
  if config.diagnostics.enable then
    vim.cmd([[autocmd DiagnosticChanged * lua require('ya-tree.lib').on_diagnostics_changed()]])
  end

  vim.cmd("augroup END")
end

function M.setup()
  setup_netrw()

  ---@type boolean, string
  local netrw, root_path
  if config.replace_netrw then
    netrw, root_path = M.get_path_from_directory_buffer()
  end
  if not netrw then
    root_path = uv.cwd()
  end

  async.run(function()
    -- create the tree for the current tabpage
    log.debug("creating tree in lib.setup")
    local tree = Tree.get_tree({ root_path = root_path })
    -- the autocmd must be set up last, this avoids triggering the BufNewFile event if the initial buffer
    -- is a directory
    if netrw then
      vim.schedule(function()
        M.open({ tree = tree, hijack_buffer = true })
        setup_autocommands()
      end)
    else
      vim.schedule(function()
        setup_autocommands()
      end)
    end
  end)
end

return M
