local scheduler = require("plenary.async.util").scheduler
local void = require("plenary.async").void
local Path = require("plenary.path")

local config = require("ya-tree.config").config
local job = require("ya-tree.job")
local Trees = require("ya-tree.trees")
local ui = require("ya-tree.ui")
local utils = require("ya-tree.utils")
local log = require("ya-tree.log")("lib")

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
  local p = Path:new(path)
  return p:exists() and p:absolute() or nil
end

---@async
---@param opts? Yat.OpenWindowArgs
---  - {opts.path?} `string`
---  - {opts.switch_root?} `boolean`
---  - {opts.focus?} `boolean`
---  - {opts.tree?} `Yat.Trees.Type`
---  - {opts.location?} `Yat.Ui.Canvas.Position`
---  - {opts.size?} `integer`
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
  if opts.tree then
    log.debug("opening tree of type %q", opts.tree)
    tree = Trees.get_tree(tabpage, opts.tree, true)
    if not tree then
      tree = Trees.new_tree(tabpage, opts.tree, true, opts.path)
      if not tree then
        utils.warn(string.format("Could not create tree of type %q", opts.tree))
      end
    end
  end

  local path = opts.path and resolve_path(opts.path)
  if opts.switch_root and opts.path then
    issue_tcd = config.cwd.update_from_tree
    if path then
      local p = Path:new(path)
      if not p:is_dir() then
        path = p:parent():absolute() --[[@as string]]
      end
      log.debug("switching cwd to %q", path)
      tree = Trees.current_tree(tabpage)
      if not tree then
        tree = Trees.filesystem_or_new(tabpage, true, path)
      end
      -- no-op if a new "filesystem" tree was created
      tree:change_root_node(path)
    else
      issue_tcd = false
      utils.warn(string.format("Path %q doesn't exist!", opts.path))
      tree = Trees.current_tree(tabpage)
    end
  end

  if not tree then
    tree = Trees.current_tree(tabpage)
    if not tree then
      tree = Trees.filesystem_or_new(tabpage, true)
    end
  end

  if opts.path and not path then
    utils.warn(string.format("Path %q doesn't exist!", opts.path))
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
      log.info("cannot expand to node %q in tree type %q", path, opts.tree)
      utils.warn(string.format("Path %q is not available in the %q tree", path, tree.TYPE))
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
    local previous_tree = Trees.previous_tree(tabpage)
    if previous_tree then
      previous_tree.current_node = ui.get_current_node()
    end
    ui.update(tree, node, { focus_window = opts.focus })
  else
    ui.open(tree, node, { focus = opts.focus, focus_edit_window = not opts.focus, position = opts.position, size = opts.size })
  end

  if issue_tcd then
    log.debug("issueing tcd autocmd to %q", tree.root.path)
    vim.cmd("tcd " .. fn.fnameescape(tree.root.path))
  end
end

function M.close_window()
  local tree = Trees.current_tree(api.nvim_get_current_tabpage())
  if tree and ui.is_open() then
    tree.current_node = ui.get_current_node()
    ui.close()
  end
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
---@param new_root Yat.Node|string
local function change_cwd(new_root)
  local new_cwd = type(new_root) == "string" and new_root or new_root.path

  if config.cwd.update_from_tree then
    vim.cmd("tcd " .. fn.fnameescape(new_cwd))
  else
    Trees.change_cwd_for_current_tabpage(new_cwd)
  end
end

---@async
---@param _ Yat.Tree
---@param node Yat.Node
function M.cd_to(_, node)
  if not node:is_directory() then
    if not node.parent then
      return
    end
    node = node.parent --[[@as Yat.Node]]
  end
  log.debug("cd to %q", node.path)
  change_cwd(node)
end

---@async
---@param tree Yat.Tree
function M.cd_up(tree)
  local new_cwd = tree.root.parent and tree.root.parent.path or Path:new(tree.root.path):parent().filename
  log.debug("changing root directory one level up from %q to %q", tree.root.path, new_cwd)

  change_cwd(tree.root.parent or new_cwd)
end

---@param tree Yat.Tree
---@param node Yat.Node
function M.toggle_ignored(tree, node)
  config.git.show_ignored = not config.git.show_ignored
  log.debug("toggling git ignored to %s", config.git.show_ignored)
  ui.update(tree, node)
end

---@param tree Yat.Tree
---@param node Yat.Node
function M.toggle_filter(tree, node)
  config.filters.enable = not config.filters.enable
  log.debug("toggling filter to %s", config.filters.enable)
  ui.update(tree, node)
end

---@async
---@param tree Yat.Tree
---@param node Yat.Node
---@return boolean found
local function rescan_node_for_git(tree, node)
  tree.refreshing = true
  log.debug("checking if %s is in a git repository", node.path)

  if not node:is_directory() then
    node = node.parent --[[@as Yat.Node]]
  end
  local found = false
  if not node.repo or node.repo:is_yadm() then
    found = tree:check_node_for_repo(node)
    Trees.for_each_tree(function(_tree)
      local tree_node = _tree.root:get_child_if_loaded(node.path)
      if tree_node then
        tree_node:set_git_repo(node.repo)
      end
    end)
    if not found then
      utils.notify(string.format("No Git repository found in %q.", node.path))
    end
  elseif node.repo and not node.repo:is_yadm() then
    utils.notify(string.format("%q is already detected as a Git repository.", node.path))
  end
  tree.refreshing = false
  return found
end

---@async
---@param tree Yat.Tree
---@param node Yat.Node
function M.rescan_node_for_git(tree, node)
  if not config.git.enable then
    utils.notify("Git is not enabled.")
    return
  end

  if tree.refreshing or vim.v.exiting ~= vim.NIL then
    log.debug("refresh already in progress or vim is exiting, aborting refresh")
    return false
  end
  if rescan_node_for_git(tree, node) then
    ui.update(tree, node)
  end
end

---@async
---@param node Yat.Node
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

---@param tree Yat.Tree
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
        local first = lines[1]
        if first:sub(-1) == utils.os_sep then
          first = first:sub(1, -2)
        end
        local node = tree.root:expand({ to = first })
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
---@param tree Yat.Tree
---@param node Yat.Node
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
---@param tree Yat.Tree
---@param path string
function M.refresh_tree_and_goto_path(tree, path)
  tree.root:refresh({ recurse = true, refresh_git = config.git.enable })
  local node = tree.root:expand({ to = path })
  ui.update(tree, node, { focus_node = true })
end

---@async
---@param current_tree Yat.Tree
---@param node Yat.Node
function M.toggle_git_tree(current_tree, node)
  local tabpage = api.nvim_get_current_tabpage()

  if current_tree.TYPE == "git" then
    local tree = Trees.previous_tree(tabpage, true)
    if not tree then
      tree = Trees.filesystem_or_new(tabpage, true)
    end
    ui.update(tree, tree.current_node)
  else
    if not node.repo or node.repo:is_yadm() then
      rescan_node_for_git(current_tree, node)
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
---@param current_tree Yat.Tree
function M.toggle_buffers_tree(current_tree)
  local tabpage = api.nvim_get_current_tabpage()

  if current_tree.TYPE == "buffers" then
    local tree = Trees.previous_tree(tabpage, true)
    if not tree then
      tree = Trees.filesystem_or_new(tabpage, true)
    end
    ui.update(tree, tree.current_node)
  else
    local tree = Trees.buffers(tabpage, true)
    if not tree then
      tree = Trees.new_buffers(tabpage, true, uv.cwd())
    end
    ui.update(tree, tree.current_node)
  end
end

---@async
function M.show_filesystem_tree()
  local tabpage = api.nvim_get_current_tabpage()
  local tree = Trees.filesystem_or_new(tabpage, true)
  ui.update(tree, tree.current_node)
end

local function setup_netrw()
  if config.replace_netrw then
    vim.g.loaded_netrw = 1
    vim.g.loaded_netrwPlugin = 1
    vim.cmd([[silent! autocmd! FileExplorer *]])
    vim.cmd([[autocmd VimEnter * ++once silent! autocmd! FileExplorer *]])
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
      vim.cmd(":silent q!")
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

    ---@type Yat.OpenWindowArgs
    local opts = { path = file, focus = true, tree = "filesystem" }
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
    local tabpage = api.nvim_get_current_tabpage()
    local tree = Trees.filesystem_or_new(tabpage, false, path)

    scheduler()
    if is_directory or config.auto_open.on_setup then
      local focus = config.auto_open.on_setup and config.auto_open.focus_tree
      Trees.set_current_tree(tabpage, tree)
      ui.open(tree, tree.current_node, { hijack_buffer = is_directory, focus = focus, focus_edit_window = not focus })
    end

    local events = require("ya-tree.events")
    local event = require("ya-tree.events.event").autocmd

    if config.close_if_last_window then
      events.on_autocmd_event(event.WINDOW_CLOSED, "YA_TREE_LIB_AUTO_CLOSE_LAST_WINDOW", function(_, _, match)
        local winid = tonumber(match) --[[@as number]]
        on_win_closed(winid)
      end)
    end
    if config.auto_open.on_new_tab then
      events.on_autocmd_event(event.TAB_NEW, "YA_TREE_LIB_AUTO_OPEN_NEW_TAB", true, function()
        M.open_window({ focus = config.auto_open.focus_tree })
      end)
    end
    events.on_autocmd_event(event.TAB_ENTERED, "YA_TREE_LIB_REDRAW_TAB", true, M.redraw)
    events.on_autocmd_event(event.BUFFER_ENTERED, "YA_TREE_LIB_BUFFER_ENTERED", true, on_buf_enter)

    setting_up = false
  end)()
end

return M
