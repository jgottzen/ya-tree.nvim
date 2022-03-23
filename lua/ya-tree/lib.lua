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
  local tree = Tree.get_current_tree()
  return tree ~= nil and tree.root.path == node.path
end

---@return string|nil root_path
function M.get_root_node_path()
  local tree = Tree.get_current_tree()
  return tree ~= nil and tree.root.path
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
---  - {opts.tree?} `Tree`
---  - {opts.file?} `string`
---  - {opts.hijack_buffer?} `boolean`
---  - {opts.focus?} `boolean`
function M.open(opts)
  async.run(function()
    opts = opts or {}
    ---@type YaTree
    local tree = opts.tree or Tree.get_current_tree({ create_if_missing = true })

    ---@type string
    local file
    if opts.file then
      file = resolve_path(tree, opts.file)
      log.debug("navigating to %q", file)
    elseif config.follow_focused_file then
      file = resolve_path(tree)
    end

    tree.current_node = file and tree.root:expand({ to = file }) or tree.current_node

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

  local tree = Tree.get_current_tree()
  if tree then
    tree.current_node = M.get_current_node()
    ui.update(tree.root, tree.current_node)
  end
end

---@return YaTreeNode
function M.get_current_node()
  return ui.get_current_node()
end

---@param node YaTreeNode
function M.toggle_directory(node)
  local tree = Tree.get_current_tree()
  if not tree or not node or not node:is_directory() or tree.root == node then
    return
  end

  tree.current_node = node
  async.run(function()
    if node.expanded then
      node:collapse()
    else
      node:expand()
    end

    vim.schedule(function()
      ui.update(tree.root, tree.current_node)
    end)
  end)
end

---@param node YaTreeNode
function M.close_node(node)
  local tree = Tree.get_current_tree()
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

  ui.update(tree.root, node)
end

function M.close_all_nodes()
  local tree = Tree.get_current_tree()
  if tree then
    tree.root:collapse({ recursive = true, children_only = true })
    tree.current_node = tree.root
    ui.update(tree.root, tree.current_node)
  end
end

---@param node YaTreeNode
function M.cd_to(node)
  local tree = Tree.get_current_tree()
  if not tree or not node then
    return
  end
  log.debug("cd to %q", node.path)

  tree.current_node = node

  if config.cwd.update_from_tree then
    vim.cmd("tcd " .. fn.fnameescape(node.path))
  else
    M.change_root_node(tree, node)
  end
end

---@param node YaTreeNode
function M.cd_up(node)
  local tree = Tree.get_current_tree()
  if not tree or not node then
    return
  end
  local new_cwd = vim.fn.fnamemodify(tree.root.path, ":h")
  log.debug("changing root directory one level up from %q to %q", tree.root.path, new_cwd)

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
      ui.update(tree.root, tree.current_node)
    end)
  end)
end

---@param node YaTreeNode
function M.parent_node(node)
  -- bail if the node is the current root node
  local tree = Tree.get_current_tree()
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
  local tree = Tree.get_current_tree()
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
  local tree = Tree.get_current_tree()
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
        ui.update(tree.root, tree.current_node)
        refreshing = false
      end)
    end)
  end

  ---@param node YaTreeNode
  function M.refresh(node)
    local tree = Tree.get_current_tree()
    if tree then
      refresh_tree(tree, node)
    end
  end

  ---@param path string
  function M.refresh_and_navigate(path)
    local tree = Tree.get_current_tree()
    if tree then
      tree.current_node = M.get_current_node()
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

    async.run(function()
      for _, repo in pairs(git.repos) do
        if repo then
          repo:refresh_status({ ignored = true })
        end
      end

      local tree = Tree.get_current_tree()
      if tree then
        vim.schedule(function()
          ui.update(tree.root)
        end)
      end
      refreshing = false
    end)
  end
end

---@param node YaTreeNode
function M.rescan_dir_for_git(node)
  local tree = Tree.get_current_tree()
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
      ui.update(tree.root)
    end)
  end)
end

---@param node YaTreeNode
---@param term string
---@param search_result string[]
function M.display_search_result(node, term, search_result)
  local tree = Tree.get_current_tree()
  if not tree or not node then
    return
  end
  tree.search.result, tree.search.current_node = node:create_search_tree(search_result)
  tree.search.result.search_term = term

  vim.schedule(function()
    ui.search(tree.search.result)
  end)
end

function M.focus_first_search_result()
  local tree = Tree.get_current_tree()
  if not tree then
    return
  end

  if tree.search.result and tree.search.current_node then
    ui.focus_node(tree.search.current_node)
  end
end

function M.clear_search()
  local tree = Tree.get_current_tree()
  if not tree then
    return
  end

  tree.search.result = nil
  tree.search.current_node = nil
  ui.close_search(tree.root, tree.current_node)
end

---@param node YaTreeNode
function M.toggle_help(node)
  local tree = Tree.get_current_tree()
  if not tree then
    return
  end

  tree.current_node = ui.is_help_open() and tree.current_node or node
  ui.toggle_help(tree.root, tree.current_node)
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
  local tree = Tree.get_current_tree()
  if not tree then
    return
  end

  if ui.is_buffer_yatree(bufnr) then
    if not ui.is_open() then
      return
    end
    tree.current_node = M.get_current_node()
  else
    local edit_winid = ui.get_edit_winid()
    local is_floating_win = ui.is_window_floating()
    local is_ui_win = ui.is_current_window_ui_window()
    if not (is_floating_win or is_ui_win) then
      log.debug("on_win_leave ui.is_floating=%s, ui.is_view_win=%s, setting edit_winid to=%s", is_floating_win, is_ui_win, edit_winid)
      ui.set_edit_winid(api.nvim_get_current_win())
    end
  end
end

function M.on_color_scheme()
  log.debug("on_color_scheme")
  ui.setup_highlights()
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
            -- FIXME: only update any visible ui
            vim.schedule(function()
              ui.update(tree.root)
            end)
          end
        end
      end)
    end)
  end
end

---@param file string
---@param bufnr number
function M.on_buf_enter(file, bufnr)
  if not ui.is_open() or file == nil or file == "" or ui.is_buffer_yatree(bufnr) then
    return
  end

  local tree = Tree.get_current_tree()
  if not tree then
    return
  end

  async.run(function()
    tree.current_node = tree.root:expand({ to = file })

    if not (ui.is_help_open() or ui.is_search_open()) then
      vim.schedule(function()
        ui.update(tree.root, tree.current_node, true)
      end)
    end
  end)
end

function M.on_cursor_moved()
  if not ui.is_open() then
    return
  end
  ui.move_cursor_to_name()
end

function M.on_dir_changed()
  local window_change = vim.v.event.changed_window
  if window_change then
    return
  end
  local new_cwd = vim.v.event.cwd
  local scope = vim.v.event.scope
  log.debug("on_dir_changed: event.scope=%s, event.changed_window=%s, event.cwd=%s", scope, window_change, new_cwd)

  if scope == "tabpage" then
    local tree = Tree.get_current_tree()
    if not tree or new_cwd == tree.cwd then
      return
    end

    tree.current_node = M.get_current_node()
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

  -- FIXME: how to handle uis not currently shown
  local tree = Tree.get_current_tree()
  if tree then
    if not ui.is_help_open() then
      if ui.is_search_open() then
        ui.update(tree.search.result)
      elseif ui.is_open() then
        ui.update(tree.root)
      end
    end
  end
end, config.diagnostics.debounce_time)

---@return boolean, string?
local function get_netrw_dir()
  if not config.replace_netrw then
    return false
  end

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

  log.debug("get_netrw_dir: bufnr=%s, bufname=%s, buftype=%s, stat.type=%s", bufnr, bufname, buftype, stat.type)
  local lines = api.nvim_buf_get_lines(bufnr, 0, -1, false)
  if #lines == 0 or (#lines == 1 and lines[1] == "") then
    log.debug("get_netrw_dir: returning %s", fn.expand(bufname))
    return true, fn.expand(bufname)
  else
    return false
  end
end

function M.setup()
  local netrw, root_path = get_netrw_dir()
  if not netrw then
    root_path = uv.cwd()
  end

  async.run(function()
    -- create the tree for the current tabpage
    local tree = Tree.get_current_tree({ root_path = root_path })
    if netrw then
      vim.schedule(function()
        M.open({ tree = tree, hijack_buffer = true })
      end)
    end
  end)
end

return M
