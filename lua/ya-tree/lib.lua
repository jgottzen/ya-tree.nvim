local scheduler = require("plenary.async.util").scheduler
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
---  - {opts.position?} `Yat.Ui.Canvas.Position` Where the tree window should be positioned.
---  - {opts.size?} `integer` The size of the tree window, either width or height depending on position.
---  - {opts.tree_args?} `table<string, any>` Any tree specific arguments.
function M.open_window(opts)
  opts = opts or {}
  log.debug("opening window with %s", opts)

  scheduler()
  local tabpage = api.nvim_get_current_tabpage() --[[@as integer]]
  local previous_tree = Trees.current_tree(tabpage)
  if previous_tree and ui.is_open(previous_tree.TYPE) then
    previous_tree.current_node = ui.get_current_node()
  end

  local current_cwd = uv.cwd() --[[@as string]]
  local path = opts.path and resolve_path(opts.path)
  local tree
  if opts.tree then
    log.debug("opening tree of type %q", opts.tree)
    tree = Trees.get_tree(tabpage, opts.tree, true)
    if not tree then
      if opts.tree == "filesystem" and path and vim.startswith(path, current_cwd) then
        tree = Trees.filesystem(tabpage, true, current_cwd)
      else
        tree = Trees.new_tree(tabpage, opts.tree, true, path, opts.tree_args)
      end
      if not tree then
        utils.warn(string.format("Could not create tree of type %q", opts.tree))
        return
      end
    elseif path and not tree.root:is_ancestor_of(path) and path ~= tree.root.path then
      tree:change_root_node(path)
    end
  else
    tree = Trees.current_tree(tabpage)
    if not tree then
      local root = path and vim.startswith(path, current_cwd) and current_cwd or path
      tree = Trees.filesystem(tabpage, true, root)
    elseif path and not tree.root:is_ancestor_of(path) and path ~= tree.root.path then
      tree:change_root_node(path)
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
      log.info("cannot expand to node %q in tree type %q", path, tree.TYPE)
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
  else
    node = tree.current_node
  end

  scheduler()
  if ui.is_open() then
    ui.update(tree, node, { focus_window = opts.focus })
  else
    ui.open(tree, node, { focus = opts.focus, focus_edit_window = not opts.focus, position = opts.position, size = opts.size })
  end

  if tree.TYPE == "filesystem" and config.cwd.update_from_tree and tree.root.path ~= uv.cwd() then
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

  if not node:is_directory() then
    node = node.parent --[[@as Yat.Node]]
  end
  if not node.repo or node.repo:is_yadm() then
    if tree:check_node_for_repo(node) then
      Trees.for_each_tree(function(_tree)
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

---@async
---@param tree? Yat.Trees.Search
---@param node Yat.Node
---@param term string
function M.search(tree, node, term)
  if not tree then
    scheduler()
    local tabpage = api.nvim_get_current_tabpage()
    tree = Trees.search(tabpage, node.path)
  end
  -- necessary if the tree has been configured as persistent
  local _ = tree:change_root_node(node.path)
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

    M.open_window({ path = file, focus = true })
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
  config = require("ya-tree.config").config

  setup_netrw()

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
end

return M
