local scheduler = require("plenary.async.util").scheduler
local Path = require("plenary.path")

local config = require("ya-tree.config").config
local job = require("ya-tree.job")
local Sidebar = require("ya-tree.sidebar")
local Trees = require("ya-tree.trees")
local ui = require("ya-tree.ui")
local utils = require("ya-tree.utils")
local log = require("ya-tree.log")("lib")

local api = vim.api
local fn = vim.fn
local uv = vim.loop

local M = {}

---@param path string
---@return string|nil path the fully resolved path, or `nil`
local function resolve_path(path)
  local p = Path:new(path)
  return p:exists() and p:absolute() or nil
end

---@async
---@param opts? Yat.OpenWindowArgs
---  - {opts.path?} `string` The path to open.
---  - {opts.focus?} `boolean` Whether to focus the tree window.
---  - {opts.tree?} `Yat.Trees.Type` Which type of tree to open, defaults to the current tree, or `"filesystem"` if no current tree exists.
---  - {opts.position?} `Yat.Ui.Position` Where the tree window should be positioned.
---  - {opts.size?} `integer` The size of the tree window, either width or height depending on position.
---  - {opts.tree_args?} `table<string, any>` Any tree specific arguments.
function M.open_window(opts)
  opts = opts or {}
  log.debug("opening window with %s", opts)

  scheduler()
  local tabpage = api.nvim_get_current_tabpage()
  local sidebar = Sidebar.get_or_create_sidebar(tabpage, config.sidebar)

  local current_cwd = uv.cwd() --[[@as string]]
  local path = opts.path and resolve_path(opts.path)
  local tree
  if opts.tree then
    log.debug("opening tree of type %q", opts.tree)
    tree = sidebar:get_tree(opts.tree)
    if not tree then
      if opts.tree == "filesystem" and path and vim.startswith(path, current_cwd) then
        tree = sidebar:filesystem_tree(current_cwd)
      else
        tree = Trees.create_tree(tabpage, opts.tree, path, opts.tree_args)
        if tree then
          sidebar:add_tree(tree)
        end
      end
      if not tree then
        utils.warn(string.format("Could not create tree of type %q", opts.tree))
        return
      end
    elseif path and not tree.root:is_ancestor_of(path) and path ~= tree.root.path then
      tree:change_root_node(path)
    end
  else
    local root = path and (vim.startswith(path, current_cwd) and current_cwd or path) or nil
    tree = sidebar:filesystem_tree(root)
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
      log.info("cannot expand to node %q in tree type %q", path, tree.TYPE)
      utils.warn(string.format("Path %q is not available in the %q tree", path, tree.TYPE))
    end
  elseif config.follow_focused_file then
    scheduler()
    local bufnr = api.nvim_get_current_buf() --[[@as integer]]
    if api.nvim_buf_get_option(bufnr, "buftype") == "" then
      local filename = api.nvim_buf_get_name(bufnr) --[[@as string]]
      if tree.root:is_ancestor_of(filename) then
        node = tree.root:expand({ to = filename })
      end
    end
  end

  scheduler()
  if ui.is_open(tabpage) then
    ui.update(tree, node, { focus_window = opts.focus })
  else
    ui.open(sidebar, tree, node, { focus = opts.focus, focus_edit_window = not opts.focus, position = opts.position, size = opts.size })
  end

  if tree.TYPE == "filesystem" and config.cwd.update_from_tree and tree.root.path ~= uv.cwd() then
    log.debug("issueing tcd autocmd to %q", tree.root.path)
    vim.cmd("tcd " .. fn.fnameescape(tree.root.path))
  end
end

function M.close_window()
  local tabpage = api.nvim_get_current_tabpage()
  if ui.is_open(tabpage) then
    local tree, node = ui.get_current_tree_and_node(tabpage)
    if tree and node then
      tree.current_node = node
    end
    ui.close()
  end
end

---@async
function M.toggle_window()
  local tabpage = api.nvim_get_current_tabpage()
  if ui.is_open(tabpage) then
    M.close_window()
  else
    M.open_window()
  end
end

function M.redraw()
  local tabpage = api.nvim_get_current_tabpage()
  if ui.is_open(tabpage) then
    log.debug("redrawing tree")
    ui.update()
  end
end

---@async
---@param new_root string
local function change_root(new_root)
  if config.cwd.update_from_tree then
    vim.cmd("tcd " .. fn.fnameescape(new_root))
  else
    Sidebar.change_root_for_current_tabpage(new_root)
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
  change_root(node.path)
end

---@async
---@param tree Yat.Tree
function M.cd_up(tree)
  local new_cwd = tree.root.parent and tree.root.parent.path or Path:new(tree.root.path):parent().filename
  log.debug("changing root directory one level up from %q to %q", tree.root.path, new_cwd)

  change_root(new_cwd)
end

---@async
---@param tree Yat.Tree
---@param node Yat.Node
function M.toggle_ignored(tree, node)
  config.git.show_ignored = not config.git.show_ignored
  log.debug("toggling git ignored to %s", config.git.show_ignored)
  ui.update(tree, node)
end

---@async
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
---@return Yat.Git.Repo? repo
function M.rescan_node_for_git(tree, node)
  if not config.git.enable then
    utils.notify("Git is not enabled.")
    return
  end

  if tree.refreshing or vim.v.exiting ~= vim.NIL then
    log.debug("refresh already in progress or vim is exiting, aborting refresh")
    return
  end
  tree.refreshing = true
  log.debug("checking if %s is in a git repository", node.path)

  if not node:is_directory() and node.parent then
    node = node.parent --[[@as Yat.Node]]
  end
  if not node.repo or node.repo:is_yadm() then
    if tree:check_node_for_repo(node) then
      Sidebar.for_each_tree(function(_tree)
        local tree_node = _tree.root:get_child_if_loaded(node.path)
        if tree_node then
          tree_node:set_git_repo(node.repo)
        end
      end)
    end
  end
  tree.refreshing = false
  return node.repo
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

local function setup_netrw()
  if config.hijack_netrw then
    vim.cmd([[silent! autocmd! FileExplorer *]])
    vim.cmd([[autocmd VimEnter * ++once silent! autocmd! FileExplorer *]])
  end
end

---@param winid integer
local function on_win_closed(winid)
  local tabpage = api.nvim_get_current_tabpage()
  if ui.is_window_floating(winid) or not ui.is_open(tabpage) then
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
      vim.cmd("silent q!")
    end
  end, 100)
end

---@async
---@param bufnr integer
---@param file string
local function on_buf_enter(bufnr, file)
  local buftype = api.nvim_buf_get_option(bufnr, "buftype")
  if not (file ~= "" and (buftype == "" or buftype == "terminal")) then
    return
  end
  local tabpage = api.nvim_get_current_tabpage()
  local sidebar = Sidebar.get_sidebar(tabpage)

  -- Must use a synchronous directory check here, otherwise a scheduler call is required before any call to the ui,
  -- which in turn will update the ui, and if the buffer was opened in the tree window, and the config option to move it to
  -- the edit window is set, the buffer will first appear in the tree window and then visibly be moved to the edit window.
  -- The same is true for `bprevious`.
  -- Not very visually pleasing.
  if config.hijack_netrw and utils.is_directory_sync(file) then
    log.debug("the opened buffer is a directory with path %q", file)

    if ui.is_current_window_ui(tabpage) then
      ui.restore(tabpage)
    else
      -- switch back to the previous buffer so the window isn't closed
      vim.cmd("bprevious")
    end
    log.debug("deleting buffer %s with file %q", bufnr, file)
    api.nvim_buf_delete(bufnr, { force = true })

    M.open_window({ path = file, focus = true })
  elseif sidebar and ui.is_open(tabpage) then
    if ui.is_current_window_ui(tabpage) and config.move_buffers_from_tree_window and buftype == "" then
      log.debug("moving buffer %s to edit window", bufnr)
      ui.move_buffer_to_edit_window(tabpage, bufnr)
    end

    local tree = ui.get_current_tree_and_node(tabpage)
    if tree and tree.root:is_ancestor_of(file) then
      if config.follow_focused_file and file ~= "" and (buftype == "" or buftype == "terminal") then
        log.debug("focusing on node %q", file)
        local node = tree.root:expand({ to = file })
        if node then
          -- we need to allow the event loop to catch up when we enter a buffer after one was closed
          scheduler()
          ui.update(tree, node, { focus_node = true })
        end
      end
    end
  end
end

function M.setup()
  config = require("ya-tree.config").config

  setup_netrw()

  local events = require("ya-tree.events")
  local event = require("ya-tree.events.event").autocmd
  if config.close_if_last_window then
    events.on_autocmd_event(event.WINDOW_CLOSED, "YA_TREE_LIB_AUTO_CLOSE_LAST_WINDOW", function(_, _, match)
      local winid = tonumber(match) --[[@as integer]]
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
end

return M
