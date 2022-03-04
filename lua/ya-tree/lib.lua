local async = require("plenary.async")
local Path = require("plenary.path")

local config = require("ya-tree.config").config
local Tree = require("ya-tree.tree")
local job = require("ya-tree.job")
local git = require("ya-tree.git")
local debounce_trailing = require("ya-tree.debounce").debounce_trailing
local ui = require("ya-tree.ui")
local utils = require("ya-tree.utils")
local log = require("ya-tree.log")

local api = vim.api
local fn = vim.fn
local uv = vim.loop

local M = {
  tree = {
    cwd = nil,
    root = nil,
    current_node = nil,
    search = {
      result = nil,
      current_node = nil,
    },
  },
}

function M.get_cwd()
  return M.tree.cwd
end

function M.open(hijack_buffer)
  ui.open(M.tree.root, { hijack_buffer = hijack_buffer })
end

function M.close()
  ui.close()
end

function M.toggle()
  if ui.is_open() then
    M.close()
  else
    M.open()
    if config.follow_focused_file then
      M.navigate_to()
    end
  end
end

function M.focus()
  ui.focus(M.tree.root)
end

function M.redraw()
  log.debug("redrawing tree")

  M.tree.current_node = M.get_current_node()
  ui.update(M.tree.root, M.tree.current_node)
end

local function get_current_buffer_filename()
  local bufname = fn.bufname()
  local file = fn.fnamemodify(bufname, ":p")
  log.debug("current buffer file is %s, bufname is %s", file, bufname)

  return utils.is_readable_file(file) and file
end

local function expand_to_path(file)
  local node = Tree.node_for_path(file)
  if node then
    -- the path to the file has already been scanned into the tree
    log.debug("node %q loaded in tree, expanding...", node.path)
    node:expand()
    local parent = node.parent
    while parent and parent ~= M.tree.root do
      parent:expand()
      parent = parent.parent
    end
  else
    -- The node is currently not loaded in the tree, expand to it
    log.debug("%q not loaded in tree, loading...", file)
    node = M.tree.root:expand({ to = file })
  end

  return node
end

function M.navigate_to(file)
  if not file or file == "" then
    file = get_current_buffer_filename()
  end
  if file and not vim.startswith(file, utils.os_root()) then
    file = Path:new({ M.tree.cwd, file }):absolute()
    log.debug("expanded cwd relative path to %s", file)
  end
  log.debug("navigating to %q", file)

  if not file or not file:find(M.tree.root.path, 1, true) then
    -- the path is not located in the tree, just open the viewer
    M.open()
    return
  end

  async.run(function()
    M.tree.current_node = expand_to_path(file)

    vim.schedule(function()
      ui.open(M.tree.root, { redraw = true, focus = true }, M.tree.current_node)
    end)
  end)
end

function M.get_current_node()
  return ui.get_current_node()
end

function M.toggle_directory(node)
  if not node or not node:is_directory() then
    return
  end

  M.tree.current_node = node
  async.run(function()
    if node.expanded then
      node:collapse()
    else
      node:expand()
    end

    vim.schedule(function()
      ui.update(M.tree.root, M.tree.current_node)
    end)
  end)
end

function M.close_node(node)
  -- bail if the node is the current root node
  if not node or M.tree.root == node then
    return
  end

  if node:is_directory() and node.expanded then
    node:collapse()
  else
    local parent = node.parent
    if parent and parent ~= M.tree.root then
      parent:collapse()
      node = parent
    end
  end

  ui.update(M.tree.root, node)
end

function M.close_all_nodes()
  M.tree.root:collapse(true)
  M.tree.current_node = M.tree.root
  ui.update(M.tree.root, M.tree.root)
end

function M.cd_to(node)
  if not node then
    return
  end
  log.debug("cd to %q", node.path)

  M.tree.current_node = node

  if config.cwd.update_from_tree then
    vim.cmd("cd " .. fn.fnameescape(node.path))
  else
    M.change_root_node(node)
  end
end

function M.cd_up(node)
  if not node then
    return
  end
  local new_cwd = vim.fn.fnamemodify(M.tree.root.path, ":h")
  log.debug("changing root directory one level up from %q to %q", M.tree.root.path, new_cwd)

  M.tree.current_node = node

  if config.cwd.update_from_tree then
    vim.cmd("cd " .. fn.fnameescape(new_cwd))
  else
    M.change_root_node(M.tree.root.parent or new_cwd)
  end
end

function M.change_root_node(new_root)
  log.debug("changing root node to %q", tostring(new_root))

  async.run(function()
    if type(new_root) == "string" then
      M.tree.root = Tree.root(new_root)
    else
      M.tree.root = new_root
      M.tree.root:expand({ force_scan = true })
    end
    vim.schedule(function()
      ui.update(M.tree.root, M.tree.current_node)
    end)
  end)
end

function M.parent_node(node)
  -- bail if the nood is the current root node
  if not node or M.tree.root == node then
    return
  end

  node = node.parent
  ui.focus_node(node)
end

function M.prev_sibling(node)
  if not node then
    return
  end

  ui.focus_prev_sibling()
end

function M.next_sibling(node)
  if not node then
    return
  end

  ui.focus_next_sibling()
end

function M.first_sibling(node)
  if not node then
    return
  end

  ui.focus_first_sibling()
end

function M.last_sibling(node)
  if not node then
    return
  end

  ui.focus_last_sibling()
end

function M.toggle_ignored(node)
  if not node then
    return
  end
  log.debug("toggling ignored")

  M.tree.current_node = node
  config.git.show_ignored = not config.git.show_ignored
  ui.update(M.tree.root, M.tree.current_node)
end

function M.toggle_filter(node)
  if not node then
    return
  end
  log.debug("toggling filter")

  M.tree.current_node = node
  config.filters.enable = not config.filters.enable
  ui.update(M.tree.root, M.tree.current_node)
end

do
  local refreshing = false

  function M.refresh(node)
    log.debug("refreshing tree")
    if refreshing or vim.v.exiting ~= vim.NIL then
      log.debug("refresh already in progress or vim is exiting, aborting refresh")
      return
    end
    refreshing = true

    if node then
      M.tree.current_node = node
    end
    async.run(function()
      M.tree.root:refresh()

      vim.schedule(function()
        ui.update(M.tree.root, M.tree.current_node)
        refreshing = false
      end)
    end)
  end

  function M.refresh_and_navigate(path)
    log.debug("refreshing tree and navigating to %q", path)
    if refreshing or vim.v.exiting ~= vim.NIL then
      log.debug("refresh already in progress or vim is exiting, aborting refresh")
      return
    end
    refreshing = true

    M.tree.current_node = M.get_current_node()
    async.run(function()
      M.tree.root:refresh()

      if path then
        local node = expand_to_path(path)
        if node then
          node:expand()
          M.tree.current_node = node
        end
      end

      vim.schedule(function()
        ui.update(M.tree.root, M.tree.current_node)
        refreshing = false
      end)
    end)
  end

  function M.refresh_git()
    log.debug("refreshing git repo(s) info")
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

      vim.schedule(function()
        ui.update(M.tree.root)
        refreshing = false
      end)
    end)
  end
end

function M.rescan_dir_for_git(node)
  if not node then
    return
  end
  log.debug("checking if %s is in a git repository", node.path)

  M.tree.current_node = node
  if not node:is_directory() then
    node = node.parent
  end
  async.run(function()
    node:check_for_git_repo()

    vim.schedule(function()
      ui.update(M.tree.root)
    end)
  end)
end

function M.display_search_result(node, term, search_result)
  if not node then
    return
  end
  M.tree.search.result, M.tree.search.current_node = node:create_search_tree(search_result)
  M.tree.search.result.search_term = term

  vim.schedule(function()
    ui.search(M.tree.search.result)
  end)
end

function M.focus_first_search_result()
  if M.tree.search.result and M.tree.search.current_node then
    ui.focus_node(M.tree.search.current_node)
  end
end

function M.clear_search()
  M.tree.search.result = nil
  M.tree.search.current_node = nil
  ui.close_search(M.tree.root, M.tree.current_node)
end

function M.toggle_help(node)
  M.tree.current_node = ui.is_help_open() and M.tree.current_node or node
  ui.toggle_help(M.tree.root, M.tree.current_node)
end

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
  job.run({ cmd = config.system_open.cmd, args = args, cwd = M.tree.cwd, detached = true }, function(code, _, error)
    if code ~= 0 then
      vim.schedule(function()
        utils.print_error(string.format("%q returned error code %q and message %q", config.system_open.cmd, code, error))
      end)
    end
  end)
end

function M.on_win_leave()
  local bufnr = api.nvim_get_current_buf()
  if ui.is_buffer_yatree(bufnr) then
    if not ui.is_open() then
      return
    end
    M.tree.current_node = M.get_current_node()
  else
    local edit_winnr = ui.get_edit_winnr()
    local winnr = api.nvim_get_current_win()
    log.debug("on_win_leave edit_winnr=%s, current_winnr=%s, ui_winnr=%s", edit_winnr, winnr, require("ya-tree.ui.view").winnr())

    local is_floating_win = ui.is_current_window_floating()
    local is_ui_win = ui.is_current_win_ui_win()
    if not (is_floating_win or is_ui_win) then
      log.debug("on_win_leave ui.is_floating=%s, ui.is_view_win=%s, setting edit_winnr to=%s", is_floating_win, is_ui_win, edit_winnr)
      ui.set_edit_winnr(api.nvim_get_current_win())
    end
  end
end

function M.on_color_scheme()
  log.debug("on_color_scheme")
  ui.setup_highlights()
end

function M.on_win_closed()
  -- get the window config for all windows, this includes the closed window
  -- triggering the event
  local windows_before_event = {}
  for _, winnr in ipairs(api.nvim_list_wins()) do
    local win_config = api.nvim_win_get_config(winnr)
    windows_before_event[winnr] = win_config
  end

  vim.defer_fn(function()
    if not ui.is_open() then
      return
    end

    local windows = api.nvim_list_wins()
    if #windows == 1 and vim.bo.filetype == "YaTree" then
      -- remove the current window
      windows_before_event[windows[1]] = nil

      if select("#", windows_before_event) == 1 then
        -- if the closed window was a floating window, don't exit
        local _, window = next(windows_before_event)
        if #window.relative > 1 or window.external then
          return
        end
      end

      api.nvim_command(":silent q!")
    end
  end, 50)
end

function M.on_buf_write_post()
  log.debug("on_buf_write_post")
  M.refresh()
end

function M.on_buf_enter()
  if not ui.is_open() then
    return
  end

  local bufnr = api.nvim_get_current_buf()
  if ui.is_buffer_yatree(bufnr) then
    return
  end
  local bufname = api.nvim_buf_get_name(bufnr)
  local file = fn.fnamemodify(bufname, ":p")
  M.navigate_to(file)
end

function M.on_cursor_moved()
  if not ui.is_open() then
    return
  end
  ui.move_cursor_to_name()
end

function M.on_dir_changed()
  local new_cwd = vim.v.event.cwd
  local scope = vim.v.event.scope
  local window_change = vim.v.event.changed_window
  log.debug("on_dir_changed: event.scope=%s, event.changed_window=%s, event.cwd=%s", scope, window_change, new_cwd)
  if new_cwd == M.tree.cwd or (window_change and scope == "windows") then
    log.debug("on_dir_changed: no change required")
    return
  end

  M.tree.current_node = M.get_current_node()
  M.tree.cwd = new_cwd
  M.change_root_node(new_cwd)
end

function M.on_git_event()
  log.debug("on_git_event")
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
    local size = #M.tree.root.path
    for path, severity in pairs(diagnostics) do
      for _, parent in next, Path:new(path):parents() do
        -- don't propagate beyond the current root node
        if #parent < size then
          break
        end

        local parent_severity = diagnostics[parent]
        if not parent_severity or parent_severity > severity then
          diagnostics[parent] = severity
        end
      end
    end
  end
  Tree.set_diagnostics(diagnostics)

  if not ui.is_help_open() then
    if ui.is_search_open() then
      ui.update(M.tree.search.result)
    elseif ui.is_open() then
      ui.update(M.tree.root)
    end
  end
end, config.diagnostics.debounce_time)

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
    return fn.expand(bufname)
  else
    return false
  end
end

function M.setup()
  local cwd = get_netrw_dir()
  if cwd then
    M.tree.cwd = cwd
  else
    M.tree.cwd = uv.cwd()
  end

  async.run(function()
    M.tree.root = Tree.root(M.tree.cwd)
    vim.schedule(function()
      if cwd then
        M.open(true)
      end
    end)
  end)
end

return M
