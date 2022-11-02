local scheduler = require("plenary.async.util").scheduler
local Path = require("plenary.path")

local git = require("ya-tree.git")
local tree_utils = require("ya-tree.trees.utils")
local ui = require("ya-tree.ui")
local hl = require("ya-tree.ui.highlights")
local utils = require("ya-tree.utils")
local log = require("ya-tree.log")("trees")

local api = vim.api

---@alias Yat.Trees.Type "filesystem" | "buffers" | "git" | "search" | string

---@class Yat.Trees.TreeRenderers
---@field directory Yat.Trees.Ui.Renderer[]
---@field file Yat.Trees.Ui.Renderer[]
---@field extra Yat.Trees.TreeRenderersExtra

---@class Yat.Trees.TreeRenderersExtra
---@field directory_min_diagnostic_severity integer
---@field file_min_diagnostic_severity integer

---@class Yat.Tree
---@field TYPE Yat.Trees.Type
---@field private _tabpage integer
---@field refreshing boolean
---@field root Yat.Node
---@field current_node Yat.Node
---@field supported_actions Yat.Trees.Tree.SupportedActions[]
---@field supported_events { autcmd: Yat.Events.AutocmdEvent[], git: Yat.Events.GitEvent[], yatree: Yat.Events.YaTreeEvent[] }
---@field section_icon string
---@field section_name string
---@field renderers Yat.Trees.TreeRenderers
---@field complete_func string | fun(self: Yat.Tree, bufnr: integer, node: Yat.Node) | false
local Tree = {}
Tree.__index = Tree

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
  return self.TYPE == other.TYPE and self._tabpage == other._tabpage
end

Tree.__tostring = function(self)
  return string.format("(%s, tabpage=%s, root=%s)", self.TYPE, vim.inspect(self._tabpage), tostring(self.root))
end

-- selene: allow(unused_variable)

---@param config Yat.Config
function Tree.setup(config) end

-- selene: allow(unused_variable)

---@generic T : Yat.Tree
---@param class T
---@param tabpage integer
---@param path? string
---@param kwargs? table<string, any>
---@return T tree
---@diagnostic disable-next-line:unused-local
function Tree.new(class, tabpage, path, kwargs)
  ---@type Yat.Tree
  local self = {
    _tabpage = tabpage,
    refreshing = false,
  }
  setmetatable(self, class)
  local config = require("ya-tree.config").config
  self.section_icon = config.trees[self.TYPE].section_icon or ""
  self.section_name = config.trees[self.TYPE].section_name or self.TYPE

  return self
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
  api.nvim_buf_set_option(bufnr, "completefunc", "v:lua._ya_tree_trees_tree_file_in_path_complete")
  api.nvim_buf_set_option(bufnr, "omnifunc", "")
  api.nvim_buf_set_option(bufnr, "path", (node and node.path or self.root.path) .. "/**")
end

function Tree:delete()
  log.info("deleting tree %s", tostring(self))
end

-- selene: allow(unused_variable)

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

      local tabpage = api.nvim_get_current_tabpage()
      return self:is_shown_in_ui(tabpage) and ui.is_node_rendered(tabpage, self, node)
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
    local tabpage = api.nvim_get_current_tabpage()
    local parent = self.root:get_child_if_loaded(Path:new(file):parent().filename)
    if parent then
      parent:refresh()
      local node = parent:get_child_if_loaded(file)
      if node then
        node.modified = false
        if require("ya-tree.config").config.git.enable then
          if node.repo then
            node.repo:refresh_status_for_path(file)
          end
        end
        return self:is_shown_in_ui(tabpage) and ui.is_node_rendered(tabpage, self, node)
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
  if
    vim.v.exiting == vim.NIL
    and (self.root:is_ancestor_of(repo.toplevel) or repo.toplevel:find(self.root.path, 1, true) ~= nil)
    and self:is_shown_in_ui(api.nvim_get_current_tabpage())
  then
    log.debug("git repo %s changed", tostring(repo))
    return true
  end
  return false
end

---@async
---@param severity_changed boolean
---@return boolean
function Tree:on_diagnostics_event(severity_changed)
  return severity_changed and self:is_shown_in_ui(api.nvim_get_current_tabpage())
end

-- selene: allow(unused_variable)

---@async
---@param new_cwd string
function Tree:on_cwd_changed(new_cwd) end

---@return string line
---@return Yat.Ui.HighlightGroup[][] highlights
function Tree:render_header()
  return self.section_icon .. "  " .. self.section_name,
    { { name = hl.SECTION_ICON, from = 0, to = 3 }, { name = hl.SECTION_NAME, from = 5, to = -1 } }
end

---@param config Yat.Config
---@param offset integer
---@return string[] lines
---@return Yat.Ui.HighlightGroup[][] highlights
---@return { [integer]: string, [integer]: string } path_lookup
---@return Yat.Trees.TreeRenderersExtra
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
    lines[linenr], highlights[linenr] = tree_utils.render_node(node, context, has_children and directory_renderers or file_renderers)

    if has_children and node.expanded then
      ---@param child Yat.Node
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

  return lines, highlights, path_lookup, self.renderers.extra
end

---@async
---@param node Yat.Node
---@return boolean
function Tree:check_node_for_repo(node)
  if require("ya-tree.config").config.git.enable then
    local repo = git.create_repo(node.path)
    if repo then
      node:set_git_repo(repo)
      repo:refresh_status({ ignored = true })
      return true
    end
  end
  return false
end

-- selene: allow(unused_variable)

---@async
---@param path string
---@return boolean
---@nodiscard
---@diagnostic disable-next-line:unused-local
function Tree:change_root_node(path)
  return true
end

---@param tabpage integer
---@return boolean
function Tree:is_shown_in_ui(tabpage)
  return ui.is_open(self._tabpage, self) and self:is_for_tabpage(tabpage)
end

---@param tabpage integer
---@return boolean
function Tree:is_for_tabpage(tabpage)
  return self._tabpage == tabpage
end

return Tree
