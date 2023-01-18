local git = require("ya-tree.git")
local job = require("ya-tree.job")
local log = require("ya-tree.log").get("panels")
local meta = require("ya-tree.meta")
local Panel = require("ya-tree.panels.panel")
local scheduler = require("ya-tree.async").scheduler
local ui = require("ya-tree.ui")
local utils = require("ya-tree.utils")
local void = require("ya-tree.async").void

local api = vim.api

---@abstract
---@class Yat.Panel.Tree : Yat.Panel
---@field new async fun(self: Yat.Panel.Tree, type: Yat.Panel.Type, sidebar: Yat.Sidebar, title: string, icon: string, actions: table<string, Yat.Action>, renderers: Yat.Panel.TreeRenderers, node: Yat.Node): Yat.Panel.Tree
---@overload async fun(type: Yat.Panel.Type, sidebar: Yat.Sidebar, title: string, icon: string, actions: table<string, Yat.Action>, renderers: Yat.Panel.TreeRenderers, node: Yat.Node): Yat.Panel.Tree
---@field class fun(self: Yat.Panel.Tree): Yat.Class
---@field static Yat.Panel.Tree
---@field super Yat.Panel
---
---@field public root Yat.Node
---@field public current_node Yat.Node
---@field private previous_row integer
---@field protected path_lookup { [integer]: string, [integer]: string }
---@field protected renderers Yat.Panel.TreeRenderers
---@field protected _directory_min_diagnostic_severity integer
---@field protected _file_min_diagnostic_severity integer
local TreePanel = meta.create_class("Yat.Panel.Tree", Panel)

function TreePanel.__tostring(self)
  return string.format(
    "<class %s(TYPE=%s, winid=%s, bufnr=%s, root=%s)>",
    self:class():name(),
    self.TYPE,
    self:winid(),
    self:bufnr(),
    tostring(self.root)
  )
end

---@async
---@protected
---@param _type Yat.Panel.Type
---@param sidebar Yat.Sidebar
---@param title string
---@param icon string
---@param keymap table<string, Yat.Action>
---@param renderers Yat.Panel.TreeRenderers
---@param root Yat.Node
function TreePanel:init(_type, sidebar, title, icon, keymap, renderers, root)
  self.super:init(_type, sidebar, title, icon, keymap)
  self.root = root
  self.current_node = self.root
  self.path_lookup = {}
  self.renderers = renderers

  for _, renderer in ipairs(self.renderers.directory) do
    if renderer.name == "diagnostics" then
      local renderer_config = renderer.config --[[@as Yat.Config.Renderers.Builtin.Diagnostics]]
      self._directory_min_diagnostic_severity = renderer_config.directory_min_severity
      break
    end
  end
  self._directory_min_diagnostic_severity = self._directory_min_diagnostic_severity or vim.diagnostic.severity.ERROR

  for _, renderer in ipairs(self.renderers.file) do
    if renderer.name == "diagnostics" then
      local renderer_config = renderer.config --[[@as Yat.Config.Renderers.Builtin.Diagnostics]]
      self._file_min_diagnostic_severity = renderer_config.file_min_severity
    end
  end
  self._file_min_diagnostic_severity = self._file_min_diagnostic_severity or vim.diagnostic.severity.HINT
end

---@return integer severity
function TreePanel:directory_min_severity()
  return self._directory_min_diagnostic_severity
end

---@return integer severity
function TreePanel:file_min_severity()
  return self._file_min_diagnostic_severity
end

---@protected
function TreePanel:register_buffer_modified_event()
  local event = require("ya-tree.events.event").autocmd.BUFFER_MODIFIED
  self:register_autocmd_event(event, function(bufnr, file, match)
    self:on_buffer_modified(bufnr, file, match)
  end)
end

-- selene: allow(unused_variable)

---@async
---@protected
---@param bufnr integer
---@param file string
---@param match string
---@diagnostic disable-next-line:unused-local
function TreePanel:on_buffer_modified(bufnr, file, match)
  if file ~= "" and api.nvim_buf_get_option(bufnr, "buftype") == "" then
    local modified = api.nvim_buf_get_option(bufnr, "modified") --[[@as boolean]]
    local node = self.root:get_child_if_loaded(file)
    if node and node.modified ~= modified then
      node.modified = modified
      self:draw()
    end
  end
end

---@protected
function TreePanel:register_buffer_saved_event()
  local event = require("ya-tree.events.event").autocmd.BUFFER_SAVED
  self:register_autocmd_event(event, function(bufnr, file, match)
    self:on_buffer_saved(bufnr, file, match)
  end)
end

-- selene: allow(unused_variable)

---@async
---@protected
---@param bufnr integer
---@param file string
---@param match string
---@diagnostic disable-next-line:unused-local
function TreePanel:on_buffer_saved(bufnr, file, match)
  if self.root:is_ancestor_of(file) then
    log.debug("changed file %q is in panel %s", file, tostring(self))
    local parent = self.root:get_child_if_loaded(file)
    if parent then
      parent:refresh()
      local node = parent:get_child_if_loaded(file)
      if node then
        node.modified = false
        self:draw()
      end
    end
  end
end

---@protected
function TreePanel:register_buffer_enter_event()
  local event = require("ya-tree.events.event").autocmd.BUFFER_ENTER
  self:register_autocmd_event(event, function(bufnr, file, match)
    self:on_buffer_enter(bufnr, file, match)
  end)
end

-- selene: allow(unused_variable)

---@async
---@protected
---@param bufnr integer
---@param file string
---@param match string
---@diagnostic disable-next-line:unused-local
function TreePanel:on_buffer_enter(bufnr, file, match)
  local ok, buftype = pcall(api.nvim_buf_get_option, bufnr, "buftype")
  if not ok or not ((buftype == "" and file ~= "") or buftype == "terminal") then
    return
  end

  local config = require("ya-tree.config").config
  if config.follow_focused_file then
    if self:is_open() then
      if self.root:is_ancestor_of(file) then
        log.debug("focusing on node %q", file)
        local node = self.root:expand({ to = file })
        if node then
          -- we need to allow the event loop to catch up when we enter a buffer after one was closed
          scheduler()
          self:draw(node)
        end
      end
    end
  end
end

---@protected
function TreePanel:register_dir_changed_event()
  local config = require("ya-tree.config").config
  if config.cwd.follow then
    local event = require("ya-tree.events.event").autocmd.DIR_CHANGED
    ---@param scope "window"|"tabpage"|"global"|"auto"
    ---@param new_cwd string
    self:register_autocmd_event(event, function(_, new_cwd, scope)
      -- currently not available in the table passed to the callback
      if not vim.v.event.changed_window then
        local current_tabpage = api.nvim_get_current_tabpage()
        -- if the autocmd was fired because of a switch to a tab or window with a different
        -- cwd than the previous tab/window, it can safely be ignored.
        if scope == "global" or (scope == "tabpage" and current_tabpage == self.tabpage) then
          log.debug("scope=%s, cwd=%s", scope, new_cwd)
          self:on_cwd_changed(new_cwd)
        end
      end
    end)
  end
end

---@protected
function TreePanel:register_dot_git_dir_changed_event()
  local config = require("ya-tree.config").config
  if config.git.enable then
    local event = require("ya-tree.events.event").git.DOT_GIT_DIR_CHANGED
    self:register_git_event(event, function(repo, fs_changes)
      self:on_dot_git_dir_changed(repo, fs_changes)
    end)
  end
end

-- selene: allow(unused_variable)

---@async
---@protected
---@param repo Yat.Git.Repo
---@param fs_changes boolean
---@diagnostic disable-next-line:unused-local
function TreePanel:on_dot_git_dir_changed(repo, fs_changes)
  if vim.v.exiting == vim.NIL and (self.root:is_ancestor_of(repo.toplevel) or repo.toplevel:find(self.root.path, 1, true) ~= nil) then
    log.debug("git repo %s changed", tostring(repo))
    self:draw(self:get_current_node())
  end
end

---@protected
function TreePanel:register_diagnostics_changed_event()
  local config = require("ya-tree.config").config
  if config.diagnostics.enable then
    local event = require("ya-tree.events.event").ya_tree.DIAGNOSTICS_CHANGED
    self:register_ya_tree_event(event, function(severity_changed)
      self:on_diagnostics_event(severity_changed)
    end)
  end
end

-- selene: allow(unused_variable)

---@async
---@protected
---@param severity_changed boolean
---@diagnostic disable-next-line:unused-local
function TreePanel:on_diagnostics_event(severity_changed)
  if severity_changed then
    self:draw()
  end
end

---@protected
function TreePanel:register_fs_changed_event()
  local config = require("ya-tree.config").config
  if config.dir_watcher.enable then
    local event = require("ya-tree.events.event").ya_tree.FS_CHANGED
    self:register_ya_tree_event(event, function(dir, filename)
      self:on_fs_changed_event(dir, filename)
    end)
  end
end

-- selene: allow(unused_variable)

---@async
---@virtual
---@protected
---@param dir string
---@param filenames string[]
---@diagnostic disable-next-line:unused-local
function TreePanel:on_fs_changed_event(dir, filenames) end
TreePanel:virtual("on_fs_changed_event")

do
  ---@type string[]
  local paths = {}

  -- selene: allow(global_usage)

  ---@param start integer
  ---@param base string
  ---@return integer|string[]
  _G._ya_tree_panels_trees_loaded_nodes_complete = function(start, base)
    if start == 1 then
      return 0
    end
    ---@param item string
    return vim.tbl_filter(function(item)
      return item:find(base, 1, true) ~= nil
    end, paths)
  end

  ---@param bufnr integer
  function TreePanel:complete_func_loaded_nodes(bufnr)
    local config = require("ya-tree.config").config
    paths = {}
    self.root:walk(function(node)
      if not node:is_directory() and not node:is_hidden(config) then
        paths[#paths + 1] = node.path:sub(#self.root.path + 2)
      end
    end)
    api.nvim_buf_set_option(bufnr, "completefunc", "v:lua._ya_tree_panels_trees_loaded_nodes_complete")
    api.nvim_buf_set_option(bufnr, "omnifunc", "")
  end
end

-- selene: allow(global_usage)

---@param start integer
---@param base string
---@return integer|string[]
_G._ya_tree_panels_trees_file_in_path_complete = function(start, base)
  if start == 1 then
    return 0
  end
  return vim.fn.getcompletion(base, "file_in_path")
end

---@param bufnr integer
---@param node? Yat.Node
function TreePanel:complete_func_file_in_path(bufnr, node)
  local home = os.getenv("HOME") --[[@as string]]
  local path = node and node.path or self.root.path
  api.nvim_buf_set_option(bufnr, "completefunc", "v:lua._ya_tree_panels_trees_file_in_path_complete")
  api.nvim_buf_set_option(bufnr, "omnifunc", "")
  -- only complete on _all_ files if the node is located below the home dir
  if #path > #home then
    api.nvim_buf_set_option(bufnr, "path", path .. "/**")
  else
    api.nvim_buf_set_option(bufnr, "path", path .. "/*")
  end
end

-- selene: allow(unused_variable)

---@virtual
---@protected
---@param node Yat.Node
---@return fun(bufnr: integer, node?: Yat.Node)|string complete_func
---@return string? search_root
---@diagnostic disable-next-line:unused-local,missing-return
function TreePanel:get_complete_func_and_search_root(node) end
TreePanel:virtual("get_complete_func_and_search_root")

---@async
---@param node Yat.Node
function TreePanel:search_for_node(node)
  local completion, search_root = self:get_complete_func_and_search_root(node)
  search_root = search_root or self.root.path

  local path = ui.nui_input({ title = " Path: ", completion = completion })
  if path then
    local cmd, args = utils.build_search_arguments(path, search_root, false)
    if not cmd then
      return
    end

    local code, stdout, stderr = job.async_run({ cmd = cmd, args = args, cwd = search_root })
    if code == 0 then
      local lines = vim.split(stdout or "", "\n", { plain = true, trimempty = true }) --[=[@as string[]]=]
      log.debug("%q found %s matches for %q in %q", cmd, #lines, path, search_root)

      if #lines > 0 then
        local first = lines[1]
        if first:sub(-1) == utils.os_sep then
          first = first:sub(1, -2)
        end
        local result_node = self.root:expand({ to = first })
        scheduler()
        self:draw(result_node)
      else
        utils.notify(string.format("%q cannot be found in the tree", path))
      end
    else
      log.error("%q with args %s failed with code %s and message %s", cmd, args, code, stderr)
    end
  end
end

-- selene: allow(unused_variable)

---@async
---@virtual
---@param path string
---@diagnostic disable-next-line:unused-local
function TreePanel:change_root_node(path) end
TreePanel:virtual("change_root_node")

---@async
function TreePanel:refresh()
  if self.refreshing or vim.v.exiting ~= vim.NIL then
    log.debug("refresh already in progress or vim is exiting, aborting refresh")
    return
  end
  self.refreshing = true
  log.debug("refreshing %q panel", self.TYPE)

  self.root:refresh({ recurse = true, refresh_git = true })
  self:draw(self.current_node)
  self.refreshing = false
end

---@param repo Yat.Git.Repo
---@param path string
function TreePanel:set_git_repo_for_path(repo, path)
  local node = self.root:get_child_if_loaded(path) or self.root:get_child_if_loaded(repo.toplevel)
  if node and node.repo ~= repo then
    log.debug("setting git repo for panel %s on node %s", self.TYPE, node.path)
    node:set_git_repo(repo)
    self:draw()
  end
end

---@async
---@param node Yat.Node
---@return Yat.Git.Repo|nil repo
function TreePanel:check_node_for_git_repo(node)
  if self.refreshing or vim.v.exiting ~= vim.NIL then
    log.debug("refresh already in progress or vim is exiting, aborting refresh")
    return
  end
  self.refreshing = true
  log.debug("checking if %s is in a git repository", node.path)
  local repo = git.create_repo(node.path)
  if repo then
    node:set_git_repo(repo)
    repo:status():refresh({ ignored = true })
  end
  self.refreshing = false
  return repo
end

---@param panel Yat.Panel.Tree
---@param action Yat.Action
---@return function handler
local function create_keymap_function(panel, action)
  return function()
    local node = panel:get_current_node()
    if node or action.node_independent then
      if node then
        panel.current_node = node
      end
      void(action.fn)(panel, node)
    end
  end
end

---@protected
function TreePanel:apply_mappings()
  local opts = { buffer = self:bufnr(), silent = true, nowait = true }
  for key, action in pairs(self.keymap) do
    local rhs = create_keymap_function(self, action)

    ---@type table<string, boolean>
    local modes = {}
    for _, mode in ipairs(action.modes) do
      modes[mode] = true
    end
    opts.desc = action.desc
    for mode in pairs(modes) do
      if not pcall(vim.keymap.set, mode, key, rhs, opts) then
        log.error("couldn't construct mapping for key %q!", key)
      end
    end
  end
end

---@protected
function TreePanel:on_window_open()
  if require("ya-tree.config").config.move_cursor_to_name then
    api.nvim_create_autocmd("CursorMoved", {
      group = self.window_augroup,
      buffer = self:bufnr(),
      callback = function()
        self:move_cursor_to_name()
      end,
      desc = "Moving cursor to name",
    })
  end
end

---@protected
function TreePanel:on_win_closed()
  self.path_lookup = {}
end

---@return Yat.Node|nil node
function TreePanel:get_current_node()
  local winid = self:winid()
  if not winid then
    return
  end
  local row = api.nvim_win_get_cursor(winid)[1]
  return self:get_node_at_row(row)
end

---@param row integer
---@return Yat.Node|nil
function TreePanel:get_node_at_row(row)
  local path = self.path_lookup[row]
  return path and self.root:get_child_if_loaded(path) or nil
end

---@return Yat.Node[]
function TreePanel:get_selected_nodes()
  local from, to = self:get_selected_rows()
  return self:get_nodes(from, to)
end

---@param from integer
---@param to integer
---@return Yat.Node[] nodes
function TreePanel:get_nodes(from, to)
  ---@type Yat.Node[]
  local nodes = {}
  for row = from, to do
    local path = self.path_lookup[row]
    if path then
      local node = self.root:get_child_if_loaded(path)
      if node then
        nodes[#nodes + 1] = node
      end
    end
  end
  return nodes
end

---@generic T : Yat.Node
---@param start T
---@param forward boolean
---@return T[]
function TreePanel:flatten_from(start, forward)
  ---@cast start Yat.Node
  ---@type Yat.Node[]
  local nodes = {}

  if self.root:is_ancestor_of(start.path) or self.root.path == start.path then
    ---@param node Yat.Node
    local function flatten_children(node)
      if forward and node.path ~= start.path then
        nodes[#nodes + 1] = node
      end
      if node:has_children() and node.expanded then
        for _, child in node:iterate_children({ reverse = not forward }) do
          flatten_children(child)
        end
      end
      if not forward and node.path ~= start.path then
        nodes[#nodes + 1] = node
      end
    end

    ---@param node Yat.Node
    ---@param from Yat.Node
    local function flatten_parent(node, from)
      if self.root:is_ancestor_of(node.path) or self.root.path == node.path then
        for _, child in node:iterate_children({ reverse = not forward, from = from }) do
          flatten_children(child)
        end
        if not forward and node.path ~= self.root.path then
          nodes[#nodes + 1] = node
        end
        if node.parent then
          flatten_parent(node.parent, node)
        end
      end
    end

    if forward and start:has_children() then
      flatten_children(start)
    end
    if start.parent then
      flatten_parent(start.parent, start)
    end
    if not forward then
      nodes[#nodes + 1] = self.root
    end
  end

  return nodes
end

---@generic T : Yat.Node
---@param start_node T
---@param forward boolean
---@param predicate fun(node: T): boolean
---@return T?
function TreePanel:get_first_node_that_matches(start_node, forward, predicate)
  ---@cast start_node Yat.Node
  local nodes = self:flatten_from(start_node, forward)
  for _, node in ipairs(nodes) do
    if predicate(node) then
      return node
    end
  end
end

---@param node Yat.Node
function TreePanel:focus_node(node)
  local config = require("ya-tree.config").config

  -- if the node has been hidden after a toggle
  -- go upwards in the tree until we find one that's displayed
  while node and node:is_hidden(config) and node.parent do
    node = node.parent
  end
  if node then
    local row = self.path_lookup[node.path]
    if row then
      log.debug("node %s is at row %s", node.path, row)
      self:focus_row(row)
    end
  end
end

---@param node Yat.Node the node to open
---@param cmd Yat.Action.Files.Open.Mode
function TreePanel:open_node(node, cmd)
  api.nvim_set_current_win(self.sidebar:edit_win())
  node:edit(cmd)
end

function TreePanel:move_cursor_to_name()
  local winid = self:winid()
  if not winid then
    return
  end
  local row, col = unpack(api.nvim_win_get_cursor(winid))
  local node = self:get_node_at_row(row)
  if not node or row == self.previous_row then
    return
  end

  self.previous_row = row
  -- don't move the cursor on the root node
  if node == self.root then
    return
  end

  local line = api.nvim_get_current_line()
  local column = (line:find(node.name, 1, true) or 0) - 1
  if column > 0 and column ~= col then
    api.nvim_win_set_cursor(winid, { row, column })
  end
end

---@param pos integer
---@param padding string
---@param text string
---@param highlight string
---@return integer end_position, string content, Yat.Ui.HighlightGroup highlight
local function line_part(pos, padding, text, highlight)
  local from = pos + #padding
  local size = #text
  local group = {
    name = highlight,
    from = from,
    to = from + size,
  }
  return group.to, string.format("%s%s", padding, text), group
end

---@param node Yat.Node
---@param context Yat.Ui.RenderContext
---@param renderers Yat.Panel.Tree.Ui.Renderer[]
---@return string text, Yat.Ui.HighlightGroup[] highlights
local function render_node(node, context, renderers)
  ---@type string[], Yat.Ui.HighlightGroup[]
  local content, highlights, pos = {}, {}, 0

  for _, renderer in ipairs(renderers) do
    local results = renderer.fn(node, context, renderer.config)
    if results then
      for _, result in ipairs(results) do
        if result.text then
          if not result.highlight then
            log.error("renderer %s didn't return a highlight name for node %q, renderer returned %s", renderer.name, node.path, result)
          end
          pos, content[#content + 1], highlights[#highlights + 1] = line_part(pos, result.padding or "", result.text, result.highlight)
        end
      end
    end
  end

  return table.concat(content), highlights
end

---@protected
---@return string[] lines
---@return Yat.Ui.HighlightGroup[][] highlights
function TreePanel:render()
  local config = require("ya-tree.config").config
  ---@type string[], Yat.Ui.HighlightGroup[][], Yat.Ui.RenderContext
  local lines, highlights, context, linenr = {}, {}, { panel_type = self.TYPE, config = config, indent_markers = {} }, 0
  local directory_renderers, file_renderers = self.renderers.directory, self.renderers.file
  self.path_lookup = {}

  ---@param node Yat.Node
  ---@param depth integer
  ---@param last_child boolean
  local function append_node(node, depth, last_child)
    linenr = linenr + 1
    context.depth = depth
    context.last_child = last_child
    self.path_lookup[node.path] = linenr
    self.path_lookup[linenr] = node.path
    local has_children = node:has_children()
    lines[linenr], highlights[linenr] = render_node(node, context, has_children and directory_renderers or file_renderers)

    if has_children and node.expanded then
      local children = vim.tbl_filter(function(child)
        return not child:is_hidden(config)
      end, node:children()) --[=[@as Yat.Node[]]=]
      local nr_of_children = #children
      for i, child in ipairs(children) do
        append_node(child, depth + 1, i == nr_of_children)
      end
    end
  end

  linenr = 1
  lines[linenr], highlights[linenr] = self:render_header()
  append_node(self.root, 0, false)

  return lines, highlights
end

---@param node? Yat.Node
---@param opts? { focus_panel?: boolean }
---  - {opts.focus_panel?} `boolean`
function TreePanel:draw(node, opts)
  if self:is_open() then
    opts = opts or {}
    local lines, highlights = self:render()
    self:set_content(lines, highlights)
    if opts.focus_panel then
      self:focus()
    end
    if node then
      self:focus_node(node)
    end
  end
end

return TreePanel
