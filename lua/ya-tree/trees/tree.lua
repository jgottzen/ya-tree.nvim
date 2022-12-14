local Path = require("plenary.path")

local git = require("ya-tree.git")
local meta = require("ya-tree.meta")
local hl = require("ya-tree.ui.highlights")
local utils = require("ya-tree.utils")
local log = require("ya-tree.log")("trees")

local api = vim.api

---@class Yat.Trees.TreeRenderers
---@field directory Yat.Trees.Ui.Renderer[]
---@field file Yat.Trees.Ui.Renderer[]
---@field extra Yat.Trees.TreeRenderersExtra

---@class Yat.Trees.TreeRenderersExtra
---@field directory_min_diagnostic_severity integer
---@field file_min_diagnostic_severity integer

---@alias Yat.Trees.AutocmdEventsLookupTable { [Yat.Events.AutocmdEvent]: async fun(self: Yat.Tree, bufnr: integer, file: string, match: string): boolean }
---@alias Yat.Trees.GitEventsLookupTable { [Yat.Events.GitEvent]: async fun(self: Yat.Tree, repo: Yat.Git.Repo, fs_changes: boolean): boolean }
---@alias Yat.Trees.YaTreeEventsLookupTable { [Yat.Events.YaTreeEvent]: async fun(self: Yat.Tree, ...): boolean }

---@class Yat.Tree : Yat.Object
---@field new async fun(self: Yat.Tree, tabpage: integer, path?: string, kwargs?: table<string, any>): Yat.Tree?
---@overload async fun(tabpage: integer, path?: string, kwargs?: table<string, any>): Yat.Tree?
---@field class fun(self: Yat.Tree): Yat.Tree
---@field private __lower Yat.Tree
---@field static Yat.Tree
---
---@field TYPE Yat.Trees.Type
---@field keymap table<string, Yat.Action>
---@field tabpage integer
---@field refreshing boolean
---@field root Yat.Node
---@field current_node Yat.Node
---@field supported_actions Yat.Trees.Tree.SupportedActions[]
---@field supported_events { autocmd: Yat.Trees.AutocmdEventsLookupTable, git: Yat.Trees.GitEventsLookupTable, yatree: Yat.Trees.YaTreeEventsLookupTable }
---@field section_icon string
---@field section_name string
---@field renderers Yat.Trees.TreeRenderers
---@field complete_func string|fun(self: Yat.Tree, bufnr: integer, node: Yat.Node)|false
---@field on_buffer_enter? async fun(self: Yat.Tree, bufnr: integer, file: string, is_terminal_buffer: boolean): boolean
---@field on_cursor_hold? async fun(self: Yat.Tree, node: Yat.Node, winid: integer)
local Tree = meta.create_class("Yat.Tree")

---@alias Yat.Trees.Tree.SupportedActions
---| "close_window"
---| "system_open"
---| "open_help"
---| "show_node_info"
---| "close_tree"
---| "delete_tree"
---| "focus_prev_tree"
---| "focus_next_tree"
---
---| "open_symbols_tree"
---| "open_git_tree"
---| "open_buffers_tree"
---
---| "open"
---| "vsplit"
---| "split"
---| "tabnew"
---| "preview"
---| "preview_and_focus"
---
---| "copy_name_to_clipboard"
---| "copy_root_relative_path_to_clipboard"
---| "copy_absolute_path_to_clipboard"
---
---| "close_node"
---| "close_all_nodes"
---| "close_all_child_nodes"
---| "expand_all_nodes"
---| "expand_all_child_nodes"
---
---| "refresh_tree"
---
---| "focus_parent"
---| "focus_prev_sibling"
---| "focus_next_sibling"
---| "focus_first_sibling"
---| "focus_last_sibling"

do
  local builtin = require("ya-tree.actions.builtin")
  Tree.supported_actions = utils.tbl_unique({
    builtin.general.close_window,
    builtin.general.system_open,
    builtin.general.open_help,
    builtin.general.show_node_info,
    builtin.general.close_tree,
    builtin.general.delete_tree,
    builtin.general.focus_prev_tree,
    builtin.general.focus_next_tree,

    builtin.general.open_symbols_tree,
    builtin.general.open_git_tree,
    builtin.general.open_buffers_tree,

    builtin.general.open,
    builtin.general.vsplit,
    builtin.general.split,
    builtin.general.tabnew,
    builtin.general.preview,
    builtin.general.preview_and_focus,

    builtin.general.copy_name_to_clipboard,
    builtin.general.copy_root_relative_path_to_clipboard,
    builtin.general.copy_absolute_path_to_clipboard,

    builtin.general.close_node,
    builtin.general.close_all_nodes,
    builtin.general.close_all_child_nodes,
    builtin.general.expand_all_nodes,
    builtin.general.expand_all_child_nodes,

    builtin.general.refresh_tree,

    builtin.general.focus_parent,
    builtin.general.focus_prev_sibling,
    builtin.general.focus_next_sibling,
    builtin.general.focus_first_sibling,
    builtin.general.focus_last_sibling,
  })
end

---@param other Yat.Tree
Tree.__eq = function(self, other)
  return self.TYPE == other.TYPE and self.tabpage == other.tabpage
end

Tree.__tostring = function(self)
  return string.format("(%s, tabpage=%s, root=%s)", self.TYPE, self.tabpage, self.root)
end

-- selene: allow(unused_variable)

---@virtual
---@param config Yat.Config
---@return boolean enabled
---@diagnostic disable-next-line:unused-local,missing-return
function Tree.setup(config) end
Tree:virtual("setup")

---@class Yat.Trees.Ui.Renderer
---@field name Yat.Ui.Renderer.Name
---@field fn Yat.Ui.RendererFunction
---@field config? Yat.Config.BaseRendererConfig

---@param tree_type Yat.Trees.Type
---@param config Yat.Config
---@return Yat.Trees.TreeRenderers
function Tree.create_renderers(tree_type, config)
  local renderers = require("ya-tree.ui.renderers")

  ---@param renderer_type string
  ---@param raw_renderer Yat.Config.Trees.Renderer
  ---@return Yat.Trees.Ui.Renderer|nil renderer
  local function create_renderer(renderer_type, raw_renderer)
    local name = raw_renderer.name
    if type(name) == "string" then
      local renderer_info = renderers.get_renderer(name)
      if renderer_info then
        ---@type Yat.Trees.Ui.Renderer
        local renderer = { name = name, fn = renderer_info.fn, config = vim.deepcopy(renderer_info.config) }
        if raw_renderer.override then
          for k, v in pairs(raw_renderer.override) do
            if type(k) == "string" then
              log.debug("overriding tree_type %s %q renderer %q config value for %q with %s", tree_type, renderer_type, renderer.name, k, v)
              renderer.config[k] = v
            end
          end
        end
        return renderer
      end
    end
    utils.warn("Invalid renderer:\n" .. vim.inspect(raw_renderer))
  end

  local dconf = config.renderers.builtin.diagnostics
  ---@type Yat.Trees.TreeRenderers
  local tree_renderers = {
    directory = {},
    file = {},
    extra = { directory_min_diagnstic_severrity = dconf.directory_min_severity, file_min_diagnostic_severity = dconf.file_min_severity },
  }
  local tree_renderer_config = config.trees[tree_type].renderers

  for _, directory_renderer in ipairs(tree_renderer_config.directory) do
    local renderer = create_renderer("directory", directory_renderer)
    if renderer then
      tree_renderers.directory[#tree_renderers.directory + 1] = renderer
      if renderer.name == "diagnostics" then
        local renderer_config = renderer.config --[[@as Yat.Config.Renderers.Builtin.Diagnostics]]
        tree_renderers.extra.directory_min_diagnostic_severity = renderer_config.directory_min_severity
      end
    end
  end

  for _, file_renderer in ipairs(tree_renderer_config.file) do
    local renderer = create_renderer("file", file_renderer)
    if renderer then
      tree_renderers.file[#tree_renderers.file + 1] = renderer
      if renderer.name == "diagnostics" then
        local renderer_config = renderer.config --[[@as Yat.Config.Renderers.Builtin.Diagnostics]]
        tree_renderers.extra.file_min_diagnostic_severity = renderer_config.file_min_severity
      end
    end
  end

  return tree_renderers
end

---@param config Yat.Config
---@param tree_type Yat.Trees.Type
---@param supported_actions Yat.Actions.Name[]
---@return table<string, Yat.Action>
function Tree.create_mappings(config, tree_type, supported_actions)
  local actions = require("ya-tree.actions").actions

  ---@type table<string, Yat.Action>
  local keymap = {}
  ---@type table<string, Yat.Actions.Name|string>
  local mappings = vim.tbl_deep_extend("force", config.trees.global_mappings.list, config.trees[tree_type].mappings.list)
  for key, name in pairs(mappings) do
    if name == "" then
      log.debug("key %q is disabled by user config", key)
    else
      local action = actions[name]
      if not vim.tbl_contains(supported_actions, name) and not action.user_defined then
        log.error("key %q is mapped to 'action' %q, which tree %q doesn't support, mapping ignored", key, name, tree_type)
        utils.warn(string.format("Key %q is mapped to 'action' %q, which tree %q doesn't support, mapping ignored!", key, name, tree_type))
      else
        if action then
          keymap[key] = action
        else
          log.debug("tree %q action %q is disabled due to dependent feature is disabled", tree_type, name)
        end
      end
    end
  end

  return keymap
end

---@protected
---@param type Yat.Trees.Type
---@param tabpage integer
---@param root Yat.Node
---@param current_node Yat.Node
function Tree:init(type, tabpage, root, current_node)
  self.TYPE = type
  self.tabpage = tabpage
  self.root = root
  self.current_node = current_node
  self.refreshing = false
  local tree_config = require("ya-tree.config").config.trees[self.TYPE]
  self.section_icon = tree_config and tree_config.section_icon or ""
  self.section_name = tree_config and tree_config.section_name or self.TYPE
end

do
  ---@type string[]
  local paths = {}

  -- selene: allow(global_usage)

  ---@param start integer
  ---@param base string
  ---@return integer|string[]
  _G._ya_tree_trees_tree_loaded_nodes_complete = function(start, base)
    if start == 1 then
      return 0
    end
    ---@param item string
    return vim.tbl_filter(function(item)
      return item:find(base, 1, true) ~= nil
    end, paths)
  end

  ---@param bufnr integer
  function Tree:complete_func_loaded_nodes(bufnr)
    local config = require("ya-tree.config").config
    paths = {}
    self.root:walk(function(node)
      if not node:is_directory() and not node:is_hidden(config) then
        paths[#paths + 1] = node.path:sub(#self.root.path + 2)
      end
    end)
    api.nvim_buf_set_option(bufnr, "completefunc", "v:lua._ya_tree_trees_tree_loaded_nodes_complete")
    api.nvim_buf_set_option(bufnr, "omnifunc", "")
  end
end

-- selene: allow(global_usage)

---@param start integer
---@param base string
---@return integer|string[]
_G._ya_tree_trees_tree_file_in_path_complete = function(start, base)
  if start == 1 then
    return 0
  end
  return vim.fn.getcompletion(base, "file_in_path")
end

---@param bufnr integer
---@param node? Yat.Node
function Tree:complete_func_file_in_path(bufnr, node)
  local home = os.getenv("HOME") --[[@as string]]
  local path = node and node.path or self.root.path
  api.nvim_buf_set_option(bufnr, "completefunc", "v:lua._ya_tree_trees_tree_file_in_path_complete")
  api.nvim_buf_set_option(bufnr, "omnifunc", "")
  -- only complete on _all_ files if the node is located below the home dir
  if #path > #home then
    api.nvim_buf_set_option(bufnr, "path", path .. "/**")
  else
    api.nvim_buf_set_option(bufnr, "path", path .. "/*")
  end
end

function Tree:delete()
  log.info("deleting tree %s", tostring(self))
end

---@generic T : Yat.Node
---@param start T
---@param forward boolean
---@return T[]
function Tree:flatten_from(start, forward)
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
function Tree:get_first_node_that_matches(start_node, forward, predicate)
  ---@cast start_node Yat.Node
  local nodes = self:flatten_from(start_node, forward)
  for _, node in ipairs(nodes) do
    if predicate(node) then
      return node
    end
  end
end

-- selene: allow(unused_variable)

---@async
---@param bufnr integer
---@param file string
---@param match string
---@return boolean update
---@diagnostic disable-next-line:unused-local
function Tree:on_buffer_modified(bufnr, file, match)
  if file ~= "" and api.nvim_buf_get_option(bufnr, "buftype") == "" then
    local modified = api.nvim_buf_get_option(bufnr, "modified") --[[@as boolean]]
    local node = self.root:get_child_if_loaded(file)
    if node and node.modified ~= modified then
      node.modified = modified
      return true
    end
  end
  return false
end

-- selene: allow(unused_variable)

---@async
---@param bufnr integer
---@param file string
---@param match string
---@return boolean update
---@diagnostic disable-next-line:unused-local
function Tree:on_buffer_saved(bufnr, file, match)
  if self.root:is_ancestor_of(file) then
    log.debug("changed file %q is in tree %s", file, tostring(self))
    local parent = self.root:get_child_if_loaded(Path:new(file):parent().filename)
    if parent then
      parent:refresh()
      local node = parent:get_child_if_loaded(file)
      if node then
        node.modified = false
        return true
      end
    end
  end
  return false
end

-- selene: allow(unused_variable)

---@async
---@param repo Yat.Git.Repo
---@param fs_changes boolean
---@return boolean update
---@diagnostic disable-next-line:unused-local
function Tree:on_git_event(repo, fs_changes)
  if vim.v.exiting == vim.NIL and (self.root:is_ancestor_of(repo.toplevel) or repo.toplevel:find(self.root.path, 1, true) ~= nil) then
    log.debug("git repo %s changed", tostring(repo))
    return true
  end
  return false
end

-- selene: allow(unused_variable)

---@async
---@param severity_changed boolean
---@return boolean
---@diagnostic disable-next-line:unused-local
function Tree:on_diagnostics_event(severity_changed)
  return severity_changed
end

-- selene: allow(unused_variable)

---@async
---@param new_cwd string
---@diagnostic disable-next-line:unused-local
function Tree:on_cwd_changed(new_cwd) end

---@return string line
---@return Yat.Ui.HighlightGroup[][] highlights
function Tree:render_header()
  return self.section_icon .. "  " .. self.section_name,
    { { name = hl.SECTION_ICON, from = 0, to = 3 }, { name = hl.SECTION_NAME, from = 5, to = -1 } }
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
---@param renderers Yat.Trees.Ui.Renderer[]
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

---@param config Yat.Config
---@param offset integer
---@return string[] lines
---@return Yat.Ui.HighlightGroup[][] highlights
---@return { [integer]: string, [integer]: string } path_lookup
function Tree:render(config, offset)
  ---@type { [integer]: string, [integer]: string }, string[], Yat.Ui.HighlightGroup[][], Yat.Ui.RenderContext
  local path_lookup, lines, highlights, context, linenr = {}, {}, {}, { tree_type = self.TYPE, config = config, indent_markers = {} }, 0
  local directory_renderers, file_renderers = self.renderers.directory, self.renderers.file

  ---@param node Yat.Node
  ---@param depth integer
  ---@param last_child boolean
  local function append_node(node, depth, last_child)
    linenr = linenr + 1
    context.depth = depth
    context.last_child = last_child
    path_lookup[node.path] = linenr + offset
    path_lookup[linenr + offset] = node.path
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

  append_node(self.root, 0, false)

  return lines, highlights, path_lookup
end

---@async
---@param node Yat.Node
---@return Yat.Git.Repo|nil repo
function Tree:check_node_for_repo(node)
  if require("ya-tree.config").config.git.enable then
    local repo = git.create_repo(node.path)
    if repo then
      node:set_git_repo(repo)
      repo:status():refresh({ ignored = true })
      return repo
    end
  end
end

-- selene: allow(unused_variable)

---@async
---@virtual
---@param path string
---@diagnostic disable-next-line:unused-local
function Tree:change_root_node(path) end
Tree:virtual("change_root_node")

return Tree
