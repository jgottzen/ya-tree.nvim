local scheduler = require("plenary.async.util").scheduler
local void = require("plenary.async").void
local Path = require("plenary.path")

local config = require("ya-tree.config").config
local job = require("ya-tree.job")
local Trees = require("ya-tree.trees")
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

local M = {}

---@param path string
---@return string|nil path the fully resolved path, or `nil`
local function resolve_path(path)
  if not utils.is_absolute_path(path) then
    -- a relative path is relative to the current cwd
    path = Path:new({ uv.cwd(), path }):absolute() --[[@as string]]
    log.debug("expanded cwd relative path to %s", path)
  end
  return path
end

---@class YaTreeLib.OpenWindow
---@field path? string
---@field switch_root? boolean
---@field focus? boolean
---@field tree_type? YaTreeType|string

---@async
---@param opts? YaTreeLib.OpenWindow
---  - {opts.path?} `string`
---  - {opts.switch_root?} `boolean`
---  - {opts.focus?} `boolean`
---  - {opts.tree_type?} `YaTreeName|string`
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
  log.debug("opening window with %s", opts)
  -- If the switch_root flag is true and a file is given _and_ the appropriate config flag is set,
  -- we need to update the filesystem tree with the new cwd and root _before_ issuing the `tcd` command, since
  -- control passes to the handler. Issuing it after will be a no-op since since the tree cwd is already set.
  local issue_tcd = false

  scheduler()
  local tabpage = api.nvim_get_current_tabpage() --[[@as number]]

  local tree
  if opts.tree_type then
    tree = Trees.get_tree(tabpage, opts.tree_type, true)
    if not tree then
      local path = opts.path and resolve_path(opts.path) or uv.cwd()
      tree = Trees.new_tree(tabpage, opts.tree_type, true, path)
      if not tree then
        utils.warn(string.format("Could not create tree for path %q", path))
      end
    end
  end

  if opts.switch_root and opts.path then
    issue_tcd = config.cwd.update_from_tree
    local path = Path:new(opts.path)
    local cwd = path:absolute() --[[@as string]]
    if not path:is_dir() then
      path = path:parent()
      cwd = path:absolute() --[[@as string]]
    end
    if path:exists() then
      log.debug("switching cwd to %q", cwd)
      tree = Trees.filesystem(tabpage, true)
      if tree then
        tree:change_root_node(cwd)
      else
        tree = Trees.new_filesystem(tabpage, true, cwd)
      end
      if config.cwd.update_from_tree then
        -- updating the root node doesn't change the cwd, so set it
        tree.cwd = cwd
      end
      scheduler()
    else
      utils.warn(string.format("Path %q doesn't exist.\nUsing %q as tree root", opts.path, uv.cwd()))
      tree = Trees.current_tree(tabpage)
    end
  end

  if not tree then
    tree = Trees.current_tree(tabpage)
    if not tree then
      tree = Trees.new_filesystem(tabpage, true)
    end
  end

  local path
  if opts.path then
    path = resolve_path(opts.path)
    if not path then
      log.info("%q cannot be resolved in relation to the current cwd %q", opts.path, uv.cwd())
    end
  end

  local node
  if path then
    node = tree.root:expand({ to = path })
    if node then
      local hidden, reason = node:is_hidden(config)
      if hidden and reason then
        if reason == "filter" then
          config.filters.enable = false
        elseif reason == "git" then
          config.git.show_ignored = true
        end
      end
      log.debug("navigating to %q", path)
    else
      -- need to check if the `tree_type` is explicitly "files"
      if opts.tree_type and opts.tree_type == "files" then
        log.error("cannot expand to file %q in with root %s", path, tostring(tree.root))
        utils.warn(string.format("Path %q is not a file or directory", opts.path))
      else
        log.debug("cannot expand to node %q in view %q", path, opts.tree_type)
        utils.notify(string.format("Path %q is not available in the %s view", path, opts.tree_type or "current"))
      end
    end
  elseif config.follow_focused_file then
    scheduler()
    local bufnr = api.nvim_get_current_buf() --[[@as number]]
    if api.nvim_buf_get_option(bufnr, "buftype") == "" then
      local filename = api.nvim_buf_get_name(bufnr) --[[@as string]]
      if tree.root:is_ancestor_of(filename) then
        node = tree.root:expand({ to = filename })
      end
    end
  end

  scheduler()
  if ui.is_open() then
    local ui_node = ui.get_current_node()
    tree.current_node = ui_node

    if not node then
      node = ui_node
    end
  end
  if ui.is_open() and not opts.tree_type then
    if opts.focus then
      ui.focus()
    end
    ui.update(tree, node)
  else
    ui.open(tree, node, { focus = opts.focus, focus_edit_window = not opts.focus })
  end

  if issue_tcd then
    log.debug("issueing tcd autocmd to %q", tree.root.path)
    vim.cmd("tcd " .. fn.fnameescape(tree.root.path))
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
  local tree = Trees.current_tree(api.nvim_get_current_tabpage())
  if tree and ui.is_open() then
    log.debug("redrawing tree")
    ui.update(tree)
  end
end

---@async
---@param tree YaTree
---@param node YaTreeNode
function M.toggle_node(tree, node)
  if not node:is_container() or tree.root == node then
    return
  end

  if node.expanded then
    node:collapse()
  else
    node:expand()
  end
  ui.update(tree, node)
end

---@param tree YaTree
---@param node YaTreeNode
function M.close_node(tree, node)
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
  ui.update(tree, node)
end

---@async
---@param tree YaTree
function M.close_all_nodes(tree)
  tree.root:collapse({ recursive = true, children_only = true })
  ui.update(tree, tree.root)
end

---@async
---@param tree YaTree
---@param node YaTreeNode
function M.close_all_child_nodes(tree, node)
  if node:is_container() then
    node:collapse({ recursive = true, children_only = true })
    ui.update(tree, node)
  end
end

do
  ---@async
  ---@param node YaTreeNode
  ---@param depth number
  local function expand(node, depth)
    node:expand()
    if depth < config.expand_all_nodes_max_depth then
      for _, child in ipairs(node.children) do
        if child:is_container() and not child:is_hidden(config) then
          expand(child, depth + 1)
        end
      end
    end
  end

  ---@async
  ---@param tree YaTree
  ---@param node YaTreeNode
  function M.expand_all_nodes(tree, node)
    expand(tree.root, 1)
    ui.update(tree, node)
  end

  ---@async
  ---@param tree YaTree
  ---@param node YaTreeNode
  function M.expand_all_child_nodes(tree, node)
    if node:is_container() then
      expand(node, 1)
      ui.update(tree, node)
    end
  end
end

---@async
---@param tabpage integer
---@param set_default? boolean
---@param root? string
local function get_or_create_filesystem_tree(tabpage, set_default, root)
  local tree = Trees.filesystem(tabpage, set_default)
  if not tree then
    tree = Trees.new_filesystem(tabpage, set_default or false, root)
  end
  return tree
end

---@async
---@param tabpage integer
---@param new_root YaTreeNode|string
local function change_cwd(tabpage, new_root)
  local tree = get_or_create_filesystem_tree(tabpage, true, new_root)
  local new_cwd = type(new_root) == "string" and new_root or new_root.path

  -- only issue a :tcd if the config is set, _and_ the path is different from the filesystem tree's cwd
  if config.cwd.update_from_tree and new_cwd ~= tree.cwd then
    vim.cmd("tcd " .. fn.fnameescape(new_cwd))
  elseif new_cwd ~= tree.root.path then
    tree:change_root_node(new_root)
    scheduler()
    ui.update(tree, type(new_root) == "table" and new_root or tree.current_node)
  end
end

---@async
---@param tree YaTree
---@param node YaTreeNode
function M.cd_to(tree, node)
  local tabpage = api.nvim_get_current_tabpage()
  if node == tree.root then
    return
  end
  if not node:is_directory() then
    if not node.parent or node.parent == tree.root then
      return
    end
    node = node.parent --[[@as YaTreeNode]]
  end
  log.debug("cd to %q", node.path)
  change_cwd(tabpage, node)
end

---@async
function M.cd_up(tree)
  local tabpage = api.nvim_get_current_tabpage()
  if utils.is_root_directory(tree.root.path) then
    return
  end

  local new_cwd = tree.root.parent and tree.root.parent.path or Path:new(tree.root.path):parent().filename
  log.debug("changing root directory one level up from %q to %q", tree.root.path, new_cwd)

  change_cwd(tabpage, tree.root.parent or new_cwd)
end

---@param tree YaTree
---@param node YaTreeNode
function M.toggle_ignored(tree, node)
  config.git.show_ignored = not config.git.show_ignored
  log.debug("toggling git ignored to %s", config.git.show_ignored)
  ui.update(tree, node)
end

---@param tree YaTree
---@param node YaTreeNode
function M.toggle_filter(tree, node)
  config.filters.enable = not config.filters.enable
  log.debug("toggling filter to %s", config.filters.enable)
  ui.update(tree, node)
end

---@async
---@param tree YaFsTree
---@param node YaTreeNode
---@return boolean found
local function rescan_dir_for_git(tree, node)
  tree.refreshing = true
  log.debug("checking if %s is in a git repository", node.path)

  if not node:is_directory() then
    node = node.parent --[[@as YaTreeNode]]
  end
  local found = false
  if not node.repo or node.repo:is_yadm() then
    found = tree:check_node_for_repo(node)
  end
  tree.refreshing = false
  return found
end

---@async
---@param _? YaTree
---@param node YaTreeNode
function M.rescan_dir_for_git(_, node)
  if not config.git.enable then
    utils.notify("Git is not enabled.")
    return
  end

  local tree = Trees.filesystem(api.nvim_get_current_tabpage())
  if not tree or tree.refreshing or vim.v.exiting ~= vim.NIL then
    log.debug("refresh already in progress or vim is exiting, aborting refresh")
    return false
  end
  if rescan_dir_for_git(tree, node) then
    ui.update(tree, node)
  else
    utils.notify(string.format("No Git repository found in %q.", node.path))
  end
end

---@async
---@param node YaTreeNode
---@param term string
function M.search(node, term)
  scheduler()
  local tabpage = api.nvim_get_current_tabpage()
  local tree = Trees.search(tabpage, true)
  if not tree then
    tree = Trees.new_search(tabpage, true, node.path)
  elseif tree.root.path ~= node.path then
    tree:change_root_node(node.path)
  end
  local matches_or_error = tree:search(term)
  if type(matches_or_error) == "number" then
    utils.notify(string.format("Found %s matches for %q in %q", matches_or_error, term, node.path))
    ui.update(tree, tree.current_node)
  else
    utils.warn(string.format("Failed with message:\n\n%s", matches_or_error))
  end
end

---@async
---@param tree YaTree
---@param node YaTreeNode
function M.refresh_tree(tree, node)
  if tree.refreshing or vim.v.exiting ~= vim.NIL then
    log.debug("refresh already in progress or vim is exiting, aborting refresh")
    return
  end
  tree.refreshing = true
  log.debug("refreshing current tree")

  tree.root:refresh({ recurse = true, refresh_git = config.git.enable })
  ui.update(tree, node, { focus_node = true })
  tree.refreshing = false
end

---@async
---@param tree YaTree
---@param path string
function M.refresh_tree_and_goto_path(tree, path)
  tree.root:refresh({ recurse = true, refresh_git = config.git.enable })
  local node = tree.root:expand({ to = path })
  ui.update(tree, node, { focus_node = true })
end

---@async
---@param _ YaTree
---@param node YaTreeNode
function M.goto_node_in_tree(_, node)
  local tabpage = api.nvim_get_current_tabpage()
  local tree = get_or_create_filesystem_tree(tabpage, true)
  local target_node = tree.root:expand({ to = node.path })
  ui.update(tree, target_node)
end

---@async
function M.close_search()
  local tabpage = api.nvim_get_current_tabpage()
  local tree = get_or_create_filesystem_tree(tabpage, true)
  ui.update(tree, tree.current_node)
end

function M.show_last_search()
  local tabpage = api.nvim_get_current_tabpage()
  local tree = Trees.search(tabpage, true)
  if tree then
    ui.update(tree, tree.current_node)
  end
end

---@param tree YaTree
---@param path string
function M.search_for_node_in_tree(tree, path)
  local cmd, args = utils.build_search_arguments(path, tree.root.path, false)
  if not cmd then
    return
  end

  job.run({ cmd = cmd, args = args, cwd = tree.root.path, async_callback = true }, function(code, stdout, stderr)
    if code == 0 then
      local lines = vim.split(stdout or "", "\n", { plain = true, trimempty = true }) --[=[@as string[]]=]
      log.debug("%q found %s matches for %q in %q", cmd, #lines, path, tree.root.path)

      if #lines > 0 then
        local node = tree.root:expand({ to = lines[1] })
        scheduler()
        ui.update(tree, node)
      else
        utils.notify(string.format("%q cannot be found in the tree", path))
      end
    else
      log.error("%q with args %s failed with code %s and message %s", cmd, args, code, stderr)
    end
  end)
end

---@async
---@param current_tree YaTree
---@param node YaTreeNode
function M.toggle_git_view(current_tree, node)
  local tabpage = api.nvim_get_current_tabpage()

  if current_tree.TYPE == "git" then
    local tree = get_or_create_filesystem_tree(tabpage, true)
    ui.update(tree, tree.current_node)
  elseif current_tree.TYPE == "files" then
    ---@cast current_tree YaFsTree
    if not node.repo or node.repo:is_yadm() then
      rescan_dir_for_git(current_tree, node)
    end
    if node.repo then
      local tree = Trees.git(tabpage, true)
      if not tree then
        tree = Trees.new_git(tabpage, true, node.repo)
      elseif tree.root.repo ~= node.repo then
        tree:change_root_node(node.repo)
      end
      ui.update(tree, tree.current_node)
    end
  end
end

---@async
---@param current_tree YaTree
---@param node YaTreeNode
function M.toggle_buffers_view(current_tree, node)
  local tabpage = api.nvim_get_current_tabpage()

  if current_tree.TYPE == "buffers" then
    local tree = get_or_create_filesystem_tree(tabpage, true, node.path)
    ui.update(tree, tree.current_node)
  elseif current_tree.TYPE == "files" then
    local tree = Trees.buffers(tabpage, true)
    if not tree then
      tree = Trees.new_buffers(tabpage, true, uv.cwd())
    end
    ui.update(tree, tree.current_node)
  end
end

local function setup_netrw()
  if config.replace_netrw then
    vim.g.loaded_netrw = 1
    vim.g.loaded_netrwPlugin = 1
    api.nvim_create_augroup("FileExplorer", { clear = true })
  end
end

---@param winid number
local function on_win_closed(winid)
  -- if the closed window was a floating window, do nothing.
  -- otherwise we will quit from a hijacked netrw buffer when using
  -- any form of popup, including command mode
  if ui.is_window_floating(winid) or not ui.is_open() then
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
---@param bufnr integer
---@param file string
local function on_buf_enter(bufnr, file)
  local buftype = api.nvim_buf_get_option(bufnr, "buftype")
  if file == "" or not (buftype == "" or buftype == "terminal") then
    return
  end
  local tabpage = api.nvim_get_current_tabpage()
  local tree = Trees.current_tree(tabpage)

  -- Must use a synchronous directory check here, otherwise a scheduler call is required before the call to ui.is_open,
  -- the scheduler call will update the ui, and if the buffer was opened in the tree window, and the config option to
  -- move it to the edit window is set, the buffer will first appear in the tree window and then visibly be moved to the
  -- edit window. Not very visually pleasing.
  if config.replace_netrw and utils.is_directory_sync(file) then
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

    ---@type YaTreeLib.OpenWindow
    local opts = { path = file, focus = true, tree_type = "files" }
    if not tree then
      log.debug("no tree for current tab")
      local cwd = uv.cwd() --[[@as string]]
      if file:find(cwd, 1, true) then
        log.debug("requested directory is a subpath of the current cwd %q, opening tree with root at cwd", cwd)
      else
        log.debug("requested directory is not a subpath of the current cwd %q, opening tree with root of the requested path", cwd)
        opts.switch_root = true
      end
    else
      tree = Trees.filesystem(tabpage)
      if not tree or not tree.root:is_ancestor_of(file) and tree.root.path ~= file then
        log.debug("the current tree is not a parent for directory %s", file)
        opts.switch_root = true
      else
        log.debug("current tree is parent of directory %s", file)
      end
    end

    M.open_window(opts)
  elseif tree and ui.is_open() then
    if ui.is_current_window_ui() and config.move_buffers_from_tree_window and buftype == "" then
      log.debug("moving buffer %s to edit window", bufnr)
      ui.move_buffer_to_edit_window(bufnr)
    end

    if config.follow_focused_file then
      log.debug("focusing on node %q", file)
      local node = tree.root:expand({ to = file })
      ui.update(tree, node, { focus_node = true })
    elseif ui.is_highlight_open_file_enabled() then
      ui.update(tree)
    end
  end
end

function M.setup()
  setting_up = true
  config = require("ya-tree.config").config

  setup_netrw()

  local is_directory = false
  local path
  if config.replace_netrw then
    is_directory, path = utils.get_path_from_directory_buffer()
  end
  if not is_directory then
    path = uv.cwd() --[[@as string]]
  end

  void(function()
    local tree = get_or_create_filesystem_tree(api.nvim_get_current_tabpage(), true, path)

    scheduler()
    if is_directory or config.auto_open.on_setup then
      local focus = config.auto_open.on_setup and config.auto_open.focus_tree
      ui.open(tree, tree.current_node, { hijack_buffer = is_directory, focus = focus, focus_edit_window = not focus })
    end

    local events = require("ya-tree.events")
    local event = require("ya-tree.events.event")

    events.on_autocmd_event(event.WINDOW_CLOSED, "YA_TREE_LIB_AUTO_CLOSE_LAST_WINDOW", false, function(_, _, match)
      if config.auto_close then
        local winid = tonumber(match) --[[@as number]]
        on_win_closed(winid)
      end
    end)
    events.on_autocmd_event(event.TAB_NEW, "YA_TREE_LIB_AUTO_OPEN_NEW_TAB", true, function()
      if config.auto_open.on_new_tab then
        M.open_window({ focus = config.auto_open.focus_tree })
      end
    end)
    events.on_autocmd_event(event.TAB_ENTERED, "YA_TREE_LIB_REDRAW_TAB", true, M.redraw)
    events.on_autocmd_event(event.BUFFER_ENTERED, "YA_TREE_LIB_BUFFER_ENTERED", true, on_buf_enter)

    setting_up = false
  end)()
end

return M
