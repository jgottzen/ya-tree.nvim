local scheduler = require("plenary.async.util").scheduler
local void = require("plenary.async").void
local Path = require("plenary.path")

local events = require("ya-tree.events")
local autocmd_event = require("ya-tree.events.event").autocmd
local git_event = require("ya-tree.events.event").git
local yatree_event = require("ya-tree.events.event").ya_tree
local fs = require("ya-tree.fs")
local git = require("ya-tree.git")
local Trees = require("ya-tree.trees")
local BuffersTree = require("ya-tree.trees.buffers")
local FilesystemTree = require("ya-tree.trees.filesystem")
local GitTree = require("ya-tree.trees.git")
local SearchTree = require("ya-tree.trees.search")
local ui = require("ya-tree.ui")
local log = require("ya-tree.log")("sidebar")

local api = vim.api
local uv = vim.loop

---@type fun(tree?: Yat.Tree, node?: Yat.Node, opts?: { focus_node?: boolean, focus_window?: boolean })
local update_ui = vim.schedule_wrap(ui.update)

---@class Yat.Sidebar.Section
---@field tree Yat.Tree
---@field directory_min_diagnostic_severity integer
---@field file_min_diagnostic_severity integer
---@field from integer
---@field to integer
---@field path_lookup { [integer]: string, [integer]: string }

---@param section Yat.Sidebar.Section
---@return string
local function section_tostring(section)
  return string.format("(%s, [%s,%s])", section.tree.TYPE, section.from, section.to)
end

---@class Yat.Sidebar
---@field tabpage integer
---@field single_mode boolean
---@field tree_order table<Yat.Trees.Type, integer>
---@field always_shown_trees Yat.Trees.Type[]
---@field private _sections Yat.Sidebar.Section[]
---@field private _registered_events { autcmd: table<Yat.Events.AutocmdEvent, integer>, git: table<Yat.Events.GitEvent, integer>, yatree: table<Yat.Events.YaTreeEvent, integer> }
local Sidebar = {}
Sidebar.__index = Sidebar

---@param other Yat.Sidebar
---@return boolean
function Sidebar.__eq(self, other)
  return self.tabpage == other.tabpage
end

function Sidebar.__tostring(self)
  return string.format("Sidebar(%s, sections=[%s])", self.tabpage, table.concat(vim.tbl_map(section_tostring, self._sections), ", "))
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
    directory_min_diagnostic_severity = vim.diagnostic.severity.HINT,
    file_min_diagnostic_severity = vim.diagnostic.severity.HINT,
  }
  return section
end

---@async
---@param tabpage integer
---@param sidebar_config? Yat.Config.Sidebar
---@return Yat.Sidebar
function Sidebar:new(tabpage, sidebar_config)
  sidebar_config = sidebar_config or require("ya-tree.config").config.sidebar
  local this = setmetatable({}, self)
  this.tabpage = tabpage
  this.single_mode = sidebar_config.single_mode
  this.tree_order = {}
  for i, tree_type in ipairs(sidebar_config.tree_order) do
    this.tree_order[tree_type] = i
  end
  this.always_shown_trees = sidebar_config.trees_always_shown
  this._registered_events = { autcmd = {}, git = {}, yatree = {} }
  this._sections = {}
  local tree_types = this.single_mode and { this.always_shown_trees[1] } or this.always_shown_trees
  for _, tree_type in ipairs(tree_types) do
    local tree = Trees.create_tree(this.tabpage, tree_type, uv.cwd())
    if tree then
      this:_register_events_for_tree(tree)
      this._sections[#this._sections + 1] = create_section(tree)
    end
  end
  table.sort(this._sections, function(a, b)
    local a_order = this.tree_order[a.tree.TYPE] or 1000
    local b_order = this.tree_order[b.tree.TYPE] or 1000
    return a_order < b_order
  end)

  log.info("created new sidebar %s", tostring(this))
  return this
end

---@private
---@param tree Yat.Tree
function Sidebar:_register_events_for_tree(tree)
  log.debug("registering events for tree %s", tostring(tree))
  for _, event in ipairs(tree.supported_events.autcmd) do
    self:register_autocmd_event(event, true, function(bufnr, file, match)
      if event == autocmd_event.BUFFER_NEW then
        self:on_buffer_new(bufnr, file, match)
      elseif event == autocmd_event.BUFFER_HIDDEN then
        self:on_buffer_hidden(bufnr, file, match)
      elseif event == autocmd_event.BUFFER_DISPLAYED then
        self:on_buffer_displayed(bufnr, file, match)
      elseif event == autocmd_event.BUFFER_DELETED then
        self:on_buffer_deleted(bufnr, file, match)
      elseif event == autocmd_event.BUFFER_MODIFIED then
        self:on_buffer_modified(bufnr, file, match)
      elseif event == autocmd_event.BUFFER_SAVED then
        self:on_buffer_saved(bufnr, file, match)
      else
        log.error("unhandled event of type %q", events.get_event_name(event))
      end
    end)
  end
  for _, event in ipairs(tree.supported_events.git) do
    self:register_git_event(event, function(repo, fs_changes)
      if event == git_event.DOT_GIT_DIR_CHANGED then
        self:on_git_event(repo, fs_changes)
      else
        log.error("unhandled event of type %q", events.get_event_name(event))
      end
    end)
  end
  for _, event in ipairs(tree.supported_events.yatree) do
    ---@param severity_changed boolean
    self:register_yatree_event(event, true, function(severity_changed)
      if event == yatree_event.DIAGNOSTICS_CHANGED then
        self:on_diagnostics_event(severity_changed)
      else
        log.error("unhandled event of type %q", events.get_event_name(event))
      end
    end)
  end
  local config = require("ya-tree.config").config
  if tree.TYPE == "filesystem" and config.dir_watcher.enable then
    ---@param dir string
    ---@param filenames string[]
    self:register_yatree_event(yatree_event.FS_CHANGED, true, function(dir, filenames)
      self:on_fs_changed_event(dir, filenames)
    end)
  end
end

---@async
---@private
---@param tree_type Yat.Trees.Type
---@param tree_creator fun(): Yat.Tree
---@param new_root_node? any
---@return Yat.Tree
function Sidebar:_get_or_create_tree(tree_type, tree_creator, new_root_node)
  local tree = self:get_tree(tree_type)
  if tree then
    if new_root_node then
      tree:change_root_node(new_root_node)
    end
    if self.single_mode and self._sections[1].tree.TYPE ~= tree.TYPE then
      self:_delete_section(1)
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
  return self:_get_or_create_tree("filesystem", function()
    return FilesystemTree:new(self.tabpage, path)
  end, path) --[[@as Yat.Trees.Filesystem]]
end

---@async
---@param repo Yat.Git.Repo
---@return Yat.Trees.Git
function Sidebar:git_tree(repo)
  return self:_get_or_create_tree("git", function()
    return GitTree:new(self.tabpage, repo)
  end, repo) --[[@as Yat.Trees.Git]]
end

---@async
---@return Yat.Trees.Buffers
function Sidebar:buffers_tree()
  return self:_get_or_create_tree("buffers", function()
    return BuffersTree:new(self.tabpage, uv.cwd())
  end) --[[@as Yat.Trees.Buffers]]
end

---@async
---@param path string
---@return Yat.Trees.Search
function Sidebar:search_tree(path)
  return self:_get_or_create_tree("search", function()
    return SearchTree:new(self.tabpage, path)
  end, path) --[[@as Yat.Trees.Search]]
end

---@param tree_type Yat.Trees.Type
---@return Yat.Tree|nil tree
function Sidebar:get_tree(tree_type)
  local section = self:_get_section(tree_type)
  return section and section.tree
end

---@private
---@param index integer
function Sidebar:_delete_section(index)
  local section = self._sections[index]
  log.info("deleteing section %s", section_tostring(section))
  local tree = section.tree
  for _, event in ipairs(tree.supported_events.autcmd) do
    self:remove_autocmd_event(event)
  end
  for _, event in ipairs(tree.supported_events.git) do
    self:remove_git_event(event)
  end
  for _, event in ipairs(tree.supported_events.yatree) do
    self:remove_yatree_event(event)
  end
  local config = require("ya-tree.config").config
  if tree.TYPE == "filesystem" and config.dir_watcher.enable then
    self:remove_yatree_event(yatree_event.FS_CHANGED)
  end
  tree:delete()
  table.remove(self._sections, index)
end

---@async
---@param tree Yat.Tree
function Sidebar:add_tree(tree)
  if self.single_mode then
    if self._sections[1].tree == tree then
      return
    end
    -- don't delete the filesystem tree section
    if self._sections[1].tree.TYPE ~= "filesystem" then
      self:_delete_section(1)
    end
    table.insert(self._sections, 1, create_section(tree))
    self:_register_events_for_tree(tree)
  else
    for _, section in pairs(self._sections) do
      if section.tree == tree then
        section.tree = tree
        return
      end
    end
    self._sections[#self._sections + 1] = create_section(tree)
    self:_register_events_for_tree(tree)
    table.sort(self._sections, function(a, b)
      local a_order = self.tree_order[a.tree.TYPE] or 1000
      local b_order = self.tree_order[b.tree.TYPE] or 1000
      return a_order < b_order
    end)
  end
end

---@async
---@param tree Yat.Tree
---@param force? boolean
---@return Yat.Tree? tree
function Sidebar:close_tree(tree, force)
  if self.single_mode then
    if tree.TYPE ~= "filesystem" then
      self:_delete_section(1)
      -- the filesystem tree is never deleted, reuse it if it's present
      if not (self._sections[1] and self._sections[1].tree.TYPE == "filesystem") then
        self._sections = create_section(FilesystemTree:new(self.tabpage, uv.cwd()))
      end
      return self._sections[1].tree
    end
  else
    if force or not vim.tbl_contains(self.always_shown_trees, tree.TYPE) then
      for i = #self._sections, 1, -1 do
        if self._sections[i].tree == tree then
          self:_delete_section(i)
          if i >= #self._sections then
            return self._sections[#self._sections].tree
          else
            return self._sections[i].tree
          end
        end
      end
    end
  end
end

---@async
---@param bufnr integer
---@param file string
function Sidebar:on_buffer_new(bufnr, file, match)
  local update = false
  for _, section in pairs(self._sections) do
    local tree = section.tree
    ---@diagnostic disable-next-line:undefined-field
    if tree.on_buffer_new and vim.tbl_contains(tree.supported_events.autcmd, autocmd_event.BUFFER_NEW) then
      ---@diagnostic disable-next-line:undefined-field
      update = tree:on_buffer_new(bufnr, file, match) or update
    end
  end
  if update then
    update_ui()
  end
end

---@async
---@param bufnr integer
---@param file string
function Sidebar:on_buffer_hidden(bufnr, file, match)
  local update = false
  for _, section in pairs(self._sections) do
    local tree = section.tree
    ---@diagnostic disable-next-line:undefined-field
    if tree.on_buffer_hidden and vim.tbl_contains(tree.supported_events.autcmd, autocmd_event.BUFFER_HIDDEN) then
      ---@diagnostic disable-next-line:undefined-field
      update = tree:on_buffer_hidden(bufnr, file, match) or update
    end
  end
  if update then
    update_ui()
  end
end

---@async
---@param bufnr integer
---@param file string
function Sidebar:on_buffer_displayed(bufnr, file, match)
  local update = false
  for _, section in pairs(self._sections) do
    local tree = section.tree
    ---@diagnostic disable-next-line:undefined-field
    if tree.on_buffer_displayed and vim.tbl_contains(tree.supported_events.autcmd, autocmd_event.BUFFER_DISPLAYED) then
      ---@diagnostic disable-next-line:undefined-field
      update = tree:on_buffer_displayed(bufnr, file, match) or update
    end
  end
  if update then
    update_ui()
  end
end

---@async
---@param bufnr integer
---@param file string
function Sidebar:on_buffer_deleted(bufnr, file, match)
  local update = false
  for _, section in pairs(self._sections) do
    local tree = section.tree
    ---@diagnostic disable-next-line:undefined-field
    if tree.on_buffer_deleted and vim.tbl_contains(tree.supported_events.autcmd, autocmd_event.BUFFER_DELETED) then
      ---@diagnostic disable-next-line:undefined-field
      update = tree:on_buffer_deleted(bufnr, file, match) or update
    end
  end
  if update then
    update_ui()
  end
end

---@async
---@param bufnr integer
---@param file string
function Sidebar:on_buffer_modified(bufnr, file, match)
  local update = false
  for _, section in pairs(self._sections) do
    local tree = section.tree
    if tree.on_buffer_modified and vim.tbl_contains(tree.supported_events.autcmd, autocmd_event.BUFFER_MODIFIED) then
      update = tree:on_buffer_modified(bufnr, file, match) or update
    end
  end
  if update then
    update_ui()
  end
end

---@async
---@param bufnr integer
---@param file string
---@diagnostic disable-next-line:unused-local
function Sidebar:on_buffer_saved(bufnr, file, match)
  local repo = git.get_repo_for_path(file)
  if repo then
    repo:refresh_status_for_path(file)
  end
  local update = false
  for _, section in pairs(self._sections) do
    local tree = section.tree
    if tree.on_buffer_saved and vim.tbl_contains(tree.supported_events.autcmd, autocmd_event.BUFFER_SAVED) then
      update = tree:on_buffer_saved(bufnr, file, match) or update
    end
  end
  if update then
    update_ui()
  end
end

---@async
---@param repo Yat.Git.Repo
---@param fs_changes boolean
function Sidebar:on_git_event(repo, fs_changes)
  local update = false
  for _, section in pairs(self._sections) do
    local tree = section.tree
    if tree.on_git_event and vim.tbl_contains(tree.supported_events.git, git_event.DOT_GIT_DIR_CHANGED) then
      update = tree:on_git_event(repo, fs_changes) or update
    end
  end
  if update then
    update_ui()
  end
end

---@async
---@param severity_changed boolean
function Sidebar:on_diagnostics_event(severity_changed)
  local update = false
  for _, section in pairs(self._sections) do
    local tree = section.tree
    if tree.on_diagnostics_event and vim.tbl_contains(tree.supported_events.yatree, yatree_event.DIAGNOSTICS_CHANGED) then
      update = tree:on_diagnostics_event(severity_changed) or update
    end
  end
  if update then
    update_ui()
  end
end

---@async
---@param dir string
---@param filenames string[]
function Sidebar:on_fs_changed_event(dir, filenames)
  local tabpage = api.nvim_get_current_tabpage()
  local tree = self:get_tree("filesystem") --[[@as Yat.Trees.Filesystem?]]
  log.debug("fs_event for dir %q, with files %s, focus=%q", dir, filenames, tree and tree.focus_path_on_fs_event)
  local ui_is_open = ui.is_open(tabpage)

  local repo = git.get_repo_for_path(dir)
  if repo then
    repo:refresh_status({ ignored = true })
  end
  local git_tree = self:get_tree("git") --[[@as Yat.Trees.Git?]]
  if git_tree and (git_tree.root:is_ancestor_of(dir) or git_tree.root.path == dir) then
    git_tree.root:refresh({ refresh_git = false })
  end

  if not tree then
    if git_tree and ui_is_open and self:is_tree_rendered(git_tree) then
      ui.update()
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
        scheduler()
        if new_node then
          ui.update(tree, new_node, { focus_node = true })
        else
          local row = api.nvim_win_get_cursor(0)[1]
          local current_tree, current_node = self:get_current_tree_and_node(row)
          ui.update(current_tree, current_node)
        end
      end
    end
    if tree.focus_path_on_fs_event then
      log.debug("resetting focus_path_on_fs_event=%q dir=%q, filenames=%s", tree.focus_path_on_fs_event, dir, filenames)
      tree.focus_path_on_fs_event = nil
    end
  end
end

---@param event Yat.Events.AutocmdEvent
---@param async boolean
---@param callback fun(bufnr: integer, file: string, match: string)
function Sidebar:register_autocmd_event(event, async, callback)
  local count = self._registered_events.autcmd[event] or 0
  count = count + 1
  self._registered_events.autcmd[event] = count
  if count == 1 then
    events.on_autocmd_event(event, self:_create_event_id(event), async, callback)
  end
end

---@param event Yat.Events.AutocmdEvent
function Sidebar:remove_autocmd_event(event)
  local count = self._registered_events.autcmd[event] or 0
  count = count - 1
  self._registered_events.autcmd[event] = count
  if count < 1 then
    events.remove_autocmd_event(event, self:_create_event_id(event))
  end
end

---@param event Yat.Events.GitEvent
---@param callback fun(repo: Yat.Git.Repo, fs_changes: boolean)
function Sidebar:register_git_event(event, callback)
  local count = self._registered_events.git[event] or 0
  count = count + 1
  self._registered_events.git[event] = count
  if count == 1 then
    events.on_git_event(event, self:_create_event_id(event), callback)
  end
end

---@param event Yat.Events.GitEvent
function Sidebar:remove_git_event(event)
  local count = self._registered_events.git[event] or 0
  count = count - 1
  self._registered_events.git[event] = count
  if count < 1 then
    events.remove_git_event(event, self:_create_event_id(event))
  end
end

---@param event Yat.Events.YaTreeEvent
---@param async boolean
---@param callback fun(...)
function Sidebar:register_yatree_event(event, async, callback)
  local count = self._registered_events.yatree[event] or 0
  count = count + 1
  self._registered_events.yatree[event] = count
  if count == 1 then
    events.on_yatree_event(event, self:_create_event_id(event), async, callback)
  end
end

---@param event Yat.Events.YaTreeEvent
function Sidebar:remove_yatree_event(event)
  local count = self._registered_events.yatree[event] or 0
  count = count - 1
  self._registered_events.yatree[event] = count
  if count < 1 then
    events.remove_yatree_event(event, self:_create_event_id(event))
  end
end

---@private
---@param event integer
---@return string id
function Sidebar:_create_event_id(event)
  return string.format("YA_TREE_SIDEBAR_%s_%s", self.tabpage, events.get_event_name(event))
end

---@param config Yat.Config
---@param width integer
---@return string[] lines
---@return Yat.Ui.HighlightGroup[][] highlights
function Sidebar:render(config, width)
  local hl = require("ya-tree.ui.highlights")
  local sections = self.single_mode and { self._sections[1] } or self._sections
  if self.single_mode and #self._sections == 2 then
    self._sections[2].from = 0
    self._sections[2].to = 0
    self._sections[2].path_lookup = {}
  end

  local header_enabled = not (self.single_mode or #self._sections == 1) and config.sidebar.section_layout.header.enable
  local pad_header = config.sidebar.section_layout.header.empty_line_before_tree
  local offset = not header_enabled and -1 or pad_header and 1 or 0
  local footer_enabled = config.sidebar.section_layout.footer.enable
  local pad_footer_top = config.sidebar.section_layout.footer.empty_line_after_tree
  local pad_footer_bottom = config.sidebar.section_layout.footer.empty_line_after_separator
  local separator = string.rep(config.sidebar.section_layout.footer.separator_char, width)

  ---@type string[], Yat.Ui.HighlightGroup[][]
  local lines, highlights, from = {}, {}, 1
  for i, section in pairs(sections) do
    section.from = from
    local _lines, _highlights, path_lookup, extra = section.tree:render(config, from + offset)
    section.path_lookup = path_lookup
    section.directory_min_diagnostic_severity = extra.directory_min_diagnostic_severity
    section.file_min_diagnostic_severity = extra.file_min_diagnostic_severity

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
      _lines[#_lines + 1] = separator
      _highlights[#_highlights + 1] = { { name = hl.DIM_TEXT, from = 0, to = -1 } }
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

  return lines, highlights
end

---@private
---@param tree_type Yat.Trees.Type
---@return Yat.Sidebar.Section? section
function Sidebar:_get_section(tree_type)
  for _, section in pairs(self._sections) do
    if section.tree.TYPE == tree_type then
      return section
    end
  end
end

---@private
---@param row integer
---@return Yat.Sidebar.Section|nil
function Sidebar:_get_section_for_row(row)
  for _, section in pairs(self._sections) do
    if row >= section.from and row <= section.to then
      return section
    end
  end
end

---@param tree Yat.Tree
---@return boolean is_rendered
function Sidebar:is_tree_rendered(tree)
  if self.single_mode then
    return self._sections[1].tree.TYPE == tree.TYPE
  end
  return self:_get_section(tree.TYPE) ~= nil
end

---@param tree Yat.Tree
---@param node Yat.Node
---@return boolean is_rendered
function Sidebar:is_node_rendered(tree, node)
  local section = self:_get_section(tree.TYPE)
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
function Sidebar:get_current_tree_and_node(row)
  local section = self:_get_section_for_row(row)
  if section then
    return section.tree, get_node(section.tree, section.path_lookup[row])
  end
end

---@param tree Yat.Tree
---@return Yat.Tree|nil next_tree `nil` if the current tree is the first one.
function Sidebar:get_previous_tree(tree)
  for i, section in pairs(self._sections) do
    if section.tree.TYPE == tree.TYPE then
      local index = i - 1
      return index <= #self._sections and self._sections[index].tree or nil
    end
  end
end

---@param tree Yat.Tree
---@return Yat.Tree|nil next_tree `nil` if the current tree is the last one.
function Sidebar:get_next_tree(tree)
  for i, section in pairs(self._sections) do
    if section.tree.TYPE == tree.TYPE then
      local index = i + 1
      return index <= #self._sections and self._sections[index].tree or nil
    end
  end
end

---@param row integer
---@return Yat.Node|nil
function Sidebar:get_node(row)
  local section = self:_get_section_for_row(row)
  return section and get_node(section.tree, section.path_lookup[row])
end

---@param from integer
---@param to integer
---@return Yat.Node[] nodes
function Sidebar:get_nodes(from, to)
  ---@type Yat.Node[]
  local nodes = {}
  local section = self:_get_section_for_row(from)
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

---@param tree Yat.Tree
---@param node Yat.Node
---@return integer|nil row
function Sidebar:get_row_of_node(tree, node)
  local section = self:_get_section(tree.TYPE)
  return section and section.path_lookup[node.path]
end

---@param iterator fun(): integer, Yat.Node
---@param tree Yat.Tree
---@param config Yat.Config
---@return integer|nil node
function Sidebar:get_first_non_hidden_node_row(iterator, tree, config)
  local section = self:_get_section(tree.TYPE)
  if section then
    for _, node in iterator do
      if not node:is_hidden(config) then
        return section.path_lookup[node.path]
      end
    end
  end
end

---@private
---@param tree Yat.Tree
---@param start_node Yat.Node
---@param forward boolean
---@param predicate fun(node_at_row: Yat.Node, section: Yat.Sidebar.Section): boolean
---@return integer|nil row
function Sidebar:_get_first_row_that_match(tree, start_node, forward, predicate)
  local section = self:_get_section(tree.TYPE)
  if section then
    local current_row = section.path_lookup[start_node.path]
    if current_row then
      local step = forward and 1 or -1
      for row = current_row + step, forward and section.to or section.from, step do
        local path = section.path_lookup[row]
        if path then
          local node_at_row = get_node(tree, path)
          if node_at_row and predicate(node_at_row, section) then
            return row
          end
        end
      end
    end
  end
end

---@param tree Yat.Tree
---@param node Yat.Node
---@return integer|nil row
function Sidebar:get_prev_git_item_row(tree, node)
  return self:_get_first_row_that_match(tree, node, false, function(node_at_row)
    return node_at_row:git_status() ~= nil
  end)
end

---@param tree Yat.Tree
---@param node Yat.Node
---@return integer|nil row
function Sidebar:get_next_git_item_row(tree, node)
  return self:_get_first_row_that_match(tree, node, true, function(node_at_row)
    return node_at_row:git_status() ~= nil
  end)
end

---@param tree Yat.Tree
---@param node Yat.Node
---@return integer|nil row
function Sidebar:get_prev_diagnostic_item_row(tree, node)
  return self:_get_first_row_that_match(tree, node, false, function(node_at_row, section)
    local severity = node_at_row:diagnostic_severity()
    if severity then
      local target_severity = node_at_row:is_directory() and section.directory_min_diagnostic_severity
        or section.file_min_diagnostic_severity
      if severity <= target_severity then
        return true
      end
    end
  end)
end

---@param tree Yat.Tree
---@param node Yat.Node
---@return integer|nil row
function Sidebar:get_next_diagnostic_item_row(tree, node)
  return self:_get_first_row_that_match(tree, node, true, function(node_at_row, section)
    local severity = node_at_row:diagnostic_severity()
    if severity then
      local target_severity = node_at_row:is_directory() and section.directory_min_diagnostic_severity
        or section.file_min_diagnostic_severity
      if severity <= target_severity then
        return true
      end
    end
  end)
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
---@param sidebar_config? Yat.Config.Sidebar
---@return Yat.Sidebar sidebar
function M.get_or_create_sidebar(tabpage, sidebar_config)
  local sidebar = M._sidebars[tabpage]
  if not sidebar then
    sidebar = Sidebar:new(tabpage, sidebar_config)
    M._sidebars[tabpage] = sidebar
  end
  return sidebar
end

---@param callback fun(tree: Yat.Tree)
function M.for_each_tree(callback)
  for _, sidebar in ipairs(M._sidebars) do
    for _, section in pairs(sidebar._sections) do
      callback(section.tree)
    end
  end
end

---@async
---@param scope "window"|"tabpage"|"global"|"auto"
---@param new_cwd string
local function on_cwd_changed(scope, new_cwd)
  log.debug("scope=%s, cwd=%s", scope, new_cwd)

  ---@param sidebar? Yat.Sidebar
  local function cwd_for_sidebar(sidebar)
    if sidebar then
      for _, section in pairs(sidebar._sections) do
        section.tree:on_cwd_changed(new_cwd)
      end
    end
  end

  local current_tabpage = api.nvim_get_current_tabpage()
  -- Do the current tabpage first
  if scope == "tabpage" or scope == "global" then
    cwd_for_sidebar(M._sidebars[current_tabpage])
    update_ui()
  end
  if scope == "global" then
    for tabpage, sidebar in ipairs(M._sidebars) do
      if tabpage ~= current_tabpage then
        cwd_for_sidebar(sidebar)
      end
    end
  end
end

---@async
---@param new_cwd string
function M.change_root_for_current_tabpage(new_cwd)
  void(on_cwd_changed)("tabpage", new_cwd)
end

function M.delete_sidebars_for_nonexisting_tabpages()
  ---@type table<string, boolean>
  local found_toplevels = {}
  local tabpages = api.nvim_list_tabpages() --[=[@as integer[]]=]
  -- use pairs instead of ipairs to handle any keys without a value, i.e. when a tabpage has been deleted
  for tabpage, sidebar in pairs(M._sidebars) do
    if not vim.tbl_contains(tabpages, tabpage) then
      for i = #sidebar._sections, 1, -1 do
        sidebar:_delete_section(i)
      end
      for event, count in pairs(sidebar._registered_events.autcmd) do
        if count > 0 then
          log.error("autocmd event %s is still registered with count %s", events.get_event_name(event), count)
        end
      end
      for event, count in pairs(sidebar._registered_events.git) do
        if count > 0 then
          log.error("git event %s is still registered with count %s", events.get_event_name(event), count)
        end
      end
      for event, count in pairs(sidebar._registered_events.yatree) do
        if count > 0 then
          log.error("yatree event %s is still registered with count %s", events.get_event_name(event), count)
        end
      end
      log.info("deleted sidebar for tabpage %s", tabpage)
      -- using table.remove will change the key as well, i.e. { 1, 2, 3 } and table.remove(t, 2) will result in { 1, 2 } instead of { 1, 3 }
      M._sidebars[tabpage] = nil
    else
      for _, section in pairs(sidebar._sections) do
        section.tree.root:walk(function(node)
          if node.repo and not found_toplevels[node.repo.toplevel] then
            found_toplevels[node.repo.toplevel] = true
            if not node.repo:is_yadm() then
              return true
            end
          end
        end)
      end
    end
  end

  for toplevel, repo in pairs(git.repos) do
    if not found_toplevels[toplevel] then
      git.remove_repo(repo)
    end
  end
end

---@param config Yat.Config
function M.setup(config)
  events.on_autocmd_event(autocmd_event.TAB_CLOSED, "YA_TREE_SIDEBAR_TAB_CLOSE_CLEANUP", M.delete_sidebars_for_nonexisting_tabpages)

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
      desc = "YaTree DirChanged handler",
    })
  end
end

return M
