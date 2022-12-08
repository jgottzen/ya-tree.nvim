local scheduler = require("plenary.async.util").scheduler
local void = require("plenary.async").void
local Path = require("plenary.path")

local Canvas = require("ya-tree.ui.canvas")
local events = require("ya-tree.events")
local autocmd_event = require("ya-tree.events.event").autocmd
local git_event = require("ya-tree.events.event").git
local yatree_event = require("ya-tree.events.event").ya_tree
local fs = require("ya-tree.fs")
local git = require("ya-tree.git")
local meta = require("ya-tree.meta")
local Trees = require("ya-tree.trees")
local BuffersTree = require("ya-tree.trees.buffers")
local FilesystemTree = require("ya-tree.trees.filesystem")
local GitTree = require("ya-tree.trees.git")
local SearchTree = require("ya-tree.trees.search")
local ui = require("ya-tree.ui")
local utils = require("ya-tree.utils")
local log = require("ya-tree.log")("sidebar")

local api = vim.api
local uv = vim.loop

---@class Yat.Sidebar.Section
---@field tree Yat.Tree
---@field from integer
---@field to integer
---@field path_lookup { [integer]: string, [integer]: string }
---@field directory_min_diagnostic_severity integer
---@field file_min_diagnostic_severity integer

---@param section Yat.Sidebar.Section
---@return string
local function section_tostring(section)
  return string.format("(%s, [%s,%s])", section.tree.TYPE, section.from, section.to)
end

---@class Yat.Sidebar : Yat.Object
---@field new async fun(self: Yat.Sidebar, tabpage: integer): Yat.Sidebar
---@overload async fun(tabpage: integer): Yat.Sidebar
---@field class fun(self: Yat.Sidebar): Yat.Sidebar
---
---@field package canvas Yat.Ui.Canvas
---@field private _tabpage integer
---@field private single_mode boolean
---@field private tree_order table<Yat.Trees.Type, integer>
---@field private always_shown_trees Yat.Trees.Type[]
---@field private sections Yat.Sidebar.Section[]
---@field private registered_events { autocmd: table<Yat.Events.AutocmdEvent, integer>, git: table<Yat.Events.GitEvent, integer>, yatree: table<Yat.Events.YaTreeEvent, integer> }
local Sidebar = meta.create_class("Yat.Sidebar")

---@param other Yat.Sidebar
---@return boolean
function Sidebar.__eq(self, other)
  return self._tabpage == other._tabpage
end

function Sidebar.__tostring(self)
  return string.format("Sidebar(%s, sections=[%s])", self._tabpage, table.concat(vim.tbl_map(section_tostring, self.sections), ", "))
end

---@param tree Yat.Tree
---@return Yat.Sidebar.Section
local function create_section(tree)
  ---@type Yat.Sidebar.Section
  local section = {
    tree = tree,
    from = 0,
    to = 0,
    path_lookup = {},
    directory_min_diagnostic_severity = tree.renderers.extra.directory_min_diagnostic_severity,
    file_min_diagnostic_severity = tree.renderers.extra.file_min_diagnostic_severity,
  }
  return section
end

---@async
---@private
---@param tabpage integer
function Sidebar:init(tabpage)
  local config = require("ya-tree.config").config.sidebar
  self._tabpage = tabpage
  self.canvas = Canvas:new(config.position, config.size, config.number, config.relativenumber, function(row)
    return self:get_tree_and_node(row)
  end)
  self.single_mode = config.single_mode
  self.tree_order = {}
  for i, tree_type in ipairs(config.tree_order) do
    self.tree_order[tree_type] = i
  end
  self.always_shown_trees = config.trees_always_shown
  self.registered_events = { autocmd = {}, git = {}, yatree = {} }
  self.sections = {}
  local tree_types = self.single_mode and { self.always_shown_trees[1] } or self.always_shown_trees
  local cwd = uv.cwd() --[[@as string]]
  for _, tree_type in ipairs(tree_types) do
    local tree = Trees.create_tree(self._tabpage, tree_type, cwd)
    if tree then
      self:add_section(tree)
    end
  end
  self:sort_sections()

  log.info("created new sidebar %s", tostring(self))
end

---@package
function Sidebar:delete()
  self.canvas:close()
  for i = #self.sections, 1, -1 do
    self:delete_section(i)
  end
  for event, count in pairs(self.registered_events.autocmd) do
    if count > 0 then
      log.error("autocmd event %s is still registered with count %s", events.get_event_name(event), count)
    end
  end
  for event, count in pairs(self.registered_events.git) do
    if count > 0 then
      log.error("git event %s is still registered with count %s", events.get_event_name(event), count)
    end
  end
  for event, count in pairs(self.registered_events.yatree) do
    if count > 0 then
      log.error("yatree event %s is still registered with count %s", events.get_event_name(event), count)
    end
  end
  log.info("deleted sidebar %s for tabpage %s", tostring(self), self._tabpage)
end

---@return integer tabpage
function Sidebar:tabpage()
  return self._tabpage
end

---@private
---@param tree Yat.Tree
---@param pos? integer
function Sidebar:add_section(tree, pos)
  table.insert(self.sections, pos or (#self.sections + 1), create_section(tree))
  self:register_events_for_tree(tree)
end

---@private
function Sidebar:sort_sections()
  table.sort(self.sections, function(a, b)
    local a_order = self.tree_order[a.tree.TYPE] or 1000
    local b_order = self.tree_order[b.tree.TYPE] or 1000
    return a_order < b_order
  end)
end

---@private
---@param index integer
function Sidebar:delete_section(index)
  local section = self.sections[index]
  log.info("deleteing section %s", section_tostring(section))
  local tree = section.tree
  for event in pairs(tree.supported_events.autocmd) do
    self:remove_autocmd_event(event)
  end
  for event in pairs(tree.supported_events.git) do
    self:remove_git_event(event)
  end
  for event in pairs(tree.supported_events.yatree) do
    self:remove_yatree_event(event)
  end
  local config = require("ya-tree.config").config
  if tree.TYPE == "filesystem" and config.dir_watcher.enable then
    self:remove_yatree_event(yatree_event.FS_CHANGED)
  end
  tree:delete()
  table.remove(self.sections, index)
end

---@async
---@private
---@param tree_type Yat.Trees.Type
---@param tree_creator fun(): Yat.Tree
---@param new_root_node? string
---@return Yat.Tree
function Sidebar:get_or_create_tree(tree_type, tree_creator, new_root_node)
  local tree = self:get_tree(tree_type)
  if tree then
    if new_root_node then
      tree:change_root_node(new_root_node)
    end
    if self.single_mode and self.sections[1].tree.TYPE ~= tree.TYPE then
      self:delete_section(1)
    end
  else
    tree = tree_creator()
    self:add_tree(tree)
  end
  return tree
end

---@async
---@param path? string
---@return Yat.Trees.Filesystem
function Sidebar:filesystem_tree(path)
  path = path or uv.cwd() --[[@as string]]
  return self:get_or_create_tree("filesystem", function()
    return FilesystemTree:new(self._tabpage, path)
  end, path) --[[@as Yat.Trees.Filesystem]]
end

---@async
---@param repo Yat.Git.Repo
---@return Yat.Trees.Git
function Sidebar:git_tree(repo)
  return self:get_or_create_tree("git", function()
    return GitTree:new(self._tabpage, repo)
  end, repo.toplevel) --[[@as Yat.Trees.Git]]
end

---@async
---@return Yat.Trees.Buffers
function Sidebar:buffers_tree()
  return self:get_or_create_tree("buffers", function()
    return BuffersTree:new(self._tabpage, uv.cwd())
  end) --[[@as Yat.Trees.Buffers]]
end

---@async
---@param path string
---@return Yat.Trees.Search
function Sidebar:search_tree(path)
  return self:get_or_create_tree("search", function()
    return SearchTree:new(self._tabpage, path) --[[@as Yat.Trees.Search]]
  end, path) --[[@as Yat.Trees.Search]]
end

---@param tree_type Yat.Trees.Type
---@return Yat.Tree|nil tree
function Sidebar:get_tree(tree_type)
  local section = self:get_section(tree_type)
  return section and section.tree
end

---@async
---@param tree Yat.Tree
function Sidebar:add_tree(tree)
  if self.single_mode then
    if self.sections[1].tree == tree then
      return
    end
    -- don't delete the filesystem tree section
    if self.sections[1].tree.TYPE ~= "filesystem" then
      self:delete_section(1)
    end
    self:add_section(tree, 1)
  else
    for _, section in pairs(self.sections) do
      if section.tree == tree then
        section.tree = tree
        return
      end
    end
    self:add_section(tree)
    self:sort_sections()
  end
end

---@async
---@param tree Yat.Tree
---@param force? boolean
---@return Yat.Tree? tree
function Sidebar:close_tree(tree, force)
  if self.single_mode then
    if tree.TYPE ~= "filesystem" then
      self:delete_section(1)
      -- the filesystem tree is never deleted, reuse it if it's present
      if not (self.sections[1] and self.sections[1].tree.TYPE == "filesystem") then
        for i = #self.sections, 1, -1 do
          self:delete_section(i)
        end
        self.sections = {}
        self:add_section(FilesystemTree:new(self._tabpage, uv.cwd()))
      end
      return self.sections[1].tree
    end
  else
    if (force or not vim.tbl_contains(self.always_shown_trees, tree.TYPE)) and #self.sections > 1 then
      for i = #self.sections, 1, -1 do
        if self.sections[i].tree == tree then
          self:delete_section(i)
          if i >= #self.sections then
            return self.sections[#self.sections].tree
          else
            return self.sections[i].tree
          end
        end
      end
    end
  end
end

---@param callback fun(tree: Yat.Tree)
function Sidebar:for_each_tree(callback)
  for _, section in ipairs(self.sections) do
    callback(section.tree)
  end
end

---@class Yat.Sidebar.OpenArgs
---@field focus? boolean
---@field focus_edit_window? boolean
---@field position? Yat.Ui.Position
---@field size? integer

---@param tree Yat.Tree
---@param node? Yat.Node
---@param opts Yat.Sidebar.OpenArgs
---  - {opts.focus?} `boolean`
---  - {opts.focus_edit_window?} `boolean`
---  - {opts.position?} `Yat.Ui.Position`
---  - {opts.size?} `integer`
function Sidebar:open(tree, node, opts)
  if self.canvas:is_open() then
    return
  end

  opts = opts or {}
  self.canvas:open({ position = opts.position, size = opts.size })
  self:apply_mappings()
  self:render()
  self.canvas:restore_previous_position()

  if node then
    self:focus_node(tree, node)
  end

  if opts.focus then
    self.canvas:focus()
  elseif opts.focus_edit_window then
    self.canvas:focus_edit_window()
  end
end

---@param sidebar Yat.Sidebar
---@param mapping table<Yat.Trees.Type, Yat.Action>
---@return function handler
local function create_keymap_function(sidebar, mapping)
  return function()
    local tree, node = sidebar:get_current_tree_and_node()
    if tree then
      local action = mapping[tree.TYPE]
      if action then
        if node or action.node_independent then
          if node then
            tree.current_node = node
          end
          void(action.fn)(tree, node, sidebar)
        end
      end
    end
  end
end

---@private
function Sidebar:apply_mappings()
  local opts = { buffer = self.canvas:bufnr(), silent = true, nowait = true }
  for key, mapping in pairs(Trees.mappings()) do
    local rhs = create_keymap_function(self, mapping)

    ---@type table<string, boolean>, string[]
    local modes, descriptions = {}, {}
    for _, action in pairs(mapping) do
      for _, mode in ipairs(action.modes) do
        modes[mode] = true
      end
      descriptions[#descriptions + 1] = action.desc
    end
    opts.desc = table.concat(utils.tbl_unique(descriptions), "/")
    for mode in pairs(modes) do
      if not pcall(vim.keymap.set, mode, key, rhs, opts) then
        utils.warn(string.format("Cannot construct mapping for key %q!", key))
      end
    end
  end
end

---@param tree? Yat.Tree
---@return boolean is_open
function Sidebar:is_open(tree)
  local is_open = self.canvas:is_open()
  if is_open and tree then
    return self:is_tree_rendered(tree)
  end
  return is_open
end

function Sidebar:close()
  local tree, node = self:get_current_tree_and_node()
  if tree and node then
    tree.current_node = node
  end
  self.canvas:close()
end

function Sidebar:focus()
  self.canvas:focus()
end

function Sidebar:restore_window()
  self.canvas:restore()
end

---@return integer? height, integer? width
function Sidebar:size()
  if self.canvas:is_open() then
    return self.canvas:size()
  end
end

---@return boolean
function Sidebar:is_current_window()
  return self.canvas:is_current_window_canvas()
end

---@param position Yat.Ui.Position
---@param size? integer
function Sidebar:move_window_to(position, size)
  self.canvas:move_window(position, size)
end

---@param size integer
function Sidebar:resize_window(size)
  self.canvas:resize(size)
end

---@param bufnr integer
function Sidebar:move_buffer_to_edit_window(bufnr)
  self.canvas:move_buffer_to_edit_window(bufnr)
end

---@param tree? Yat.Tree
---@param node? Yat.Node
---@param opts? { focus_node?: boolean, focus_window?: boolean }
---  - {opts.focus_node?} `boolean`
---  - {opts.focus_window?} `boolean`
function Sidebar:update(tree, node, opts)
  opts = opts or {}
  if self.canvas:is_open() then
    self:render()
    if opts.focus_window then
      self.canvas:focus()
    end
    -- only update the focused node if the current window is the view window,
    -- or explicitly requested
    if tree and node and (opts.focus_node or self.canvas:has_focus()) then
      self:focus_node(tree, node)
    end
  end
end

---@param tree Yat.Tree
---@param node Yat.Node
function Sidebar:focus_node(tree, node)
  local config = require("ya-tree.config").config

  -- if the node has been hidden after a toggle
  -- go upwards in the tree until we find one that's displayed
  while node and node:is_hidden(config) and node.parent do
    node = node.parent
  end
  if node then
    local row = self:get_row_of_node(tree, node)
    if row then
      log.debug("node %s is at row %s", node.path, row)
      self.canvas:focus_row(row)
    end
  end
end

---@param file string the file path to open
---@param cmd Yat.Action.Files.Open.Mode
function Sidebar:open_file(file, cmd)
  local winid = self.canvas:edit_winid()
  if not winid then
    -- only the tree window is open, e.g. netrw replacement
    -- create a new window for buffers
    self.canvas:create_edit_window()
    if cmd == "split" or cmd == "vsplit" then
      cmd = "edit"
    end
  else
    api.nvim_set_current_win(winid)
  end

  vim.cmd({ cmd = cmd, args = { vim.fn.fnameescape(file) } })
end

do
  local SUPPORTED_EVENTS = {
    autocmd_event.BUFFER_NEW,
    autocmd_event.BUFFER_HIDDEN,
    autocmd_event.BUFFER_DISPLAYED,
    autocmd_event.BUFFER_DELETED,
    autocmd_event.BUFFER_MODIFIED,
    autocmd_event.BUFFER_SAVED,
  }

  ---@private
  ---@param tree Yat.Tree
  function Sidebar:register_events_for_tree(tree)
    log.debug("registering events for tree %s", tostring(tree))
    for event in pairs(tree.supported_events.autocmd) do
      if vim.tbl_contains(SUPPORTED_EVENTS, event) then
        self:register_autocmd_event(event, function(bufnr, file, match)
          self:on_autocmd_event(event, bufnr, file, match)
        end)
      else
        log.error("unhandled event of type %q", events.get_event_name(event))
      end
    end
    for event in pairs(tree.supported_events.git) do
      if event == git_event.DOT_GIT_DIR_CHANGED then
        self:register_git_event(event, function(repo, fs_changes)
          self:on_git_event(repo, fs_changes)
        end)
      else
        log.error("unhandled event of type %q", events.get_event_name(event))
      end
    end
    for event in pairs(tree.supported_events.yatree) do
      if event == yatree_event.DIAGNOSTICS_CHANGED then
        ---@param severity_changed boolean
        self:register_yatree_event(event, function(severity_changed)
          self:on_diagnostics_event(severity_changed)
        end)
      else
        log.error("unhandled event of type %q", events.get_event_name(event))
      end
    end
    local config = require("ya-tree.config").config
    if tree.TYPE == "filesystem" and config.dir_watcher.enable then
      ---@param dir string
      ---@param filenames string[]
      self:register_yatree_event(yatree_event.FS_CHANGED, function(dir, filenames)
        self:on_fs_changed_event(dir, filenames)
      end)
    end
  end
end

---@param sidebar Yat.Sidebar
---@param focus_node? boolean
local function update_canvas(sidebar, focus_node)
  vim.schedule(function()
    local tree, node = sidebar:get_current_tree_and_node()
    if tree then
      sidebar:update(tree, node, { focus_node = focus_node })
    end
  end)
end

---@async
---@private
---@param event Yat.Events.AutocmdEvent
---@param bufnr integer
---@param file string
---@param match string
function Sidebar:on_autocmd_event(event, bufnr, file, match)
  local tabpage = api.nvim_get_current_tabpage()
  local update = false
  for _, section in pairs(self.sections) do
    local tree = section.tree
    local callback = tree.supported_events.autocmd[event]
    if callback then
      update = callback(tree, bufnr, file, match) or update
    end
  end
  if update and tabpage == self._tabpage and self.canvas:is_open() then
    update_canvas(self, true)
  end
end

---@async
---@private
---@param repo Yat.Git.Repo
---@param fs_changes boolean
function Sidebar:on_git_event(repo, fs_changes)
  scheduler()
  local tabpage = api.nvim_get_current_tabpage()
  local update = false
  for _, section in pairs(self.sections) do
    local tree = section.tree
    local callback = tree.supported_events.git[git_event.DOT_GIT_DIR_CHANGED]
    if callback then
      update = callback(tree, repo, fs_changes) or update
    end
  end
  if update and tabpage == self._tabpage and self.canvas:is_open() then
    update_canvas(self, true)
  end
end

---@async
---@private
---@param severity_changed boolean
function Sidebar:on_diagnostics_event(severity_changed)
  local tabpage = api.nvim_get_current_tabpage()
  local update = false
  for _, section in pairs(self.sections) do
    local tree = section.tree
    local callback = tree.supported_events.yatree[yatree_event.DIAGNOSTICS_CHANGED]
    if callback then
      update = callback(tree, severity_changed) or update
    end
  end
  if update and tabpage == self._tabpage and self.canvas:is_open() then
    update_canvas(self)
  end
end

---@async
---@private
---@param dir string
---@param filenames string[]
function Sidebar:on_fs_changed_event(dir, filenames)
  local tree = self:get_tree("filesystem") --[[@as Yat.Trees.Filesystem?]]
  log.debug("fs_event for dir %q, with files %s, focus=%q", dir, filenames, tree and tree.focus_path_on_fs_event)
  local ui_is_open = self.canvas:is_open()

  local repo = git.get_repo_for_path(dir)
  if repo then
    repo:status():refresh({ ignored = true })
  end
  local git_tree = self:get_tree("git") --[[@as Yat.Trees.Git?]]
  if git_tree and (git_tree.root:is_ancestor_of(dir) or git_tree.root.path == dir) then
    if not git_tree.refreshing then
      git_tree.refreshing = true
      git_tree.root:refresh({ refresh_git = false })
      git_tree.refreshing = false
    else
      log.info("git tree is refreshing, skipping")
    end
  end

  if not tree then
    if git_tree and ui_is_open and self:is_tree_rendered(git_tree) then
      update_canvas(self, true)
    end
    return
  end
  -- if the watched directory was deleted, the parent directory will handle any updates
  if not fs.exists(dir) or not (tree.root:is_ancestor_of(dir) or tree.root.path == dir) then
    return
  end

  local node = tree.root:get_child_if_loaded(dir)
  if node then
    node:refresh()
    if ui_is_open and self:is_tree_rendered(tree) then
      local new_node = nil
      if tree.focus_path_on_fs_event then
        if tree.focus_path_on_fs_event == "expand" then
          node:expand()
        else
          local parent = tree.root:expand({ to = Path:new(tree.focus_path_on_fs_event):parent().filename })
          new_node = parent and parent:get_child_if_loaded(tree.focus_path_on_fs_event)
        end
        if not new_node then
          local os_sep = Path.path.sep
          for _, filename in ipairs(filenames) do
            local path = dir .. os_sep .. filename
            local child = node:get_child_if_loaded(path)
            if child then
              log.debug("setting current node to %q", path)
              new_node = child
              break
            end
          end
        end
      end
      if self:is_node_rendered(tree, node) then
        if new_node then
          vim.schedule(function()
            self:update(tree, new_node, { focus_node = true })
          end)
        else
          update_canvas(self, true)
        end
      end
    end
    if tree.focus_path_on_fs_event then
      log.debug("resetting focus_path_on_fs_event=%q dir=%q, filenames=%s", tree.focus_path_on_fs_event, dir, filenames)
      tree.focus_path_on_fs_event = nil
    end
  end
end

---@private
---@param event Yat.Events.AutocmdEvent
---@param callback fun(bufnr: integer, file: string, match: string)
function Sidebar:register_autocmd_event(event, callback)
  local count = self.registered_events.autocmd[event] or 0
  count = count + 1
  self.registered_events.autocmd[event] = count
  if count == 1 then
    events.on_autocmd_event(event, self:create_event_id(event), true, callback)
  end
end

---@private
---@param event Yat.Events.AutocmdEvent
function Sidebar:remove_autocmd_event(event)
  local count = self.registered_events.autocmd[event] or 0
  count = count - 1
  self.registered_events.autocmd[event] = count
  if count < 1 then
    events.remove_autocmd_event(event, self:create_event_id(event))
  end
end

---@private
---@param event Yat.Events.GitEvent
---@param callback fun(repo: Yat.Git.Repo, fs_changes: boolean)
function Sidebar:register_git_event(event, callback)
  local count = self.registered_events.git[event] or 0
  count = count + 1
  self.registered_events.git[event] = count
  if count == 1 then
    events.on_git_event(event, self:create_event_id(event), callback)
  end
end

---@private
---@param event Yat.Events.GitEvent
function Sidebar:remove_git_event(event)
  local count = self.registered_events.git[event] or 0
  count = count - 1
  self.registered_events.git[event] = count
  if count < 1 then
    events.remove_git_event(event, self:create_event_id(event))
  end
end

---@private
---@param event Yat.Events.YaTreeEvent
---@param callback fun(...)
function Sidebar:register_yatree_event(event, callback)
  local count = self.registered_events.yatree[event] or 0
  count = count + 1
  self.registered_events.yatree[event] = count
  if count == 1 then
    events.on_yatree_event(event, self:create_event_id(event), true, callback)
  end
end

---@private
---@param event Yat.Events.YaTreeEvent
function Sidebar:remove_yatree_event(event)
  local count = self.registered_events.yatree[event] or 0
  count = count - 1
  self.registered_events.yatree[event] = count
  if count < 1 then
    events.remove_yatree_event(event, self:create_event_id(event))
  end
end

---@private
---@param event integer
---@return string id
function Sidebar:create_event_id(event)
  return string.format("YA_TREE_SIDEBAR_%s_%s", self._tabpage, events.get_event_name(event))
end

---@private
function Sidebar:render()
  local config = require("ya-tree.config").config
  local hl = require("ya-tree.ui.highlights")
  local width = self.canvas:inner_width()

  local sections = self.single_mode and { self.sections[1] } or self.sections
  if self.single_mode and #self.sections > 1 then
    for i = 2, #self.sections do
      self.sections[i].from = 0
      self.sections[i].to = 0
      self.sections[i].path_lookup = {}
    end
  end

  local layout = config.sidebar.section_layout
  local header_enabled = not (self.single_mode or #self.sections == 1) and layout.header.enable
  local pad_header = layout.header.empty_line_before_tree
  local offset = not header_enabled and -1 or pad_header and 1 or 0
  local footer_enabled = layout.footer.enable
  local pad_footer_top = layout.footer.empty_line_after_tree
  local pad_footer_bottom = layout.footer.empty_line_after_divider
  local divider = footer_enabled and string.rep(layout.footer.divider_char, width) or nil

  ---@type string[], Yat.Ui.HighlightGroup[][]
  local lines, highlights, from = {}, {}, 1
  for i, section in pairs(sections) do
    section.from = from
    local _lines, _highlights
    _lines, _highlights, section.path_lookup = section.tree:render(config, from + offset)

    if header_enabled then
      local header, header_hl = section.tree:render_header()
      table.insert(_lines, 1, header)
      table.insert(_highlights, 1, header_hl)
      if pad_header then
        table.insert(_lines, 2, "")
        table.insert(_highlights, 2, {})
      end
    end

    if footer_enabled and i < #sections then
      if pad_footer_top then
        _lines[#_lines + 1] = ""
        _highlights[#_highlights + 1] = {}
      end
      _lines[#_lines + 1] = divider
      _highlights[#_highlights + 1] = { { name = hl.SECTION_DIVIDER, from = 0, to = -1 } }
      if pad_footer_bottom then
        _lines[#_lines + 1] = ""
        _highlights[#_highlights + 1] = {}
      end
    end

    vim.list_extend(lines, _lines, 1, #_lines)
    vim.list_extend(highlights, _highlights, 1, #_highlights)
    section.to = from + #_lines - 1
    from = section.to + 1
  end

  self.canvas:draw(lines, highlights)
end

---@private
---@param tree_type Yat.Trees.Type
---@return Yat.Sidebar.Section? section
function Sidebar:get_section(tree_type)
  for _, section in pairs(self.sections) do
    if section.tree.TYPE == tree_type then
      return section
    end
  end
end

---@private
---@param row integer
---@return Yat.Sidebar.Section|nil
function Sidebar:get_section_for_row(row)
  for _, section in pairs(self.sections) do
    if row >= section.from and row <= section.to then
      return section
    end
  end
end

---@param tree Yat.Tree
---@return boolean is_rendered
function Sidebar:is_tree_rendered(tree)
  if self.single_mode then
    return self.sections[1].tree.TYPE == tree.TYPE
  end
  return self:get_section(tree.TYPE) ~= nil
end

---@param tree Yat.Tree
---@param node Yat.Node
---@return boolean is_rendered
function Sidebar:is_node_rendered(tree, node)
  local section = self:get_section(tree.TYPE)
  return section and section.path_lookup[node.path] ~= nil or false
end

---@param tree Yat.Tree
---@param path? string
---@return Yat.Node|nil node
local function get_node(tree, path)
  return path and tree.root and tree.root:get_child_if_loaded(path) or nil
end

---@param row integer
---@return Yat.Tree|nil current_tree
---@return Yat.Node|nil current_node
function Sidebar:get_tree_and_node(row)
  local section = self:get_section_for_row(row)
  if section then
    return section.tree, get_node(section.tree, section.path_lookup[row])
  end
end

---@return Yat.Tree|nil current_tree
---@return Yat.Node|nil current_node
function Sidebar:get_current_tree_and_node()
  local row = api.nvim_win_get_cursor(self.canvas:winid())[1]
  local section = self:get_section_for_row(row)
  if section then
    return section.tree, get_node(section.tree, section.path_lookup[row])
  end
end

---@param tree Yat.Tree
---@return Yat.Tree|nil next_tree `nil` if the current tree is the first one.
function Sidebar:get_prev_tree(tree)
  for i, section in pairs(self.sections) do
    if section.tree.TYPE == tree.TYPE then
      local index = i - 1
      return index <= #self.sections and self.sections[index].tree or nil
    end
  end
end

---@param tree Yat.Tree
---@return Yat.Tree|nil next_tree `nil` if the current tree is the last one.
function Sidebar:get_next_tree(tree)
  for i, section in pairs(self.sections) do
    if section.tree.TYPE == tree.TYPE then
      local index = i + 1
      return index <= #self.sections and self.sections[index].tree or nil
    end
  end
end

---@param row integer
---@return Yat.Node|nil
function Sidebar:get_node(row)
  local section = self:get_section_for_row(row)
  return section and get_node(section.tree, section.path_lookup[row])
end

---@param from integer
---@param to integer
---@return Yat.Node[] nodes
function Sidebar:get_nodes(from, to)
  ---@type Yat.Node[]
  local nodes = {}
  local section = self:get_section_for_row(from)
  if section and section.tree.root then
    for row = from, math.min(to, section.to) do
      local path = section.path_lookup[row]
      if path then
        local node = section.tree.root:get_child_if_loaded(path)
        if node then
          nodes[#nodes + 1] = node
        end
      end
    end
  end
  return nodes
end

---@return Yat.Node[]
function Sidebar:get_selected_nodes()
  local from, to = self.canvas:get_selected_rows()
  return self:get_nodes(from, to)
end

---@param tree Yat.Tree
---@param node Yat.Node
---@return integer|nil row
function Sidebar:get_row_of_node(tree, node)
  local section = self:get_section(tree.TYPE)
  return section and section.path_lookup[node.path]
end

---@async
---@param new_cwd string
function Sidebar:change_cwd(new_cwd)
  for _, section in pairs(self.sections) do
    section.tree:on_cwd_changed(new_cwd)
  end
end

local M = {
  ---@private
  ---@type table<integer, Yat.Sidebar>
  _sidebars = {},
}

---@param tabpage integer
---@return Yat.Sidebar?
function M.get_sidebar(tabpage)
  return M._sidebars[tabpage]
end

---@async
---@param tabpage integer
---@return Yat.Sidebar sidebar
function M.get_or_create_sidebar(tabpage)
  local sidebar = M._sidebars[tabpage]
  if not sidebar then
    sidebar = Sidebar:new(tabpage)
    M._sidebars[tabpage] = sidebar
  end
  return sidebar
end

---@param callback fun(tree: Yat.Tree)
function M.for_each_sidebar_and_tree(callback)
  for _, sidebar in ipairs(M._sidebars) do
    sidebar:for_each_tree(callback)
  end
end

---@async
---@param scope "window"|"tabpage"|"global"|"auto"
---@param new_cwd string
local function on_cwd_changed(scope, new_cwd)
  log.debug("scope=%s, cwd=%s", scope, new_cwd)

  local current_tabpage = api.nvim_get_current_tabpage()
  -- Do the current tabpage first
  if scope == "tabpage" or scope == "global" then
    local sidebar = M._sidebars[current_tabpage]
    if sidebar then
      local tree, node
      if sidebar:is_open() then
        tree, node = sidebar:get_current_tree_and_node()
      end
      sidebar:change_cwd(new_cwd)
      if tree then
        sidebar:update(tree, node)
      end
    end
  end
  if scope == "global" then
    for tabpage, sidebar in ipairs(M._sidebars) do
      if tabpage ~= current_tabpage then
        sidebar:change_cwd(new_cwd)
      end
    end
  end
end

function M.delete_sidebars_for_nonexisting_tabpages()
  ---@type table<string, boolean>
  local found_toplevels = {}
  local tabpages = api.nvim_list_tabpages() --[=[@as integer[]]=]
  for tabpage, sidebar in pairs(M._sidebars) do
    if not vim.tbl_contains(tabpages, tabpage) then
      M._sidebars[tabpage] = nil
      sidebar:delete()
    else
      sidebar:for_each_tree(function(tree)
        tree.root:walk(function(node)
          if node.repo then
            if not found_toplevels[node.repo.toplevel] then
              found_toplevels[node.repo.toplevel] = true
            end
            if not node.repo:is_yadm() then
              return true
            end
          end
        end)
      end)
    end
  end

  for toplevel, repo in pairs(git.repos) do
    if not found_toplevels[toplevel] then
      git.remove_repo(repo)
    end
  end
end

---@param bufnr integer
local function on_win_leave(bufnr)
  if ui.is_window_floating() then
    return
  end
  local ok, buftype = pcall(api.nvim_buf_get_option, bufnr, "buftype")
  if not ok or buftype ~= "" then
    return
  end

  local sidebar = M.get_sidebar(api.nvim_get_current_tabpage())
  if sidebar and not sidebar.canvas:is_current_window_canvas() then
    sidebar.canvas:set_edit_winid(api.nvim_get_current_win())
  end
end

---@param config Yat.Config
function M.setup(config)
  local group = api.nvim_create_augroup("YaTreeSidebar", { clear = true })
  if config.cwd.follow then
    api.nvim_create_autocmd("DirChanged", {
      group = group,
      pattern = "*",
      callback = function(input)
        -- currently not available in the table passed to the callback
        if not vim.v.event.changed_window then
          -- if the autocmd was fired because of a switch to a tab or window with a different
          -- cwd than the previous tab/window, it can safely be ignored.
          void(on_cwd_changed)(input.match, input.file)
        end
      end,
      desc = "Handle changed cwd",
    })
  end
  api.nvim_create_autocmd("TabClosed", {
    group = group,
    callback = M.delete_sidebars_for_nonexisting_tabpages,
    desc = "Clean up after closing tabpage",
  })
  api.nvim_create_autocmd("WinLeave", {
    group = group,
    callback = on_win_leave,
    desc = "Save the last used window id",
  })
end

return M
