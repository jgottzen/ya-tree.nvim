local scheduler = require("plenary.async.util").scheduler
local void = require("plenary.async.async").void
local Path = require("plenary.path")

local config = require("ya-tree.config").config
local lib = require("ya-tree.lib")
local debounce_trailing = require("ya-tree.debounce").debounce_trailing
local Nodes = require("ya-tree.nodes")
local git = require("ya-tree.git")
local ui = require("ya-tree.ui")
local utils = require("ya-tree.utils")
local log = require("ya-tree.log")

local api = vim.api
local fn = vim.fn
local uv = vim.loop

local M = {}

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
local function on_tab_new_entered()
  lib.open_window({ focus = config.auto_open.focus_tree })
end

---@async
local function on_tab_enter()
  lib.redraw()
end

---@async
---@param tabindex number
local function on_tab_closed(tabindex)
  local tabpage = lib.tabindex_to_tabpage(tabindex)
  if tabpage then
    lib.delete_tree(tabpage)
  end
end

---@async
---@param file string
---@param bufnr number
local function on_buf_add_and_file_post(file, bufnr)
  local tree = lib._get_tree()
  if tree and tree.buffers.root and file ~= "" and api.nvim_buf_get_option(bufnr, "buftype") == "" then
    -- BufFilePost is fired before the file is available on the file system, causing the node creation
    -- to fail, by deferring the call for a short time, we should be able to find the file
    vim.defer_fn(
      void(function()
        local node = tree.buffers.root:get_child_if_loaded(file) --[[@as YaTreeBufferNode]]
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
  local tree = lib._get_tree()

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

    local opts = { path = file, focus = true }
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
  local tree = lib._get_tree()
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
    lib._for_each_tree(function(tree)
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
        if not git_node and git_status_changed then
          tree.git_status.root:add_file(file)
        elseif git_node and git_status_changed then
          ---@cast git_node YaTreeGitStatusNode
          if not git_node:get_git_status() then
            tree.git_status.root:remove_file(file)
          end
        end
        if ui.is_git_status_open() then
          node = git_node
        end
      end

      -- only update the ui if something has changed, and the tree is for the current tabpage
      if tree.tabpage == tabpage and ui.is_open() and ((node and ui.is_node_rendered(node)) or git_status_changed) then
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
    local tree = lib._get_tree()
    -- since DirChanged is only subscribed to if config.cwd.follow is enabled,
    -- the tree.cwd is always bound to the tab cwd, and the root path of the
    -- tree doens't have to be checked
    if not tree or new_cwd == tree.cwd then
      return
    end

    tree.current_node = ui.is_open() and ui.get_current_node() or tree.current_node
    tree.cwd = new_cwd
    lib.change_root_node_for_tree(tree, new_cwd)
  elseif scope == "global" then
    lib._for_each_tree(function(tree)
      -- since DirChanged is only subscribed to if config.cwd.follow is enabled,
      -- the tree.cwd is always bound to the tab cwd, and the root path of the
      -- tree doens't have to be checked
      if new_cwd ~= tree.cwd then
        tree.cwd = new_cwd
        lib.change_root_node_for_tree(tree, new_cwd)
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
  local tree = lib._get_tree()
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

function M.setup()
  config = require("ya-tree.config").config

  ---@type number
  local group = api.nvim_create_augroup("YaTree", { clear = true })

  if config.auto_close then
    api.nvim_create_autocmd("WinClosed", {
      group = group,
      callback = void(function(input)
        local bufnr = tonumber(input.match) --[[@as number]]
        on_win_closed(bufnr)
      end),
      desc = "Close Neovim when the tree is the last window",
    })
  end

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
      local tabindex = tonumber(input.match) --[[@as number]]
      on_tab_closed(tabindex)
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

return M
