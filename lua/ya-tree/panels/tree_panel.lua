local lazy = require("ya-tree.lazy")

local async = lazy.require("ya-tree.async") ---@module "ya-tree.async"
local Config = lazy.require("ya-tree.config") ---@module "ya-tree.config"
local event = lazy.require("ya-tree.events.event") ---@module "ya-tree.events.event"
local job = lazy.require("ya-tree.job") ---@module "ya-tree.job"
local Logger = lazy.require("ya-tree.log") ---@module "ya-tree.log"
local Panel = require("ya-tree.panels.panel")
local Path = lazy.require("ya-tree.path") ---@module "ya-tree.path"
local ui = lazy.require("ya-tree.ui") ---@module "ya-tree.ui"
local utils = lazy.require("ya-tree.utils") ---@module "ya-tree.utils"

local api = vim.api
local fn = vim.fn

---@abstract
---@class Yat.Panel.Tree : Yat.Panel
---
---@field public root Yat.Node
---@field public current_node Yat.Node
---@field private previous_row integer
---@field protected path_lookup { [integer]: string, [integer]: string }
---@field protected renderers { container: Yat.Panel.Tree.Ui.Renderer[], leaf: Yat.Panel.Tree.Ui.Renderer[] }
---@field protected _container_min_diagnostic_severity DiagnosticSeverity
---@field protected _leaf_min_diagnostic_severity DiagnosticSeverity
local TreePanel = Panel:subclass("Yat.Panel.Tree")

function TreePanel.__tostring(self)
  return string.format(
    "<%s(TYPE=%s, winid=%s, bufnr=%s, root=%s)>",
    self.class.name,
    self.TYPE,
    self:winid(),
    self:bufnr(),
    tostring(self.root)
  )
end

---@protected
---@param _type Yat.Panel.Type
---@param sidebar Yat.Sidebar
---@param title string
---@param icon string
---@param keymap table<string, Yat.Action>
---@param renderers { container: Yat.Panel.Tree.Ui.Renderer[], leaf: Yat.Panel.Tree.Ui.Renderer[] }
---@param root Yat.Node
function TreePanel:init(_type, sidebar, title, icon, keymap, renderers, root)
  Panel.init(self, _type, sidebar, title, icon, keymap)
  self.root = root
  self.current_node = self.root
  self.path_lookup = {}
  self.renderers = renderers

  for _, renderer in ipairs(self.renderers.container) do
    if renderer.name == "diagnostics" then
      local renderer_config = renderer.config --[[@as Yat.Config.Renderers.Builtin.Diagnostics]]
      self._container_min_diagnostic_severity = renderer_config.directory_min_severity
      break
    end
  end
  self._container_min_diagnostic_severity = self._container_min_diagnostic_severity or vim.diagnostic.severity.ERROR

  for _, renderer in ipairs(self.renderers.leaf) do
    if renderer.name == "diagnostics" then
      local renderer_config = renderer.config --[[@as Yat.Config.Renderers.Builtin.Diagnostics]]
      self._leaf_min_diagnostic_severity = renderer_config.file_min_severity
      break
    end
  end
  self._leaf_min_diagnostic_severity = self._leaf_min_diagnostic_severity or vim.diagnostic.severity.HINT
end

---@param name Yat.Ui.Renderer.Name
---@return boolean
function TreePanel:has_renderer(name)
  for _, renderer in ipairs(self.renderers.container) do
    if renderer.name == name then
      return true
    end
  end
  for _, renderer in ipairs(self.renderers.leaf) do
    if renderer.name == name then
      return true
    end
  end
  return false
end

---@return DiagnosticSeverity severity
function TreePanel:container_min_severity()
  return self._container_min_diagnostic_severity
end

---@return DiagnosticSeverity severity
function TreePanel:leaf_min_severity()
  return self._leaf_min_diagnostic_severity
end

---@protected
function TreePanel:register_buffer_modified_event()
  self:register_autocmd_event(event.autocmd.BUFFER_MODIFIED, function(bufnr, file, match)
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
    local node = self.root:get_node(file)
    if node and node.modified ~= modified then
      node.modified = modified
      self:draw()
    end
  end
end

---@protected
function TreePanel:register_buffer_saved_event()
  self:register_autocmd_event(event.autocmd.BUFFER_SAVED, function(bufnr, file, match)
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
    Logger.get("panels").debug("changed file %q is in panel %s", file, tostring(self))
    local parent = self.root:get_node(file)
    if parent then
      parent:refresh()
      local node = parent:get_node(file)
      if node then
        node.modified = false
        async.scheduler()
        self:draw()
      end
    end
  end
end

---@protected
function TreePanel:register_buffer_enter_event()
  self:register_autocmd_event(event.autocmd.BUFFER_ENTER, function(bufnr, file, match)
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
  if self:is_open() and Config.config.follow_focused_file then
    self:expand_to_buffer(bufnr, file)
  end
end

---@async
---@param bufnr integer
---@param bufname string
function TreePanel:expand_to_buffer(bufnr, bufname)
  local ok, buftype = pcall(api.nvim_buf_get_option, bufnr, "buftype")
  if not ok or not ((buftype == "" and bufname ~= "") or buftype == "terminal") then
    return
  end

  if self.root:is_ancestor_of(bufname) or self.root.path == bufname then
    Logger.get("panels").debug("focusing on node %q", bufname)
    local node = self.root:expand({ to = bufname })
    if node then
      -- we need to allow the event loop to catch up when we enter a buffer after one was closed
      async.scheduler()
      self:draw(node)
    end
  end
end

---@protected
function TreePanel:register_dir_changed_event()
  if Config.config.cwd.follow then
    ---@param scope "window"|"tabpage"|"global"|"auto"
    ---@param new_cwd string
    self:register_autocmd_event(event.autocmd.DIR_CHANGED, function(_, new_cwd, scope)
      -- currently not available in the table passed to the callback
      if not vim.v.event.changed_window then
        local current_tabpage = api.nvim_get_current_tabpage()
        -- if the autocmd was fired because of a switch to a tab or window with a different
        -- cwd than the previous tab/window, it can safely be ignored.
        if scope == "global" or (scope == "tabpage" and current_tabpage == self.tabpage) then
          Logger.get("panels").debug("scope=%s, cwd=%s", scope, new_cwd)
          self:on_cwd_changed(new_cwd)
        end
      end
    end)
  end
end

---@protected
function TreePanel:register_dot_git_dir_changed_event()
  if Config.config.git.enable then
    self:register_git_event(event.git.DOT_GIT_DIR_CHANGED, function(repo)
      self:on_dot_git_dir_changed(repo)
    end)
  end
end

-- selene: allow(unused_variable)

---@async
---@protected
---@param repo Yat.Git.Repo
function TreePanel:on_dot_git_dir_changed(repo)
  if vim.v.exiting == vim.NIL and (self.root:is_ancestor_of(repo.toplevel) or vim.startswith(self.root.path, repo.toplevel)) then
    Logger.get("panels").debug("git repo %s changed", tostring(repo))
    self:draw(self:get_current_node())
  end
end

---@protected
function TreePanel:register_diagnostics_changed_event()
  if Config.config.diagnostics.enable then
    self:register_ya_tree_event(event.ya_tree.DIAGNOSTICS_CHANGED, function(severity_changed)
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
  if Config.config.dir_watcher.enable then
    self:register_ya_tree_event(event.ya_tree.FS_CHANGED, function(dir, filename)
      self:on_fs_changed_event(dir, filename)
    end)
  end
end

-- selene: allow(unused_variable)

---@async
---@protected
---@param dir string
---@param filenames string[]
---@diagnostic disable-next-line:unused-local
function TreePanel:on_fs_changed_event(dir, filenames) end

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
    paths = {}
    self.root:walk(function(node)
      if not node:is_container() and not node:is_hidden() then
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
  return fn.getcompletion(base, "file_in_path")
end

---@param bufnr integer
---@param path string
function TreePanel:complete_func_file_in_path(bufnr, path)
  api.nvim_buf_set_option(bufnr, "completefunc", "v:lua._ya_tree_panels_trees_file_in_path_complete")
  api.nvim_buf_set_option(bufnr, "omnifunc", "")
  -- only complete on _all_ files if the node is located below the home dir
  if vim.startswith(path, Path.path.home .. Path.path.sep) then
    api.nvim_buf_set_option(bufnr, "path", path .. "/**")
  else
    api.nvim_buf_set_option(bufnr, "path", path .. "/*")
  end
end

-- selene: allow(unused_variable)

---@abstract
---@protected
---@param node? Yat.Node
---@return fun(bufnr: integer)|string|nil complete_func
---@return string|nil search_root
---@diagnostic disable-next-line:unused-local,missing-return
function TreePanel:get_complete_func_and_search_root(node) end

---@async
---@param node? Yat.Node.FsBasedNode
function TreePanel:search_for_node(node)
  local completion, search_root = self:get_complete_func_and_search_root(node)
  if not search_root then
    return
  end

  local log = Logger.get("panels")
  local path = ui.nui_input({ title = " Path: ", completion = completion })
  if path then
    local cmd, args = utils.build_search_arguments(path, search_root, false, Config.config)
    if not cmd then
      return
    end

    local code, stdout, stderr = job.async_run({ cmd = cmd, args = args, cwd = search_root })
    if code == 0 then
      local lines = vim.split(stdout or "", "\n", { plain = true, trimempty = true })
      log.debug("%q found %s matches for %q in %q", cmd, #lines, path, search_root)

      if #lines > 0 then
        local first = lines[1]
        if first:sub(-1) == Path.path.sep then
          first = first:sub(1, -2)
        end
        local result_node = self.root:expand({ to = first })
        async.scheduler()
        self:draw(result_node)
      else
        utils.notify(string.format("%q cannot be found in the tree", path))
      end
    else
      log.error("%q with args %s failed with code %s and message %s", cmd, args, code, stderr)
    end
  end
end

---@async
function TreePanel:refresh()
  local log = Logger.get("panels")
  if self.refreshing or vim.v.exiting ~= vim.NIL then
    log.debug("refresh already in progress or vim is exiting, aborting refresh")
    return
  end

  self.refreshing = true
  log.debug("refreshing %q panel", self.TYPE)
  self.root:refresh({ recurse = true, refresh_git = true })
  self:draw(self:get_current_node())
  self.refreshing = false
end

---@protected
---@param action Yat.Action
---@return function handler
function TreePanel:create_keymap_function(action)
  return function()
    local node = self:get_current_node()
    if node or action.node_independent then
      if node then
        self.current_node = node
      end
      async.void(action.fn)(self, node)
    end
  end
end

---@protected
function TreePanel:create_move_to_name_autocmd()
  api.nvim_create_autocmd("CursorMoved", {
    group = self.window_augroup,
    buffer = self:bufnr(),
    callback = function()
      self:move_cursor_to_name()
    end,
    desc = "Moving cursor to name",
  })
end

---@async
function TreePanel:expand_to_current_buffer()
  local edit_win = self.sidebar:edit_win()
  if edit_win then
    local bufnr = api.nvim_win_get_buf(edit_win)
    local bufname = api.nvim_buf_get_name(bufnr)
    self:expand_to_buffer(bufnr, bufname)
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
  return path and self.root:get_node(path) or nil
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
      local node = self.root:get_node(path)
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
  -- if the node has been hidden after a toggle
  -- go upwards in the tree until we find one that's displayed
  while node and node:is_hidden() and node.parent do
    node = node.parent
  end
  if node then
    local row = self.path_lookup[node.path]
    if row then
      Logger.get("panels").debug("node %s is at row %s", node.path, row)
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

---@protected
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

  local log = Logger.get("panels")
  for _, renderer in ipairs(renderers) do
    local results = renderer.fn(node, context, renderer.config)
    if results then
      for _, result in ipairs(results) do
        if result.text then
          if not result.highlight then
            log.error("renderer %q didn't return a highlight name for node %q, renderer returned %s", renderer.name, node.path, result)
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
  ---@type string[], Yat.Ui.HighlightGroup[][], Yat.Ui.RenderContext
  local lines, highlights, context, linenr = {}, {}, { panel_type = self.TYPE, config = Config.config, indent_markers = {} }, 1
  local container_renderers, leaf_renderers = self.renderers.container, self.renderers.leaf
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
    lines[linenr], highlights[linenr] = render_node(node, context, has_children and container_renderers or leaf_renderers)

    if has_children and node.expanded then
      ---@param child Yat.Node
      local children = vim.tbl_filter(function(child)
        return not child:is_hidden()
      end, node:children()) --[=[@as Yat.Node[]]=]
      local nr_of_children = #children
      for i, child in ipairs(children) do
        append_node(child, depth + 1, i == nr_of_children)
      end
    end
  end

  lines[linenr], highlights[linenr] = self:render_header()
  append_node(self.root, 0, false)

  return lines, highlights
end

---@param node? Yat.Node
function TreePanel:draw(node)
  if self:is_open() then
    local lines, highlights = self:render()
    self:set_content(lines, highlights)
    if node then
      self:focus_node(node)
    end
  end
end

return TreePanel
